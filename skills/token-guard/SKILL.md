---
name: token-guard
description: Manually invoked audit tool for Claude Code token efficiency. Use ONLY when the user explicitly types /token-guard or asks to "run token audit", "run token guard", "运行token审计", or "token消耗检查". Do NOT auto-trigger for general conversations about tokens, costs, pricing, or performance optimization.
---

# Token Guard

以身试法的通用 tokens 节省指南——把该踩的坑都踩过了。

这是一个手动触发的 Claude Code token 消耗审计工具。扫描当前配置，定位导致 token 过度消耗的问题，给出修复建议。

## 行为边界

- 默认只读：审计过程只读取配置文件和环境变量，不做任何修改
- 所有 API Key 值必须 mask 处理（只显示前 5 位 + 后 4 位）
- 检查完成后列出可修复项，仅在用户明确要求时才执行修复
- 不要在审计过程中调用其他 skill 或派遣子 agent

## 审计流程

### Step 1：运行诊断脚本

执行打包的诊断脚本获取结构化结果：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit.sh
```

脚本会输出 JSON 格式的检查结果。如果脚本无法执行（权限、路径问题等），则手动执行 Step 1b。

### Step 1b：手动检查（脚本不可用时的备选）

依次执行以下 7 项检查：

**检查 1 — 模型配置**
读取 `~/.claude/settings.json` 中的 `model` 字段。
- opus 或 opus[1m]：标记为 ⚠️（最高成本档位）
- sonnet：标记为 ✅
- haiku：标记为 ✅

**检查 2 — 插件数量与重复**
读取 `~/.claude/settings.json` 中 `enabledPlugins`，统计 `true` 的数量。
- 检查是否有多个插件注册相同的技能集（如 document-skills、example-skills、claude-api 三个插件都注册了 pdf/docx/xlsx 等相同技能）
- 超过 10 个已启用插件：标记为 ⚠️
- 存在重复技能注册：标记为 ❌

**检查 3 — 规则文件体积**
统计 `~/.claude/rules/` 目录下所有文件的总大小（字节）。
- 超过 15KB：标记为 ⚠️
- 超过 25KB：标记为 ❌
- 同时列出最大的 3 个文件

**检查 4 — 环境变量安全**
检查以下环境变量的值前缀是否与变量名匹配：
- `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN`：应以 `sk-ant-` 或 `cr_` 开头
- `OPENAI_API_KEY`：应以 `sk-` 开头（不是 `AIza`、不是 `cr_`）
- `GEMINI_API_KEY`：应以 `AIza` 开头（不是 `sk-`、不是 `cr_`）
- 如果某个变量的前缀与预期不符，标记为 ❌（交叉污染）
- 所有输出必须 mask：只显示前 5 位 + `...` + 后 4 位

**检查 5 — Thinking 预算**
检查环境变量 `MAX_THINKING_TOKENS`。
- 未设置（默认 31999）：标记为 ⚠️
- 大于 25000：标记为 ⚠️
- 10000-25000：标记为 ✅
- 小于 10000：标记为 ℹ️（可能影响深度推理）

**检查 6 — 危险模式**
检查运行中的 Claude Code 进程是否带 `--dangerously-skip-permissions` 参数。
读取 `~/.claude/settings.json` 中 `skipDangerousModePermissionPrompt` 字段。
- 启用了危险模式：标记为 ⚠️

**检查 7 — 会话健康**
检查当前项目在 `~/.claude/projects/` 中对应目录的会话数据。
- 统计会话数量和总大小
- 检查是否存在 aside_question 子 agent（episodic-memory 插件产生的记忆搜索 agent，单个可达 15MB+）
- 超过 7 天未活跃的旧会话且总大小超过 50MB：标记为 ⚠️
- 存在超过 10MB 的 aside_question agent：标记为 ⚠️
- 单个会话超过 20MB：标记为 ⚠️（建议 `/compact` 或开新会话）

### Step 2：生成报告

根据检查结果，使用以下固定模板生成报告：

```
Token Guard 审计报告
═══════════════════════════════════════════════
评分：[🟢 健康 / 🟡 需要关注 / 🔴 严重浪费]
检查时间：[当前日期时间]

──── 检查项 ────────────────────────────────────

[✅/⚠️/❌] 模型配置：[当前模型]
    [如有问题，一行说明]

[✅/⚠️/❌] 插件状态：[已启用数]个插件，[重复数]组重复
    [如有问题，一行说明]

[✅/⚠️/❌] 规则文件：[总大小]KB
    [如有问题，列出最大的文件]

[✅/⚠️/❌] 环境变量：[正常/发现交叉污染]
    [如有问题，说明哪个变量异常]

[✅/⚠️/❌] Thinking 预算：[当前值]
    [如有问题，一行说明]

[✅/⚠️/❌] 危险模式：[启用/未启用]
    [如有问题，一行说明]

[✅/⚠️/❌] 会话健康：[N]个会话，总计[大小]，[N]个 aside_question agent
    [如有问题，一行说明]

──── 影响估算 ──────────────────────────────────

系统提示开销：约 [N] tokens/轮
  其中技能描述占：约 [N] tokens（[M]条技能 × ~125 tokens）
  其中规则文件占：约 [N] tokens

模型成本系数：[说明当前模型相对 sonnet 的倍数]

──── 可修复项 ──────────────────────────────────

[编号列出每个可修复的问题和一行修复方案]

═══════════════════════════════════════════════
如需了解某项问题的原理和踩坑经历，请告诉我章节编号。
```

**评分标准：**
- 🟢 健康：0-1 个 ⚠️，0 个 ❌
- 🟡 需要关注：2-3 个 ⚠️，或 1 个 ❌
- 🔴 严重浪费：4+ 个 ⚠️，或 2+ 个 ❌

### Step 3：等待用户决定

报告输出后，等待用户指令。用户可能：
- 要求修复某项问题 → 执行修复，修改前告知用户具体改什么
- 询问某项问题的原因 → 读取 `${CLAUDE_PLUGIN_ROOT}/references/pitfall-guide.md` 中对应章节
- 无进一步操作 → 结束

## 快速修复速查表

| 问题 | 修复方案 |
|------|---------|
| 模型为 opus 做日常工作 | `settings.json` 中 `model` 改为 `sonnet`，需要深度推理时临时 `/model opus` |
| 插件存在重复技能 | `settings.json` 中将重复插件设为 `false`，保留一个即可 |
| 插件过多 | 全局只保留核心插件，其他按项目在 `项目/.claude/settings.json` 中启用 |
| 规则文件过大 | 将不常用的规则（如 skill-vetter）转为按需加载的 skill |
| 环境变量交叉污染 | 用 `setx VAR ""` 清除错误值，设置正确的 key |
| Thinking 预算过高 | `export MAX_THINKING_TOKENS=20000` 或 `setx MAX_THINKING_TOKENS 20000` |
| 危险模式启用 | 移除 `--dangerously-skip-permissions` 启动参数 |
| 会话数据膨胀 | 长会话执行 `/compact` 压缩，或开新会话；定期清理旧会话目录 |
| 子 agent 数量过多 | 检查规则文件是否有"自动触发"指令，改为"建议触发" |
| aside_question 膨胀 | episodic-memory 插件产生的记忆搜索 agent 可达 15MB+，不常用时考虑禁用该插件 |

## 成本倍数参考（不含具体价格）

| 模型 | 输入成本倍数 | 输出成本倍数 | 适用场景 |
|------|------------|------------|---------|
| Opus | 5x（基准 Sonnet） | 5x | 复杂架构设计、深度分析 |
| Sonnet | 1x（基准） | 1x | 日常开发、编码、调试 |
| Haiku | ~0.27x | ~0.27x | 子 agent、轻量任务、批处理 |

每个已启用插件的技能描述约占 100-150 tokens 系统提示空间，无论是否被使用。
每个子 agent 独立加载完整系统提示，成本与主会话相同。
子 agent 应根据任务性质选择合适的模型（haiku/sonnet/opus），避免所有子 agent 都继承主模型的高成本。

## 深入参考

如果用户想了解某个坑的详细经历和原理，读取对应章节：

| 章节 | 文件位置 | 涵盖内容 |
|------|---------|---------|
| 第1章 | `${CLAUDE_PLUGIN_ROOT}/references/pitfall-guide.md` § 插件管理 | 全量加载机制、重复检测、项目级配置 |
| 第2章 | 同上 § 模型选择 | 能力 vs 成本、场景匹配策略 |
| 第3章 | 同上 § 规则文件 | 规则即 tokens、精简原则、Agent 措辞 |
| 第4章 | 同上 § Thinking 预算 | 上限 vs 实际、推荐配置 |
| 第5章 | 同上 § 安全与环境变量 | Key 交叉污染、.env 管理 |
| 第6章 | 同上 § 日常维护 | 定期清理、健康检查频率 |
| 第7章 | 同上 § 会话管理 | git commit 作为跨会话记忆、/compact、一任务一会话 |
| 第8章 | 同上 § 子 Agent 失控 | 自动触发→建议触发、模型分档、升级条件、输出规范 |
