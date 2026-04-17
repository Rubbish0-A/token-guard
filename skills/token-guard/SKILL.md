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

脚本会输出 JSON 格式的检查结果，包含 10 项检查。如果脚本无法执行（权限、路径问题等），则手动执行 Step 1b。

### Step 1b：手动检查（脚本不可用时的备选）

依次执行以下 10 项检查：

**检查 1 — 模型配置**
读取 `~/.claude/settings.json` 中的 `model` 字段。
- opus 或 opus[1m]：标记为 ⚠️（最高成本档位）
- **opus[1m] + effortLevel=max**：标记为 ❌（思考 token 被 1M 上下文复算，成本极高）
- sonnet：标记为 ✅
- haiku：标记为 ✅
- **haiku + effortLevel=xhigh/max**：标记为 ⚠️（小模型无法利用深度思考）

**检查 2 — Effort 配置（Opus 4.7+ 新维度）**
读取 `~/.claude/settings.json` 中的 `effortLevel` 字段。支持五档：
- `low` / `medium` / `high` / `xhigh` / `max`
- **未设置**：使用 Opus 4.7 官方默认 xhigh（ℹ️）
- **max**：⚠️（仅建议架构/安全/深度 debug 临时使用）
- **xhigh**：✅（Opus 4.7 官方默认，编码+agentic 甜点位）
- **high**：ℹ️（4.6 时代默认；4.7 后建议升级到 xhigh）
- **low/medium + opus**：⚠️（档位倒置，应降 model 而非限 effort）

**检查 3 — 插件数量与重复**
读取 `~/.claude/settings.json` 中 `enabledPlugins`，统计 `true` 的数量。
- 检查是否有多个插件注册相同的技能集（如 document-skills、example-skills、claude-api 三个插件都注册了 pdf/docx/xlsx 等相同技能）
- 超过 10 个已启用插件：标记为 ⚠️
- 存在重复技能注册：标记为 ❌

**检查 4 — 规则文件体积**
统计 `~/.claude/rules/` 目录下所有文件的总大小（字节）。
- 超过 15KB：标记为 ⚠️
- 超过 25KB：标记为 ❌
- 同时列出最大的 3 个文件

**检查 5 — 环境变量安全**
检查以下环境变量的值前缀是否与变量名匹配：
- `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN`：应以 `sk-ant-` 或 `cr_` 开头
- `OPENAI_API_KEY`：应以 `sk-` 开头（不是 `AIza`、不是 `cr_`）
- `GEMINI_API_KEY`：应以 `AIza` 开头（不是 `sk-`、不是 `cr_`）
- 如果某个变量的前缀与预期不符，标记为 ❌（交叉污染）
- 所有输出必须 mask：只显示前 5 位 + `...` + 后 4 位

**检查 6 — 危险模式**
检查运行中的 Claude Code 进程是否带 `--dangerously-skip-permissions` 参数。
读取 `~/.claude/settings.json` 中 `skipDangerousModePermissionPrompt` 字段。
- 启用了危险模式：标记为 ⚠️

**检查 7 — 死代码权限（NEW in 1.1.0）**
检测 `permissions.allow` 列表与危险模式的组合。
- `permissions.allow` 非空 且 危险模式启用：标记为 ⚠️（allow 列表被 `--dangerously-skip-permissions` 绕过，是死代码）
- 建议：要么删除 allow 列表，要么切换到默认权限模式

**检查 8 — 规则文件过时指令（NEW in 1.1.0）**
扫描 `~/.claude/rules/**/*.md`、`~/.claude/CLAUDE.md`、`${PWD}/CLAUDE.md`，对照 `references/stale-patterns.json` 定义的模式库。
- 检测已废弃的 env var（如 `MAX_THINKING_TOKENS` 对 Opus 4.7+ 无效）
- 检测过时设置字段（如 `alwaysThinkingEnabled` 在 4.7+ 被 `effortLevel` 取代）
- 检测旧模型版本号引用（如 `Opus 4.5` / `claude-3-sonnet`）
- 任一 `warn` 级别匹配：标记为 ⚠️
- 任一 `fail` 级别匹配：标记为 ❌

**检查 9 — 会话健康**
检查当前项目在 `~/.claude/projects/` 中对应目录的会话数据。
- 统计会话数量和总大小
- 检查是否存在 aside_question 子 agent（episodic-memory 插件产生的记忆搜索 agent，单个可达 15MB+）
- 超过 7 天未活跃的旧会话且总大小超过 50MB：标记为 ⚠️
- 存在超过 10MB 的 aside_question agent：标记为 ⚠️
- 单个会话超过 20MB：标记为 ⚠️（建议 `/compact` 或开新会话）

**检查 10 — Context Rot 风险（NEW in 1.2.0）**
扫描 `~/.claude/projects/*/*.jsonl` 中近 7 天活跃的 session，取每个 session 最后一条 assistant event 的 `usage.input_tokens + cache_read_input_tokens + cache_creation_input_tokens`（模型真实看到的上下文体积，不是磁盘字节数）。
- 依据：Thariq @ Anthropic（Apr 16 2026）指出上下文 ~300-400K tokens 后模型性能下降（context rot），且 auto-compact 在最低智能点执行
- `total_context >= 300K`：⚠️（建议主动 `/compact` 带方向说明，如 `/compact focus on current task`）
- `total_context >= 400K`：❌（深度 rot 区，此时 compact 质量最低，建议 `/clear` + 手写 brief 重开）
- 只标记活跃 session（mtime < 7 天）；僵尸 session 不算风险
- 区别于检查 9：检查 9 看磁盘字节数（单调增长），检查 10 看当前活跃上下文 tokens（compact/rewind 后会缩小），两者是正交信号

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

[✅/⚠️/❌] Effort 配置：[当前 effortLevel]
    [如有问题，一行说明]

[✅/⚠️/❌] 插件状态：[已启用数]个插件，[重复数]组重复
    [如有问题，一行说明]

[✅/⚠️/❌] 规则文件：[总大小]KB
    [如有问题，列出最大的文件]

[✅/⚠️/❌] 环境变量：[正常/发现交叉污染]
    [如有问题，说明哪个变量异常]

[✅/⚠️/❌] 危险模式：[启用/未启用]
    [如有问题，一行说明]

[✅/⚠️/❌] 死代码权限：[allow 列表条数 / 是否冗余]
    [如有问题，一行说明]

[✅/⚠️/❌] 过时指令：[匹配数] 处（扫描 [N] 个文件）
    [如有问题，列出前 3 条匹配，含文件:行号 和 patternId]

[✅/⚠️/❌] 会话健康：[N]个会话，总计[大小]，[N]个 aside_question agent
    [如有问题，一行说明]

[✅/⚠️/❌] Context Rot 风险：[N]个活跃 session，[warn]个接近 rot 区，[fail]个深度 rot
    [如有问题，列出 Top 3 session 的 id 和上下文体积 (如 8d15b0d6: 840K)]

──── 影响估算 ──────────────────────────────────

系统提示开销：约 [N] tokens/轮
  其中技能描述占：约 [N] tokens（[M]条技能 × ~125 tokens）
  其中规则文件占：约 [N] tokens

模型成本系数：[说明当前模型相对 sonnet 的倍数]
Effort 倍数：[说明当前 effort 相对 high 的思考 token 倍数]

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
- 询问某项问题的原因 → 读取 `${CLAUDE_PLUGIN_ROOT}/skills/token-guard/references/pitfall-guide.md` 中对应章节
- 无进一步操作 → 结束

## 快速修复速查表

| 问题 | 修复方案 |
|------|---------|
| 模型为 opus 做日常工作 | `settings.json` 中 `model` 改为 `sonnet`，需要深度推理时临时 `/model opus` |
| opus[1m] + max 组合 | 默认 effortLevel 降到 `xhigh`，架构/安全场景才临时升 `max` |
| effortLevel 未设置 | 无需修复，4.7 默认 xhigh 已是最优起点 |
| opus + low/medium 档位倒置 | 降 model 到 sonnet，而不是限制 opus 思考 |
| haiku + xhigh/max 浪费组合 | 降 effort 到 low/medium（Never Pair 禁区） |
| 插件存在重复技能 | `settings.json` 中将重复插件设为 `false`，保留一个即可 |
| 插件过多 | 全局只保留核心插件，其他按项目在 `项目/.claude/settings.json` 中启用 |
| 规则文件过大 | 将不常用的规则（如 skill-vetter）转为按需加载的 skill |
| 环境变量交叉污染 | 用 `setx VAR ""` 清除错误值，设置正确的 key |
| 危险模式启用 | 移除 `--dangerously-skip-permissions` 启动参数 |
| 死代码 allow 列表 | 若坚持用危险模式，删除 `permissions.allow`；否则关闭危险模式 |
| 过时指令残留 | 按 check 8 报告的文件:行号逐条删除/更新；参考 pitfall 第4章 |
| 会话数据膨胀 | 长会话执行 `/compact` 压缩，或开新会话；定期清理旧会话目录 |
| 子 agent 数量过多 | 检查规则文件是否有"自动触发"指令，改为"建议触发" |
| aside_question 膨胀 | episodic-memory 插件产生的记忆搜索 agent 可达 15MB+，不常用时考虑禁用该插件 |
| 活跃 session >300K tokens | 主动 `/compact focus on current task`（带方向说明避免 bad compact） |
| 活跃 session >400K tokens | `/clear` 后写一份 brief 重开；此时模型已进入 context rot，compact 质量最低 |
| 用 "that didn't work, try X" 修正 | 改用双击 Esc 触发 `/rewind`，从失败点前重开，避免把失败路径污染进上下文 |

## 成本倍数参考（不含具体价格）

### Model 维度

| 模型 | 输入成本倍数 | 输出成本倍数 | 适用场景 |
|------|------------|------------|---------|
| Opus | 5x（基准 Sonnet） | 5x | 复杂架构设计、深度分析 |
| Sonnet | 1x（基准） | 1x | 日常开发、编码、调试 |
| Haiku | ~0.27x | ~0.27x | 子 agent、轻量任务、批处理 |

### Effort 维度（Opus 4.7+，相对 high 的思考 token 倍数估算）

| Effort | 思考 token 倍数 | 触发深度思考概率 | 适用 |
|--------|----------------|------------------|------|
| low | ~0.3x | 极少 | 检索、分类、简单转换 |
| medium | ~0.6x | 较少 | 成本敏感的常规任务 |
| high | 1x（基准） | 中等 | 多数编码、代码审查 |
| xhigh | ~1.5x | 高（含主动回溯） | **默认**，编码+agentic 甜点位 |
| max | ~2x+ | 极高 | 架构/安全/深度 debug |

**关键事实（Opus 4.7）**：low-effort Opus 4.7 已经≈medium-effort Opus 4.6，所以 effort 降档的边际成本节省有限；真正的成本节省杠杆在 model 降档。

### 关键开销公式

- 每个已启用插件的技能描述 ≈ 100-150 tokens 系统提示
- 每个子 agent 独立加载完整系统提示（与主会话同成本）
- 子 agent 应按任务性质选择 model × effort 组合（见 pitfall 第8章）

## 深入参考

如果用户想了解某个坑的详细经历和原理，读取对应章节：

| 章节 | 文件位置 | 涵盖内容 |
|------|---------|---------|
| 第1章 | `${CLAUDE_PLUGIN_ROOT}/skills/token-guard/references/pitfall-guide.md` § 插件管理 | 全量加载机制、重复检测、项目级配置 |
| 第2章 | 同上 § 模型选择 | 能力 vs 成本、场景匹配策略 |
| 第3章 | 同上 § 规则文件 | 规则即 tokens、精简原则、Agent 措辞 |
| 第4章 | 同上 § Reasoning Depth (effort) | effortLevel 五档、Opus 4.7 adaptive reasoning、Never Pair |
| 第5章 | 同上 § 安全与环境变量 | Key 交叉污染、.env 管理 |
| 第6章 | 同上 § 日常维护 | 定期清理、健康检查频率 |
| 第7章 | 同上 § 会话管理 | git commit 作为跨会话记忆、/compact、一任务一会话 |
| 第8章 | 同上 § 子 Agent 失控 | 自动触发→建议触发、model × effort 分档、升级条件、输出规范 |
| 第9章 | 同上 § 模型版本升级污染 | 待累积更多升级案例后补写（v1.1.0 占位） |
| 第10章 | 同上 § Context Rot & Session 卫生 | 300-400K 阈值、每轮5选项（continue/rewind/clear/compact/subagent）、bad compact 失效机理（v1.2.0 占位，依据 Thariq Apr 2026） |
