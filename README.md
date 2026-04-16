<p align="center">
  <a href="README.zh-CN.md">中文</a> | English
</p>

<p align="center">
  <h1 align="center">Token Guard</h1>
  <p align="center"><strong>以身试法的通用 Tokens 节省指南 — 把该踩的坑都踩过了</strong></p>
  <p align="center">
    <a href="#installation">Installation</a> ·
    <a href="#usage">Usage</a> ·
    <a href="#what-it-checks">What It Checks</a> ·
    <a href="#pitfall-guide">Pitfall Guide</a>
  </p>
</p>

---

> **Born from 1.56 billion tokens in 16 days.**
>
> 9,000 requests. $1,700+ burned. 133M input tokens. Heavy vibe-coding at max intensity with Opus — and then we asked: *where did all the tokens go?*
>
> This plugin is the answer. Every check, every pitfall, every optimization documented here was paid for in real tokens, discovered through systematic forensic analysis of a production Claude Code environment running at extreme scale.

---

A **Claude Code plugin** that audits your token consumption and identifies exactly where your money is going. Not theory — built from real forensic analysis of a heavy-usage environment that burned through 1.56B tokens in half a month.

## The Problem

Claude Code token costs can silently explode due to misconfigurations that are invisible during normal use:

- **18 plugins enabled** → 120+ skill descriptions injected into every API call (~15,000 tokens/turn wasted)
- **Triplicate plugins** → 3 plugins registering identical skills (pdf, docx, xlsx appear 3 times each)
- **Mandatory agent dispatch** → rules forcing 3-5 sub-agents per task, each reloading the full system prompt on Opus
- **API key cross-contamination** → Anthropic keys stored in `GEMINI_API_KEY`, sent to Google endpoints
- **Session bloat** → single sessions reaching 78MB with memory-search agents growing to 15MB each
- **No model tiering** → every sub-agent inheriting Opus pricing for tasks Haiku could handle

**One team went from ~$0.52/turn in system prompt overhead to ~$0.04/turn after applying Token Guard's recommendations — a 93% reduction.**

## Installation

```bash
claude plugin add Rubbish0-A/token-guard
```

Or clone manually:

```bash
git clone git@github.com:Rubbish0-A/token-guard.git ~/.claude/plugins/local/token-guard
```

## Usage

In any Claude Code session:

```
/token-guard
```

That's it. Token Guard scans your configuration and outputs a scored audit report:

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

## What It Checks

| # | Check | What It Detects |
|---|-------|-----------------|
| 1 | **Model Config** | Opus as default for daily work (5x cost vs Sonnet) |
| 2 | **Plugin Count & Duplicates** | Too many plugins, triplicate skill registrations |
| 3 | **Rules File Size** | Bloated rules inflating every API call's system prompt |
| 4 | **Env Var Safety** | API keys stored in wrong variables (cross-contamination) |
| 5 | **Thinking Budget** | Extended thinking budget set too high (default 31,999) |
| 6 | **Dangerous Mode** | `--dangerously-skip-permissions` enabling unrestricted execution |
| 7 | **Session Health** | Session bloat, aside_question agent inflation, stale data |

## Automated Diagnostic Script

Token Guard includes `scripts/audit.sh` — a cross-platform Bash script that runs all 7 checks and outputs structured JSON. Claude reads the JSON and generates the human-friendly report. If the script can't run, Claude falls back to manual checks.

```bash
bash scripts/audit.sh
```

```json
{
  "tool": "token-guard",
  "version": "1.0.0",
  "results": [
    {"check": "model", "status": "warn", "value": "opus[1m]", "message": "..."},
    {"check": "plugins", "status": "warn", "enabled": 16, "duplicates": 0},
    ...
  ]
}
```

## Pitfall Guide

The plugin includes an 8-chapter guide based on real incidents. Each chapter covers: what happened, why it happened, the cost impact, and the correct approach.

| Ch | Title | Key Lesson |
|----|-------|------------|
| 1 | **Plugin Management** | All skill descriptions load on every call — even unused ones |
| 2 | **Model Selection** | Opus for everything = rocket delivery for pizza |
| 3 | **Rules & System Prompt** | Every rule you write is tokens you pay for, every turn |
| 4 | **Thinking Budget** | Default 31,999 → most tasks use < 5,000 |
| 5 | **Security & Env Vars** | API keys in wrong variables get sent to wrong providers |
| 6 | **Maintenance** | Config only grows — nothing auto-cleans |
| 7 | **Session Management** | Git commit is your cross-session memory, not long conversations |
| 8 | **Sub-Agent Explosion** | "Auto-dispatch" in rules = 3-5 agents × full system prompt × Opus pricing |

## Cost Model Reference

No absolute prices — just ratios that stay valid as pricing changes:

| Model | Input Cost | Output Cost | Best For |
|-------|-----------|------------|----------|
| Opus | 5x | 5x | Architecture, deep reasoning |
| Sonnet | 1x (baseline) | 1x | Daily coding, debugging |
| Haiku | ~0.27x | ~0.27x | Sub-agents, retrieval, batch |

## Sub-Agent Model Selection Strategy

Token Guard recommends tiered model selection for sub-agents:

| Task | Model | Escalate to Opus When |
|------|-------|-----------------------|
| File search, git log | Haiku | Results seem unreliable or contradictory |
| CRUD, tests, simple refactoring | Sonnet | Changes span 3+ interdependent files |
| Code review (small diff) | Sonnet | Involves auth, payment, security, migration |
| Complex coding, architecture | Opus | (already Opus) |

## New User Onboarding

Includes `onboarding-checklist.md` — a ready-to-use checklist for new team members to configure Claude Code efficiently from day one.

## Contributing

Issues and PRs welcome. If you've found a new token consumption pitfall, open an issue — we'll add it to the guide.

## License

MIT

---

<p align="center">
  <em>1.56B tokens. $1,700. 16 days. Every pitfall documented here was paid for in real money.</em><br>
  <strong>Star this repo so others don't have to pay the same tuition.</strong>
</p>
