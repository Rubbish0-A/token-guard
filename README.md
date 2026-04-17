<div align="center">

<a href="README.zh-CN.md">中文</a> | English

<img src="assets/banner.png" alt="Token Guard Banner" width="100%">

# Token Guard

**The Claude Code Token Efficiency Guide — Learned the Hard Way**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://github.com/Rubbish0-A/token-guard)
[![Version](https://img.shields.io/badge/version-1.1.0-green)](https://github.com/Rubbish0-A/token-guard)

[Installation](#-installation) · [Usage](#-usage) · [What It Checks](#-what-it-checks) · [Pitfall Guide](#-pitfall-guide)

</div>

---

<table>
<tr>
<td align="center"><strong>1.56B</strong><br><sub>Tokens in 16 days</sub></td>
<td align="center"><strong>9,000</strong><br><sub>API Requests</sub></td>
<td align="center"><strong>$1,700+</strong><br><sub>Cost</sub></td>
<td align="center"><strong>133M</strong><br><sub>Input Tokens</sub></td>
</tr>
</table>

> Heavy vibe-coding at max intensity with Opus — and then we asked: *where did all the tokens go?*
>
> This plugin is the answer. Every check, every pitfall, every optimization was paid for in real tokens, discovered through systematic forensic analysis of a production Claude Code environment running at extreme scale.

---

## What Is This?

A **Claude Code plugin** that audits your token consumption and tells you exactly where your money is going.

Not theory. Built from real forensic analysis of a heavy-usage environment that burned through **1.56 billion tokens** in half a month.

### The Silent Cost Explosion

Claude Code token costs can silently explode due to misconfigurations invisible during normal use:

| Problem | Impact |
|---------|--------|
| 18 plugins enabled | 120+ skill descriptions in every API call (~15,000 tokens/turn wasted) |
| Triplicate plugins | 3 plugins registering identical skills (pdf, docx, xlsx appear 3x each) |
| Mandatory agent dispatch | Rules forcing 3-5 sub-agents per task, each reloading full system prompt on Opus |
| API key cross-contamination | Anthropic keys stored in `GEMINI_API_KEY`, sent to Google endpoints |
| Session bloat | Single sessions reaching 78MB, memory-search agents growing to 15MB each |
| No model tiering | Every sub-agent inheriting Opus pricing for tasks Haiku could handle |

**Result: ~$0.52/turn in system prompt overhead → ~$0.04/turn after optimization — 93% reduction.**

---

## ▸ Installation

```bash
claude plugin add Rubbish0-A/token-guard
```

<details>
<summary>Manual installation</summary>

```bash
git clone git@github.com:Rubbish0-A/token-guard.git ~/.claude/plugins/local/token-guard
```

</details>

## ▸ Usage

```
/token-guard
```

That's it. Token Guard scans your configuration and outputs a scored audit report:

<details>
<summary><strong>Example Report Output</strong></summary>

```
Token Guard Audit Report
═══════════════════════════════════════════════
Score: 🟡 Needs Attention
Time: 2026-04-17 10:30:00

──── Checks ────────────────────────────────────

⚠️ Model: opus[1m] (1M context — confirm task spans >200K tokens)
✅ Effort Level: xhigh (Opus 4.7 recommended default)
❌ Plugins: 18 enabled, 1 duplicate group detected
    → document-skills / example-skills / claude-api register identical skills
⚠️ Rules: 23KB (recommend < 15KB)
    → Largest: agents.md(5958B), skill-vetter.md(4699B)
✅ Env Vars: No cross-contamination detected
⚠️ Dangerous Mode: skipDangerousModePermissionPrompt=true
✅ Dead Permissions: no dead allow-list entries
⚠️ Stale Rules: 3 matches in performance.md
    → Line 40: MAX_THINKING_TOKENS (deprecated in Opus 4.7+)
    → Line 39: alwaysThinkingEnabled (superseded by effortLevel)
⚠️ Sessions: 236MB total, 45 aside_question agents, largest 48MB

──── Impact ────────────────────────────────────

System prompt overhead: ~25,000 tokens/turn
  Skill descriptions: ~15,000 tokens (120 skills × ~125)
  Rules files: ~6,000 tokens

Model cost: 5x Sonnet baseline (Opus)
Effort cost: ~1.5x high baseline (xhigh)

──── Fixable Items ─────────────────────────────

1. Disable duplicate plugins (save ~10,000 tokens/turn)
2. Reduce rules files or convert to on-demand skills
3. Clean old session data (/compact or start new sessions)
4. Remove MAX_THINKING_TOKENS references (no effect on Opus 4.7+)

═══════════════════════════════════════════════
```

</details>

## ▸ What It Checks

| # | Check | What It Detects |
|:---:|-------|-----------------|
| 1 | **Model Config** | Opus as default for daily work; `opus[1m] + effort=max` cost trap |
| 2 | **Effort Level** 🆕 | `effortLevel` misconfig (Opus 4.7+); Never-Pair combos like `haiku × max` |
| 3 | **Plugin Duplicates** | Too many plugins, triplicate skill registrations |
| 4 | **Rules File Size** | Bloated rules inflating every API call's system prompt |
| 5 | **Env Var Safety** | API keys stored in wrong variables (cross-contamination) |
| 6 | **Dangerous Mode** | `--dangerously-skip-permissions` enabling unrestricted execution |
| 7 | **Dead Permissions** 🆕 | Redundant `permissions.allow` list under dangerously-skip mode |
| 8 | **Stale Rules** 🆕 | Deprecated tokens in auto-loaded rules files (e.g. `MAX_THINKING_TOKENS` after Opus 4.7) |
| 9 | **Session Health** | Session bloat, aside_question agent inflation, stale data |

> 🆕 marks checks introduced in **v1.1.0**. The stale-rules check scans your rules files against a maintained pattern library at `references/stale-patterns.json` — contribute a pattern when you hit a new deprecation.

### Automated Diagnostic Script

Includes `scripts/audit.sh` — cross-platform Bash script outputting structured JSON for all 9 checks. Claude reads the JSON and generates the human-friendly report. Falls back to manual checks if the script can't run.

<details>
<summary>JSON output example</summary>

```json
{
  "tool": "token-guard",
  "version": "1.1.0",
  "results": [
    {"check": "model", "status": "warn", "value": "opus[1m]", "effort": "xhigh"},
    {"check": "effort_level", "status": "pass", "value": "xhigh"},
    {"check": "plugins", "status": "warn", "enabled": 16, "duplicates": 0},
    {"check": "rules", "status": "warn", "totalKB": 23},
    {"check": "env_vars", "status": "fail", "issues": 2},
    {"check": "dangerous_mode", "status": "warn", "dangerousProcs": 1},
    {"check": "dead_permissions", "status": "pass", "allowCount": 0},
    {"check": "stale_rules", "status": "warn", "matches": 3, "details": [{"patternId": "max-thinking-tokens", "file": "~/.claude/rules/common/performance.md", "line": 40}]},
    {"check": "sessions", "status": "warn", "totalSizeMB": 236}
  ]
}
```

</details>

## ▸ Pitfall Guide

8 chapters based on real incidents + 1 placeholder for upcoming content. Each chapter: what happened → why → cost impact → correct approach.

| Ch | Title | Key Lesson |
|:---:|-------|------------|
| 1 | **Plugin Management** | All skill descriptions load on every call — even unused ones |
| 2 | **Model Selection** | Opus for everything = rocket delivery for pizza |
| 3 | **Rules & System Prompt** | Every rule you write is tokens you pay for, every turn |
| 4 | **Reasoning Depth (effort)** 🔄 | `MAX_THINKING_TOKENS` is dead in Opus 4.7+; use `effortLevel` five-tier |
| 5 | **Security & Env Vars** | Keys in wrong variables get sent to wrong providers |
| 6 | **Maintenance** | Config only grows — nothing auto-cleans |
| 7 | **Session Management** | Git commit is your cross-session memory, not long conversations |
| 8 | **Sub-Agent Explosion** 🔄 | "Auto-dispatch" = 3-5 agents × full system prompt × Opus pricing — now with model × effort matrix |
| 9 | **Upgrade Drift** 🆕 | *(placeholder)* Model version upgrades leave behind stale config that keeps polluting context |

> 🔄 = chapter rewritten in v1.1.0. 🆕 = placeholder added in v1.1.0, full content after more upgrade cycles accumulate.

## ▸ Cost Model

No absolute prices — ratios that stay valid as pricing changes.

### Model Dimension

| Model | Input | Output | Best For |
|-------|:-----:|:------:|----------|
| **Opus** | 5x | 5x | Architecture, deep reasoning |
| **Sonnet** | 1x | 1x | Daily coding, debugging |
| **Haiku** | ~0.27x | ~0.27x | Sub-agents, retrieval, batch |

### Effort Dimension (Opus 4.7+)

| Effort | Thinking Tokens (vs high) | Depth-Thinking Probability | Best For |
|--------|:-----:|:------:|----------|
| `low` | ~0.3x | Almost never | Retrieval, classification |
| `medium` | ~0.6x | Rare | Cost-sensitive routine |
| `high` | 1x (baseline) | Moderate | Coding, review |
| `xhigh` | ~1.5x | High (with backtracking) | **Default** — coding + agentic |
| `max` | ~2x+ | Very high | Architecture, security, deep debug |

> **Key fact**: `low-effort Opus 4.7 ≈ medium-effort Opus 4.6`. So effort-downgrade on Opus has diminishing returns. The real lever is **model downgrade** (sonnet/haiku), not effort-downgrade.

## ▸ Sub-Agent Strategy (model × effort)

| Task | Model | Effort | Escalate When |
|------|:-----:|:-----:|---------------|
| File search, git log | Haiku | low | Results unreliable |
| Simple edit, rename | Haiku/Sonnet | medium | — |
| CRUD, tests, refactor | Sonnet | high | Changes span 3+ files |
| Code review (small diff) | Sonnet | high | Auth/payment/security/migration |
| Complex coding | Opus | xhigh | **xhigh shallow → max** |
| Architecture, deep review | Opus | max | — |

### Never Pair

- `haiku × {xhigh, max}` — small models can't exploit deep thinking
- `opus × low` — inverted, downgrade model instead
- `[1m] × max` on routine tasks — thinking tokens get re-processed across the full context

## ▸ New User Onboarding

Includes `onboarding-checklist.md` — a ready-to-use checklist for new team members to configure Claude Code efficiently from day one.

## Contributing

Issues and PRs welcome. Found a new token pitfall? [Open an issue](https://github.com/Rubbish0-A/token-guard/issues) — we'll add it to the guide.

## License

[MIT](LICENSE)

---

<div align="center">

**1.56B tokens · $1,700 · 16 days**

*Every pitfall documented here was paid for in real money.*

**Star this repo so others don't have to pay the same tuition.**

</div>
