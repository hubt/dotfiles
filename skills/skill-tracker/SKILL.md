---
name: skill-tracker
description: Show skill usage stats and codify frequently-used LLM skills into scripts
---

# skill-tracker

## Instructions

1. Read `/home/hubt/.claude/skills/skill-tracker/counts.json` (may not exist yet — treat as empty).
2. List all directories under `/home/hubt/.claude/skills/`.
3. For each skill directory, check whether it contains any executable files (`.sh`, `.py`, `.go`, compiled binaries) beyond `SKILL.md` — if so, classify it as **Script-backed**, otherwise **LLM-prompt**.
4. Print a table:

   | Skill | Uses | Avg Time | Tokens (in/out/cache) | Raw Cost | Net Cost | Type | Status |
   |-------|------|----------|-----------------------|----------|----------|------|--------|
   | hello | 3 | 42s | 12k / 2k / 8k | $0.042 ($0.014/use) | $0.005 ($0.002/use) | LLM-prompt | Learning |

   - Avg Time: `total_ms / uses`, formatted as `Xs` (seconds) or `Xm Ys` for >60s
   - Tokens: sum of `input_tokens` / `output_tokens` / (`cache_creation_tokens` + `cache_read_tokens`) — show as `Xk` rounded
   - Raw Cost: `estimated_cost_usd` formatted as `$0.000 ($0.000/use)`
   - Net Cost: `estimated_cost_usd - overhead_cost_usd` formatted as `$0.000 ($0.000/use)` — this is the cost attributable to the skill's LLM work, minus the baseline per-turn invocation overhead (cache reads from system prompt)

   Status tiers (read thresholds from `/home/hubt/.claude/skills/skill-tracker/config.json` → `thresholds`; defaults: candidate=5, priority=10):
   - 0 to (candidate-1) uses → **Learning**
   - candidate to (priority-1) uses → **Candidate** (eligible for codification)
   - priority+ uses → **Priority** (should be codified)

   Also sort by `estimated_cost_usd` descending so the most expensive skills surface first.

5. If any skills are Candidate or Priority and are still LLM-prompt type, list them as "Codification candidates", sorted by cost/use descending (highest ROI first), and ask the user if they'd like to codify one.

## Codifying a skill

When the user picks a skill to codify:

1. Read its `SKILL.md` and understand exactly what it does end-to-end.
2. Identify the parts that are **deterministic** (file reads/writes, git commands, API calls with known shapes) vs. the parts that require **LLM reasoning** (drafting prose, inferring intent, open-ended decisions).
3. Write a Go program (preferred) or bash script in the skill's directory that handles the deterministic parts. If LLM reasoning is unavoidable, have the script emit a structured prompt and pipe it to `claude -p` as a subprocess.
4. Compile any Go code: `go build -o <name> ./<name>.go`
5. Update the skill's `SKILL.md` instructions to simply invoke the compiled binary or script, passing `$args` through.
6. Tell the user what was automated vs. what still uses LLM reasoning, and why.
