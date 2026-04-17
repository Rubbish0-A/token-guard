<div align="center">

中文 | <a href="README.md">English</a>

<img src="assets/banner.png" alt="Token Guard Banner" width="100%">

# Token Guard

**以身试法的通用 Tokens 节省指南 — 把该踩的坑都踩过了**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://github.com/Rubbish0-A/token-guard)
[![Version](https://img.shields.io/badge/version-1.2.0-green)](https://github.com/Rubbish0-A/token-guard)

[安装](#-安装) · [使用](#-使用) · [检查项](#-检查项) · [踩坑指南](#-踩坑指南)

</div>

---

<table>
<tr>
<td align="center"><strong>15.6 亿</strong><br><sub>16 天消耗 Tokens</sub></td>
<td align="center"><strong>9,000</strong><br><sub>API 请求数</sub></td>
<td align="center"><strong>$1,700+</strong><br><sub>费用</sub></td>
<td align="center"><strong>1.33 亿</strong><br><sub>输入 Tokens</sub></td>
</tr>
</table>

> 用 Opus 全力 vibe coding 半个月——然后我们问了一个问题：*tokens 都去哪了？*
>
> 这个插件就是答案。每一项检查、每一个踩坑经验、每一条优化建议，都是用真金白银换来的，来自对一个超高强度生产环境的系统性排查。

---

## 这是什么？

一个 **Claude Code 插件**，审计你的 token 消耗，精准定位钱花在了哪里。

不是纸上谈兵。所有内容来自真实重度使用环境——半个月消耗 **15.6 亿 tokens** 的实战排查。

### 隐形的成本爆炸

Claude Code 的 token 成本会因为隐蔽的配置问题悄然爆炸：

| 问题 | 影响 |
|------|------|
| 18 个插件全部启用 | 每次 API 调用注入 120+ 条技能描述（每轮浪费 ~15,000 tokens） |
| 插件三重复制 | 3 个插件注册完全相同的技能（pdf、docx、xlsx 各出现 3 次） |
| 强制 Agent 调度 | 规则强制每个任务派 3-5 个子 agent，每个都在 Opus 上重载完整系统提示 |
| API Key 交叉污染 | Anthropic 密钥存在 `GEMINI_API_KEY` 里，被发送到 Google 端点 |
| 会话膨胀 | 单个会话 78MB，记忆搜索 agent 膨胀到 15MB/个 |
| 无模型分档 | 所有子 agent 继承 Opus 定价，做 Haiku 能做的事 |

**优化前每轮系统提示开销 ~$0.52 → 优化后 ~$0.04 — 降低 93%。**

---

## ▸ 安装

```bash
claude plugin add Rubbish0-A/token-guard
```

<details>
<summary>手动安装</summary>

```bash
git clone git@github.com:Rubbish0-A/token-guard.git ~/.claude/plugins/local/token-guard
```

</details>

## ▸ 使用

```
/token-guard
```

Token Guard 扫描你的配置，输出带评分的审计报告：

<details>
<summary><strong>报告示例</strong></summary>

```
Token Guard 审计报告
═══════════════════════════════════════════════
评分：🟡 需要关注
检查时间：2026-04-17 10:30:00

──── 检查项 ────────────────────────────────────

⚠️ 模型配置：opus[1m]（1M 上下文，确认任务跨 200K+ tokens 再用）
✅ Effort 配置：xhigh（Opus 4.7 官方默认）
❌ 插件状态：18 个已启用，检测到 1 组重复
    → document-skills / example-skills / claude-api 注册相同技能
⚠️ 规则文件：23KB（建议 < 15KB）
    → 最大：agents.md(5958B), skill-vetter.md(4699B)
✅ 环境变量：未检测到交叉污染
⚠️ 危险模式：skipDangerousModePermissionPrompt=true
✅ 死代码权限：无冗余 allow 列表
⚠️ 过时指令：performance.md 中 3 处匹配
    → 第40行：MAX_THINKING_TOKENS（Opus 4.7+ 已废弃）
    → 第39行：alwaysThinkingEnabled（被 effortLevel 取代）
⚠️ 会话健康：总计 236MB，45 个 aside_question agent，最大 48MB
❌ Context Rot 风险：30 个活跃 session，3 个接近 rot 区（warn），3 个深度 rot（fail）
    → Top 3 offender: 8d15b0d6 (840K tokens)、d483af3d (614K)、5c72d6bf (492K)

──── 影响估算 ──────────────────────────────────

系统提示开销：约 25,000 tokens/轮
  技能描述占：约 15,000 tokens（120 条 × ~125）
  规则文件占：约 6,000 tokens

Model 成本系数：5x Sonnet 基准（Opus）
Effort 成本系数：~1.5x high 基准（xhigh）

──── 可修复项 ──────────────────────────────────

1. 禁用重复插件（每轮省 ~10,000 tokens）
2. 精简规则文件或转为按需加载
3. 清理旧会话数据（/compact 或开新会话）
4. 删除 MAX_THINKING_TOKENS 引用（对 Opus 4.7+ 无效）

═══════════════════════════════════════════════
```

</details>

## ▸ 检查项

| # | 检查项 | 检测内容 |
|:---:|--------|---------|
| 1 | **模型配置** | 是否用 Opus 做日常开发；`opus[1m] + effort=max` 成本陷阱 |
| 2 | **Effort 配置** 🆕 | `effortLevel` 误配（Opus 4.7+ 新维度）；Never-Pair 禁区如 `haiku × max` |
| 3 | **插件重复** | 插件过多、三重复制技能注册 |
| 4 | **规则文件体积** | 规则膨胀导致系统提示开销增大 |
| 5 | **环境变量安全** | API Key 存错变量（交叉污染） |
| 6 | **危险模式** | `--dangerously-skip-permissions` 开启无限制执行 |
| 7 | **死代码权限** 🆕 | 危险模式下残留的 `permissions.allow` 列表（被完全绕过） |
| 8 | **规则过时指令** 🆕 | 自动加载的规则文件中残留的废弃指令（如 Opus 4.7 后的 `MAX_THINKING_TOKENS`） |
| 9 | **会话健康** | 会话膨胀、aside_question agent 膨胀、陈旧数据 |
| 10 | **Context Rot 风险** 🆕 | 近 7 天活跃 session 是否进入 300-400K tokens 的 context rot 区（依据 Thariq @ Anthropic, 2026-04）——基于 `input + cache_read + cache_creation`，而非磁盘字节数 |

> 🆕 **v1.1.0** 引入（effort / dead-permissions / stale-rules）与 **v1.2.0** 引入（context-rot-risk）。过时指令检查对照 `references/stale-patterns.json`，遇到新的废弃指令欢迎 PR 贡献。

### 自动化诊断脚本

内含 `scripts/audit.sh` — 跨平台 Bash 脚本，10 项检查输出结构化 JSON。Claude 读取后生成可读报告，脚本不可用时回退到手动检查。

<details>
<summary>JSON 输出示例</summary>

```json
{
  "tool": "token-guard",
  "version": "1.2.0",
  "results": [
    {"check": "model", "status": "warn", "value": "opus[1m]", "effort": "xhigh"},
    {"check": "effort_level", "status": "pass", "value": "xhigh"},
    {"check": "plugins", "status": "warn", "enabled": 16, "duplicates": 0},
    {"check": "rules", "status": "warn", "totalKB": 23},
    {"check": "env_vars", "status": "fail", "issues": 2},
    {"check": "dangerous_mode", "status": "warn", "dangerousProcs": 1},
    {"check": "dead_permissions", "status": "pass", "allowCount": 0},
    {"check": "stale_rules", "status": "warn", "matches": 3, "details": [{"patternId": "max-thinking-tokens", "file": "~/.claude/rules/common/performance.md", "line": 40}]},
    {"check": "sessions", "status": "warn", "totalSizeMB": 236},
    {"check": "context_rot_risk", "status": "fail", "activeSessions": 30, "warnCount": 3, "failCount": 3, "topOffenders": [{"session": "8d15b0d6", "context": 839610, "level": "fail"}]}
  ]
}
```

</details>

## ▸ 踩坑指南

8 章基于真实事件 + 2 章占位（后续版本补全）。每章：发生了什么 → 为什么 → 消耗影响 → 规范做法。

| 章 | 标题 | 核心教训 |
|:---:|------|---------|
| 1 | **插件管理** | 所有技能描述每次调用都加载——即使你没用到 |
| 2 | **模型选择** | 用 Opus 做所有事 = 用火箭送外卖 |
| 3 | **规则文件** | 你写的每条规则，每轮对话都要付费 |
| 4 | **Reasoning Depth (effort)** 🔄 | `MAX_THINKING_TOKENS` 在 Opus 4.7+ 已废弃，改用 `effortLevel` 五档 |
| 5 | **安全与环境变量** | Key 存错变量 = Key 被发到错误的服务商 |
| 6 | **日常维护** | 配置只增不减——没有自动清理机制 |
| 7 | **会话管理** | git commit 才是跨会话记忆，不是长对话 |
| 8 | **子 Agent 失控** 🔄 | "自动触发" = 3-5 个 agent × 完整系统提示 × Opus 定价，v1.1 新增 model × effort 矩阵 |
| 9 | **升级漂移** 🆕 | *（占位）* 模型版本升级留下陈旧配置，持续污染后续上下文 |
| 10 | **Context Rot & 会话卫生** 🆕 | *（v1.2.0 占位）* 300-400K 是 rot 区；rewind > 纠正；proactive /compact 优于 auto-compact（依据 Thariq, 2026-04） |

> 🔄 = v1.1.0 重写的章节。🆕 = v1.1.0 新增占位（第 9 章）与 v1.2.0 新增占位（第 10 章），待累积更多案例后补全。

## ▸ 成本倍数参考

不含绝对价格——只用倍数关系，不随调价过时。

### Model 维度

| 模型 | 输入 | 输出 | 适用场景 |
|------|:----:|:----:|---------|
| **Opus** | 5x | 5x | 架构设计、深度推理 |
| **Sonnet** | 1x | 1x | 日常编码、调试 |
| **Haiku** | ~0.27x | ~0.27x | 子 agent、检索、批处理 |

### Effort 维度（Opus 4.7+）

| Effort | 思考 token 倍数（vs high） | 触发深度思考概率 | 适用 |
|--------|:-----:|:------:|------|
| `low` | ~0.3x | 极少 | 检索、分类 |
| `medium` | ~0.6x | 较少 | 成本敏感常规任务 |
| `high` | 1x（基准） | 中等 | 编码、review |
| `xhigh` | ~1.5x | 高（含主动回溯） | **默认**，编码+agentic |
| `max` | ~2x+ | 极高 | 架构、安全、深度 debug |

> **关键事实**：`low-effort Opus 4.7 ≈ medium-effort Opus 4.6`。effort 降档在 Opus 上的边际收益递减。真正的成本杠杆是 **model 降档**（sonnet/haiku），不是 effort 降档。

## ▸ 子 Agent 分档策略（model × effort）

| 任务 | 模型 | Effort | 升级条件 |
|------|:----:|:-----:|---------|
| 搜文件、git log | Haiku | low | 结果不可靠 |
| 简单编辑、重命名 | Haiku/Sonnet | medium | — |
| CRUD、测试、重构 | Sonnet | high | 变更跨 3+ 文件 |
| Code review（小 diff） | Sonnet | high | 认证/支付/安全/迁移 |
| 复杂编码 | Opus | xhigh | **xhigh 浅薄 → max** |
| 架构、深度 review | Opus | max | — |

### Never Pair 禁区

- `haiku × {xhigh, max}` — 小模型无法利用深度思考
- `opus × low` — 档位倒置，应降 model 到 sonnet
- `[1m] × max` 用于常规任务 — 思考 token 被全上下文复算

## ▸ 新同事入职指南

包含 `onboarding-checklist.md` — 新同事入职当天就能用的配置清单，从第一天就避免浪费。

## 参与贡献

欢迎提 Issue 和 PR。发现了新的 token 消耗陷阱？[开个 issue](https://github.com/Rubbish0-A/token-guard/issues) — 我们会加到指南里。

## 协议

[MIT](LICENSE)

---

<div align="center">

**15.6 亿 tokens · $1,700 · 16 天**

*这里记录的每一个坑，都是真金白银踩出来的。*

**点个 Star，让别人不用再交同样的学费。**

</div>
