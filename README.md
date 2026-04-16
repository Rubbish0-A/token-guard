<div align="center">

<a href="README.zh-CN.md">中文</a> | English

<img src="assets/banner.png" alt="Token Guard Banner" width="100%">

# Token Guard

**The Claude Code Token Efficiency Guide — Learned the Hard Way**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://github.com/Rubbish0-A/token-guard)
[![Version](https://img.shields.io/badge/version-1.0.0-green)](https://github.com/Rubbish0-A/token-guard)

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
Time: 2026-04-16 14:30:00

──── Checks ────────────────────────────────────

✅ Model: sonnet (recommended for daily use)
❌ Plugins: 18 enabled, 1 duplicate group detected
    → document-skills / example-skills / claude-api register identical skills
⚠️ Rules: 19KB (recommend < 15KB)
    → Largest: skill-vetter.md(4699B), agents.md(1979B)
✅ Env Vars: No cross-contamination detected
✅ Thinking Budget: 20000 (reasonable)
⚠️ Dangerous Mode: skipDangerousModePermissionPrompt=true
⚠️ Sessions: 236MB total, 45 aside_question agents, largest 48MB

──── Impact ────────────────────────────────────

System prompt overhead: ~25,000 tokens/turn
  Skill descriptions: ~15,000 tokens (120 skills × ~125)
  Rules files: ~6,000 tokens

──── Fixable Items ─────────────────────────────

1. Disable duplicate plugins (save ~10,000 tokens/turn)
2. Reduce rules files or convert to on-demand skills
3. Clean old session data (/compact or start new sessions)

═══════════════════════════════════════════════
```

</details>

## ▸ What It Checks

| # | Check | What It Detects |
|:---:|-------|-----------------|
| 1 | **Model Config** | Opus as default for daily work (5x cost vs Sonnet) |
| 2 | **Plugin Duplicates** | Too many plugins, triplicate skill registrations |
| 3 | **Rules File Size** | Bloated rules inflating every API call's system prompt |
| 4 | **Env Var Safety** | API keys stored in wrong variables (cross-contamination) |
| 5 | **Thinking Budget** | Extended thinking budget set too high (default 31,999) |
| 6 | **Dangerous Mode** | `--dangerously-skip-permissions` enabling unrestricted execution |
| 7 | **Session Health** | Session bloat, aside_question agent inflation, stale data |

### Automated Diagnostic Script

Includes `scripts/audit.sh` — cross-platform Bash script outputting structured JSON for all 7 checks. Claude reads the JSON and generates the human-friendly report. Falls back to manual checks if the script can't run.

<details>
<summary>JSON output example</summary>

```json
{
  "tool": "token-guard",
  "version": "1.0.0",
  "results": [
    {"check": "model", "status": "warn", "value": "opus[1m]"},
    {"check": "plugins", "status": "warn", "enabled": 16, "duplicates": 0},
    {"check": "rules", "status": "warn", "totalKB": 19},
    {"check": "env_vars", "status": "fail", "issues": 2},
    {"check": "thinking", "status": "warn", "value": "31999"},
    {"check": "dangerous_mode", "status": "warn", "dangerousProcs": 3},
    {"check": "sessions", "status": "warn", "totalSizeMB": 236}
  ]
}
```

</details>

## ▸ Pitfall Guide

8 chapters based on real incidents. Each chapter: what happened → why → cost impact → correct approach.

| Ch | Title | Key Lesson |
|:---:|-------|------------|
| 1 | **Plugin Management** | All skill descriptions load on every call — even unused ones |
| 2 | **Model Selection** | Opus for everything = rocket delivery for pizza |
| 3 | **Rules & System Prompt** | Every rule you write is tokens you pay for, every turn |
| 4 | **Thinking Budget** | Default 31,999 → most tasks use < 5,000 |
| 5 | **Security & Env Vars** | Keys in wrong variables get sent to wrong providers |
| 6 | **Maintenance** | Config only grows — nothing auto-cleans |
| 7 | **Session Management** | Git commit is your cross-session memory, not long conversations |
| 8 | **Sub-Agent Explosion** | "Auto-dispatch" = 3-5 agents × full system prompt × Opus pricing |

## ▸ Cost Model

No absolute prices — ratios that stay valid as pricing changes:

| Model | Input | Output | Best For |
|-------|:-----:|:------:|----------|
| **Opus** | 5x | 5x | Architecture, deep reasoning |
| **Sonnet** | 1x | 1x | Daily coding, debugging |
| **Haiku** | ~0.27x | ~0.27x | Sub-agents, retrieval, batch |

## ▸ Sub-Agent Model Strategy

| Task | Model | Escalate to Opus When |
|------|:-----:|-----------------------|
| File search, git log | **Haiku** | Results seem unreliable or contradictory |
| CRUD, tests, simple refactoring | **Sonnet** | Changes span 3+ interdependent files |
| Code review (small diff) | **Sonnet** | Involves auth, payment, security, migration |
| Complex coding, architecture | **Opus** | — |

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
