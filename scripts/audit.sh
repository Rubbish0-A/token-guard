#!/usr/bin/env bash
# Token Guard - 自动化诊断脚本
# 扫描 Claude Code 配置，输出结构化 JSON 检查结果
# 兼容 Windows (Git Bash) / macOS / Linux

set -euo pipefail

# 定位插件根目录，用于读取同级配置文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STALE_PATTERNS_FILE="${PLUGIN_ROOT}/skills/token-guard/references/stale-patterns.json"

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
SETTINGS_LOCAL="${CLAUDE_DIR}/settings.local.json"
RULES_DIR="${CLAUDE_DIR}/rules"

# ── 工具函数 ──────────────────────────────────

mask_key() {
  local val="$1"
  local len=${#val}
  if [ "$len" -le 9 ]; then
    echo "***"
  else
    echo "${val:0:5}...${val: -4}"
  fi
}

# 用 node 解析 JSON（Claude Code 环境保证有 node）
json_get() {
  local file="$1"
  local expr="$2"
  JSON_FILE="$file" node -e "
    try {
      const fs = require('fs');
      const data = JSON.parse(fs.readFileSync(process.env.JSON_FILE, 'utf8'));
      const result = ${expr};
      if (typeof result === 'object') process.stdout.write(JSON.stringify(result));
      else process.stdout.write(String(result));
    } catch(e) { process.stdout.write(''); }
  " 2>/dev/null || echo ""
}

# ── 检查 1：模型配置（含 [1m] + effort 组合识别）──

check_model() {
  local model=""
  local effort=""
  if [ -f "$SETTINGS_FILE" ]; then
    model=$(json_get "$SETTINGS_FILE" "data.model || ''")
    effort=$(json_get "$SETTINGS_FILE" "data.effortLevel || ''")
  fi

  local status="pass"
  local message=""

  if [ -z "$model" ]; then
    status="info"
    message="未在 settings.json 中设置模型（使用默认值）"
    model="default"
  elif echo "$model" | grep -qi "opus"; then
    status="warn"
    message="使用最高成本模型，日常开发建议 sonnet"
    if echo "$model" | grep -qi "1m"; then
      if [ "$effort" = "max" ]; then
        status="fail"
        message="opus[1m] + effortLevel=max：思考 token 被 1M 上下文复算，成本极高，建议默认降 xhigh"
      else
        message="opus + 1M 上下文：系统提示开销放大，确认任务确实跨 200K+ tokens 再用"
      fi
    fi
  elif echo "$model" | grep -qi "sonnet"; then
    status="pass"
    message="日常开发推荐模型"
  elif echo "$model" | grep -qi "haiku"; then
    status="pass"
    message="轻量模型，适合简单任务"
    if [ "$effort" = "xhigh" ] || [ "$effort" = "max" ]; then
      status="warn"
      message="haiku + ${effort}：小模型无法利用深度思考（Never Pair），建议 low/medium"
    fi
  fi

  echo "{\"check\":\"model\",\"status\":\"${status}\",\"value\":\"${model}\",\"effort\":\"${effort}\",\"message\":\"${message}\"}"
}

# ── 检查 2：Effort 配置（Opus 4.7 新维度）────

check_effort_level() {
  local effort=""
  local model=""
  if [ -f "$SETTINGS_FILE" ]; then
    effort=$(json_get "$SETTINGS_FILE" "data.effortLevel || ''")
    model=$(json_get "$SETTINGS_FILE" "data.model || ''")
  fi

  local status="pass"
  local message=""

  if [ -z "$effort" ]; then
    status="info"
    effort="未设置(默认 xhigh)"
    message="未显式设置 effortLevel，使用 Opus 4.7 官方默认值 xhigh（推荐）"
  elif [ "$effort" = "max" ]; then
    status="warn"
    if echo "$model" | grep -qi "1m"; then
      message="effortLevel=max 配合 [1m] 上下文，成本极高。建议默认 xhigh，仅在架构/安全/深度 debug 临时升 max"
    else
      message="effortLevel=max 仅建议用于架构/安全/深度 debug，官方推荐起点为 xhigh"
    fi
  elif [ "$effort" = "xhigh" ]; then
    message="effortLevel=xhigh（Opus 4.7 官方默认，编码+agentic 甜点位）"
  elif [ "$effort" = "high" ]; then
    status="info"
    message="effortLevel=high（4.6 时代默认；4.7 后官方推荐升级到 xhigh）"
  elif [ "$effort" = "medium" ] || [ "$effort" = "low" ]; then
    if echo "$model" | grep -qi "opus"; then
      status="warn"
      message="opus + ${effort}：档位倒置，建议降 model 到 sonnet 而不是限制 opus 思考"
    else
      message="effortLevel=${effort}（适合成本敏感场景）"
    fi
  else
    status="info"
    message="未识别的 effortLevel 值：${effort}（支持 low/medium/high/xhigh/max）"
  fi

  echo "{\"check\":\"effort_level\",\"status\":\"${status}\",\"value\":\"${effort}\",\"message\":\"${message}\"}"
}

# ── 检查 3：插件数量与重复 ────────────────────

check_plugins() {
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "{\"check\":\"plugins\",\"status\":\"info\",\"enabled\":0,\"duplicates\":0,\"message\":\"settings.json 不存在\"}"
    return
  fi

  local result
  result=$(JSON_FILE="$SETTINGS_FILE" node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync(process.env.JSON_FILE, 'utf8'));
    const plugins = data.enabledPlugins || {};
    const enabled = Object.entries(plugins).filter(([k,v]) => v === true).map(([k]) => k);
    const count = enabled.length;

    const byMarket = {};
    enabled.forEach(p => {
      const parts = p.split('@');
      if (parts.length === 2) {
        const market = parts[1];
        if (!byMarket[market]) byMarket[market] = [];
        byMarket[market].push(parts[0]);
      }
    });

    const knownDuplicateGroups = [
      ['document-skills', 'example-skills', 'claude-api']
    ];

    let duplicates = 0;
    let duplicateDetails = [];
    knownDuplicateGroups.forEach(group => {
      const found = enabled.filter(p => group.some(g => p.startsWith(g + '@')));
      if (found.length > 1) {
        duplicates++;
        duplicateDetails.push(found.join(' / '));
      }
    });

    let status = 'pass';
    let message = '';
    if (duplicates > 0) {
      status = 'fail';
      message = '检测到重复技能组: ' + duplicateDetails.join('; ');
    } else if (count > 10) {
      status = 'warn';
      message = '插件数量较多，每个插件的技能描述都会增加系统提示开销';
    } else {
      message = '插件数量合理';
    }

    console.log(JSON.stringify({
      check: 'plugins',
      status,
      enabled: count,
      duplicates,
      enabledList: enabled,
      message
    }));
  " 2>/dev/null)

  echo "$result"
}

# ── 检查 4：规则文件体积 ──────────────────────

check_rules() {
  if [ ! -d "$RULES_DIR" ]; then
    echo "{\"check\":\"rules\",\"status\":\"pass\",\"totalBytes\":0,\"fileCount\":0,\"message\":\"无规则文件目录\"}"
    return
  fi

  local total_bytes=0
  local file_count=0
  local largest_files=""

  local file_sizes=""
  while IFS= read -r -d '' file; do
    local size
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    total_bytes=$((total_bytes + size))
    file_count=$((file_count + 1))
    local basename
    basename=$(basename "$file")
    file_sizes="${file_sizes}${size} ${basename}\n"
  done < <(find "$RULES_DIR" -type f -name "*.md" -print0 2>/dev/null)

  largest_files=$(echo -e "$file_sizes" | sort -rn | head -3 | while read s n; do
    [ -n "$s" ] && echo "${n}(${s}B)"
  done | tr '\n' ', ' | sed 's/,$//')

  local total_kb=$((total_bytes / 1024))
  local status="pass"
  local message=""

  if [ "$total_bytes" -gt 25000 ]; then
    status="fail"
    message="规则文件过大（${total_kb}KB），严重增加每次调用的系统提示开销"
  elif [ "$total_bytes" -gt 15000 ]; then
    status="warn"
    message="规则文件偏大（${total_kb}KB），建议精简或转为按需加载"
  else
    message="规则文件体积合理（${total_kb}KB）"
  fi

  echo "{\"check\":\"rules\",\"status\":\"${status}\",\"totalBytes\":${total_bytes},\"totalKB\":${total_kb},\"fileCount\":${file_count},\"largest\":\"${largest_files}\",\"message\":\"${message}\"}"
}

# ── 检查 5：环境变量安全 ──────────────────────

check_env_vars() {
  local issues=0
  local details=""

  local anth_key="${ANTHROPIC_API_KEY:-}"
  local anth_token="${ANTHROPIC_AUTH_TOKEN:-}"

  local openai_key="${OPENAI_API_KEY:-}"
  if [ -n "$openai_key" ]; then
    local prefix="${openai_key:0:4}"
    if [ "$prefix" = "AIza" ]; then
      issues=$((issues + 1))
      details="${details}OPENAI_API_KEY 存储了 Google key（$(mask_key "$openai_key")）; "
    elif echo "$openai_key" | grep -q "^cr_"; then
      issues=$((issues + 1))
      details="${details}OPENAI_API_KEY 存储了 Anthropic key（$(mask_key "$openai_key")）; "
    fi
  fi

  local gemini_key="${GEMINI_API_KEY:-}"
  if [ -n "$gemini_key" ]; then
    local prefix="${gemini_key:0:3}"
    if [ "$prefix" = "sk-" ] || echo "$gemini_key" | grep -q "^cr_"; then
      issues=$((issues + 1))
      details="${details}GEMINI_API_KEY 存储了非 Google key（$(mask_key "$gemini_key")）; "
    fi
  fi

  local status="pass"
  local message=""
  if [ "$issues" -gt 0 ]; then
    status="fail"
    message="发现 ${issues} 个环境变量交叉污染: ${details}"
  else
    message="未检测到环境变量交叉污染"
  fi

  echo "{\"check\":\"env_vars\",\"status\":\"${status}\",\"issues\":${issues},\"message\":\"${message}\"}"
}

# ── 检查 6：危险模式 ──────────────────────────

check_dangerous_mode() {
  local dangerous_procs=0
  local skip_prompt="false"

  if command -v wmic &>/dev/null; then
    dangerous_procs=$(wmic process where "name='node.exe'" get CommandLine 2>/dev/null | grep -c "dangerously-skip-permissions" || true)
    dangerous_procs=$((dangerous_procs + 0))
  elif command -v ps &>/dev/null; then
    dangerous_procs=$(ps aux 2>/dev/null | grep -c "dangerously-skip-permissions" || true)
    dangerous_procs=$((dangerous_procs > 0 ? dangerous_procs - 1 : 0))
  fi

  if [ -f "$SETTINGS_FILE" ]; then
    skip_prompt=$(json_get "$SETTINGS_FILE" "data.skipDangerousModePermissionPrompt || false")
  fi

  local status="pass"
  local message=""

  if [ "$skip_prompt" = "true" ] || [ "$dangerous_procs" -gt 0 ]; then
    status="warn"
    message="危险模式已启用"
    if [ "$dangerous_procs" -gt 0 ]; then
      message="${message}（${dangerous_procs} 个进程使用 --dangerously-skip-permissions）"
    fi
    if [ "$skip_prompt" = "true" ]; then
      message="${message}，且 skipDangerousModePermissionPrompt=true"
    fi
  else
    message="未启用危险模式"
  fi

  echo "{\"check\":\"dangerous_mode\",\"status\":\"${status}\",\"skipPrompt\":\"${skip_prompt}\",\"dangerousProcs\":${dangerous_procs},\"message\":\"${message}\"}"
}

# ── 检查 7：死代码权限（危险模式下的 allow 冗余）──

check_dead_permissions() {
  local skip_prompt="false"
  local allow_count=0
  local has_dangerous_proc=0

  if [ -f "$SETTINGS_FILE" ]; then
    skip_prompt=$(json_get "$SETTINGS_FILE" "data.skipDangerousModePermissionPrompt || false")
    allow_count=$(json_get "$SETTINGS_FILE" "(data.permissions && data.permissions.allow) ? data.permissions.allow.length : 0")
  fi

  if command -v wmic &>/dev/null; then
    has_dangerous_proc=$(wmic process where "name='node.exe'" get CommandLine 2>/dev/null | grep -c "dangerously-skip-permissions" || true)
    has_dangerous_proc=$((has_dangerous_proc + 0))
  elif command -v ps &>/dev/null; then
    has_dangerous_proc=$(ps aux 2>/dev/null | grep -c "dangerously-skip-permissions" || true)
    has_dangerous_proc=$((has_dangerous_proc > 0 ? has_dangerous_proc - 1 : 0))
  fi

  # 默认值 0 保护
  [ -z "$allow_count" ] && allow_count=0
  allow_count=$((allow_count + 0))

  local status="pass"
  local message=""

  if [ "$allow_count" -gt 0 ] && { [ "$skip_prompt" = "true" ] || [ "$has_dangerous_proc" -gt 0 ]; }; then
    status="warn"
    message="permissions.allow 有 ${allow_count} 条规则，但危险模式已启用，allow 列表被绕过（死代码）"
  elif [ "$allow_count" -eq 0 ]; then
    message="无 permissions.allow 列表"
  else
    message="permissions.allow 有 ${allow_count} 条规则，在默认权限模式下有效"
  fi

  echo "{\"check\":\"dead_permissions\",\"status\":\"${status}\",\"allowCount\":${allow_count},\"skipPrompt\":\"${skip_prompt}\",\"message\":\"${message}\"}"
}

# ── 检查 8：规则文件过时指令（NEW in 1.1.0）──

check_stale_rules() {
  if [ ! -f "$STALE_PATTERNS_FILE" ]; then
    echo "{\"check\":\"stale_rules\",\"status\":\"info\",\"matches\":0,\"message\":\"stale-patterns.json 未找到，跳过检查\"}"
    return
  fi

  # 收集所有自动加载文件路径
  local file_list=""

  if [ -d "$RULES_DIR" ]; then
    while IFS= read -r -d '' f; do
      file_list="${file_list}${f}"$'\n'
    done < <(find "$RULES_DIR" -type f -name "*.md" -print0 2>/dev/null)
  fi

  [ -f "${CLAUDE_DIR}/CLAUDE.md" ] && file_list="${file_list}${CLAUDE_DIR}/CLAUDE.md"$'\n'
  [ -f "${PWD}/CLAUDE.md" ] && file_list="${file_list}${PWD}/CLAUDE.md"$'\n'

  local result
  result=$(PATTERNS_FILE="$STALE_PATTERNS_FILE" FILE_LIST="$file_list" HOME_DIR="$HOME" node -e "
    const fs = require('fs');
    let patternsConfig;
    try {
      patternsConfig = JSON.parse(fs.readFileSync(process.env.PATTERNS_FILE, 'utf8'));
    } catch (e) {
      console.log(JSON.stringify({check:'stale_rules',status:'info',matches:0,message:'stale-patterns.json 解析失败: ' + e.message}));
      process.exit(0);
    }

    const patterns = patternsConfig.patterns.map(p => ({
      id: p.id,
      regex: new RegExp(p.regex),
      severity: p.severity,
      message: p.message
    }));

    const files = (process.env.FILE_LIST || '').split('\n').filter(f => f.trim());
    const matches = [];
    const homeDir = process.env.HOME_DIR || '';

    files.forEach(file => {
      try {
        const content = fs.readFileSync(file, 'utf8');
        const lines = content.split('\n');
        patterns.forEach(p => {
          lines.forEach((line, idx) => {
            if (p.regex.test(line)) {
              matches.push({
                patternId: p.id,
                severity: p.severity,
                file: homeDir ? file.replace(homeDir, '~') : file,
                line: idx + 1,
                excerpt: line.trim().slice(0, 100)
              });
            }
          });
        });
      } catch (e) {}
    });

    const warnCount = matches.filter(m => m.severity === 'warn').length;
    const failCount = matches.filter(m => m.severity === 'fail').length;
    const infoCount = matches.filter(m => m.severity === 'info').length;

    let status = 'pass';
    let message = '未检测到过时指令';
    if (failCount > 0) {
      status = 'fail';
      message = \`发现 \${failCount} 处严重过时引用（warn \${warnCount}, info \${infoCount}）\`;
    } else if (warnCount > 0) {
      status = 'warn';
      message = \`发现 \${warnCount} 处过时引用（info \${infoCount}），大版本升级后仍在污染上下文\`;
    } else if (infoCount > 0) {
      status = 'info';
      message = \`发现 \${infoCount} 处版本号漂移（非致命，建议更新）\`;
    }

    console.log(JSON.stringify({
      check: 'stale_rules',
      status,
      filesScanned: files.length,
      matches: matches.length,
      details: matches.slice(0, 10),
      message
    }));
  " 2>/dev/null)

  if [ -z "$result" ]; then
    echo "{\"check\":\"stale_rules\",\"status\":\"info\",\"matches\":0,\"message\":\"扫描异常\"}"
  else
    echo "$result"
  fi
}

# ── 检查 9：会话健康 ──────────────────────────

check_sessions() {
  local projects_dir="${CLAUDE_DIR}/projects"
  if [ ! -d "$projects_dir" ]; then
    echo "{\"check\":\"sessions\",\"status\":\"pass\",\"message\":\"无项目会话数据\"}"
    return
  fi

  local total_sessions=0
  local total_size_kb=0
  local total_subagents=0
  local aside_count=0
  local aside_large=0
  local largest_session_mb=0

  for project_dir in "$projects_dir"/*/; do
    [ ! -d "$project_dir" ] && continue

    while IFS= read -r -d '' session_file; do
      total_sessions=$((total_sessions + 1))
      local size_kb
      size_kb=$(( $(wc -c < "$session_file" 2>/dev/null || echo 0) / 1024 ))
      total_size_kb=$((total_size_kb + size_kb))

      local size_mb=$((size_kb / 1024))
      if [ "$size_mb" -gt "$largest_session_mb" ]; then
        largest_session_mb=$size_mb
      fi
    done < <(find "$project_dir" -maxdepth 1 -name "*.jsonl" -print0 2>/dev/null)

    for subdir in "$project_dir"/*/subagents/; do
      [ ! -d "$subdir" ] && continue
      while IFS= read -r -d '' agent_file; do
        total_subagents=$((total_subagents + 1))
        local agent_name
        agent_name=$(basename "$agent_file")
        if echo "$agent_name" | grep -q "aside_question"; then
          aside_count=$((aside_count + 1))
          local agent_size_mb
          agent_size_mb=$(( $(wc -c < "$agent_file" 2>/dev/null || echo 0) / 1048576 ))
          if [ "$agent_size_mb" -ge 10 ]; then
            aside_large=$((aside_large + 1))
          fi
        fi
      done < <(find "$subdir" -name "*.jsonl" -print0 2>/dev/null)
    done
  done

  local total_size_mb=$((total_size_kb / 1024))
  local status="pass"
  local message=""

  local warning_reasons=""
  if [ "$total_size_mb" -gt 200 ]; then
    warning_reasons="${warning_reasons}总会话数据 ${total_size_mb}MB 偏大; "
  fi
  if [ "$aside_large" -gt 0 ]; then
    warning_reasons="${warning_reasons}${aside_large} 个 aside_question agent 超过 10MB; "
  fi
  if [ "$largest_session_mb" -gt 20 ]; then
    warning_reasons="${warning_reasons}最大单个会话 ${largest_session_mb}MB，建议 /compact; "
  fi

  if [ -n "$warning_reasons" ]; then
    status="warn"
    message="$warning_reasons"
  else
    message="${total_sessions} 个会话，${total_size_mb}MB，${total_subagents} 个子agent（${aside_count} 个 aside_question）"
  fi

  echo "{\"check\":\"sessions\",\"status\":\"${status}\",\"totalSessions\":${total_sessions},\"totalSizeMB\":${total_size_mb},\"subagents\":${total_subagents},\"asideQuestions\":${aside_count},\"asideLarge\":${aside_large},\"largestSessionMB\":${largest_session_mb},\"message\":\"${message}\"}"
}

# ── 主流程 ────────────────────────────────────

echo "{"
echo "  \"tool\": \"token-guard\","
echo "  \"version\": \"1.1.1\","
echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%d)\","
echo "  \"results\": ["
echo "    $(check_model),"
echo "    $(check_effort_level),"
echo "    $(check_plugins),"
echo "    $(check_rules),"
echo "    $(check_env_vars),"
echo "    $(check_dangerous_mode),"
echo "    $(check_dead_permissions),"
echo "    $(check_stale_rules),"
echo "    $(check_sessions)"
echo "  ]"
echo "}"
