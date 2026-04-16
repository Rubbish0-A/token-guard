#!/usr/bin/env bash
# Token Guard - 自动化诊断脚本
# 扫描 Claude Code 配置，输出结构化 JSON 检查结果
# 兼容 Windows (Git Bash) / macOS / Linux

set -euo pipefail

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
# 使用环境变量传递路径，避免 bash/node 转义问题
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

# ── 检查 1：模型配置 ─────────────────────────

check_model() {
  local model=""
  if [ -f "$SETTINGS_FILE" ]; then
    model=$(json_get "$SETTINGS_FILE" "data.model || ''")
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
      message="使用最高成本模型 + 1M 上下文，成本约为 sonnet 的 5 倍"
    fi
  elif echo "$model" | grep -qi "sonnet"; then
    status="pass"
    message="日常开发推荐模型"
  elif echo "$model" | grep -qi "haiku"; then
    status="pass"
    message="轻量模型，适合简单任务"
  fi

  echo "{\"check\":\"model\",\"status\":\"${status}\",\"value\":\"${model}\",\"message\":\"${message}\"}"
}

# ── 检查 2：插件数量与重复 ────────────────────

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

    // 检测重复：提取 @ 前的插件名，找出同一 marketplace 下的不同命名空间
    const byMarket = {};
    enabled.forEach(p => {
      const parts = p.split('@');
      if (parts.length === 2) {
        const market = parts[1];
        if (!byMarket[market]) byMarket[market] = [];
        byMarket[market].push(parts[0]);
      }
    });

    // 已知的重复技能组（这些插件注册相同的技能集）
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

# ── 检查 3：规则文件体积 ──────────────────────

check_rules() {
  if [ ! -d "$RULES_DIR" ]; then
    echo "{\"check\":\"rules\",\"status\":\"pass\",\"totalBytes\":0,\"fileCount\":0,\"message\":\"无规则文件目录\"}"
    return
  fi

  local total_bytes=0
  local file_count=0
  local largest_files=""

  # 统计所有文件大小（兼容不同平台的 stat）
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

  # 取最大的 3 个文件
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

# ── 检查 4：环境变量安全 ──────────────────────

check_env_vars() {
  local issues=0
  local details=""

  # 检查 ANTHROPIC 相关 key
  local anth_key="${ANTHROPIC_API_KEY:-}"
  local anth_token="${ANTHROPIC_AUTH_TOKEN:-}"

  # 检查 OPENAI_API_KEY
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

  # 检查 GEMINI_API_KEY
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

# ── 检查 5：Thinking 预算 ─────────────────────

check_thinking() {
  local budget="${MAX_THINKING_TOKENS:-}"
  local status="pass"
  local message=""

  if [ -z "$budget" ]; then
    status="warn"
    budget="未设置(默认31999)"
    message="Thinking 预算使用默认最大值，建议设为 20000 以平衡能力和成本"
  elif [ "$budget" -gt 25000 ] 2>/dev/null; then
    status="warn"
    message="Thinking 预算较高（${budget}），大部分任务用不到这么多"
  elif [ "$budget" -lt 10000 ] 2>/dev/null; then
    status="info"
    message="Thinking 预算较低（${budget}），复杂推理可能被截断"
  else
    status="pass"
    message="Thinking 预算合理（${budget}）"
  fi

  echo "{\"check\":\"thinking\",\"status\":\"${status}\",\"value\":\"${budget}\",\"message\":\"${message}\"}"
}

# ── 检查 6：危险模式 ──────────────────────────

check_dangerous_mode() {
  local dangerous_procs=0
  local skip_prompt="false"

  # 检查运行中的进程（兼容不同平台）
  if command -v wmic &>/dev/null; then
    # Windows - 用 wmic 更可靠
    dangerous_procs=$(wmic process where "name='node.exe'" get CommandLine 2>/dev/null | grep -c "dangerously-skip-permissions" || true)
    dangerous_procs=$((dangerous_procs + 0))  # 确保是整数
  elif command -v ps &>/dev/null; then
    # macOS / Linux
    dangerous_procs=$(ps aux 2>/dev/null | grep -c "dangerously-skip-permissions" || true)
    # 减去 grep 自身
    dangerous_procs=$((dangerous_procs > 0 ? dangerous_procs - 1 : 0))
  fi

  # 检查 settings.json 中的配置
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

# ── 检查 7：会话健康 ──────────────────────────

check_sessions() {
  local projects_dir="${CLAUDE_DIR}/projects"
  if [ ! -d "$projects_dir" ]; then
    echo "{\"check\":\"sessions\",\"status\":\"pass\",\"message\":\"无项目会话数据\"}"
    return
  fi

  # 统计所有项目的会话数据
  local total_sessions=0
  local total_size_kb=0
  local total_subagents=0
  local aside_count=0
  local aside_large=0
  local largest_session_mb=0
  local issues=""

  for project_dir in "$projects_dir"/*/; do
    [ ! -d "$project_dir" ] && continue

    # 统计 .jsonl 会话文件
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

    # 统计子 agent
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

  # 判断状态
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
echo "  \"version\": \"1.0.0\","
echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%d)\","
echo "  \"results\": ["
echo "    $(check_model),"
echo "    $(check_plugins),"
echo "    $(check_rules),"
echo "    $(check_env_vars),"
echo "    $(check_thinking),"
echo "    $(check_dangerous_mode),"
echo "    $(check_sessions)"
echo "  ]"
echo "}"
