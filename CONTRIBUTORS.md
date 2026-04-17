# Contributors

Thanks to everyone who has helped shape Token Guard.

## Maintainers

- [Rubbish0-A](https://github.com/Rubbish0-A) — Author, original plugin design and pitfall documentation.
- [Cliff-AI-Lab](https://github.com/Cliff-AI-Lab) — Co-maintainer, company account for coordinated releases and long-term stewardship.

## How to Contribute

Found a new token-efficiency pitfall, a stale pattern, or a missing check? PRs and issues welcome.

- **New stale patterns** → edit `skills/token-guard/references/stale-patterns.json`. No bash knowledge required — just add an entry matching the existing schema.
- **New audit checks** → add a `check_*` function to `scripts/audit.sh` following the existing structure, then register it in the main dispatch array.
- **New pitfall chapters** → append to `skills/token-guard/references/pitfall-guide.md` using the "what happened → why → cost impact → correct approach" format.
- **Bug reports & feature requests** → https://github.com/Rubbish0-A/token-guard/issues

Every pitfall documented here was paid for in real tokens. Your contribution saves someone else the tuition.
