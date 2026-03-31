---
name: pre-push
description: Pre-push review: compile, lint, security, test gaps, docs, and commit history before pushing a branch
---

# pre-push

Run this skill before pushing a branch to share it with others. The goal is not to block work — it's to catch things worth fixing before they become someone else's problem to review or revert.

## Instructions

### Step 1 — Gather branch data

Run the gather script from the repo root:

```
bash /home/hubt/.claude/skills/pre-push/gather.sh
```

This script handles all deterministic work in one pass:
- Establishes branch scope (merge base, commits, full diff, file stats)
- Detects project types from root config files
- Runs compile checks (go build/vet, cargo check, tsc --noEmit)
- Runs lint checks (golangci-lint, eslint, biome, ruff, mypy, shellcheck)
- Collects per-commit stats for history review
- Reports upstream drift and overlapping files

If the script prints "Nothing to push — branch is up to date with upstream." — stop here.

Use the script's output as context for all steps below. Do **not** re-run git commands the script already ran.

### Step 2 — Security review

Analyze the full diff section of the script output for security issues. Severity: **Critical**, **High**, **Medium**, **Low**.

#### 2a. Injection vulnerabilities
- SQL/NoSQL injection: raw string concatenation into queries without parameterization
- Command injection: user input passed to `exec`, `shell`, `subprocess`, `os.system`, template strings in shell calls
- XSS: unescaped user content rendered into HTML/JS
- Path traversal: user-controlled paths used in file operations without sanitization
- SSRF: user-supplied URLs fetched without allowlist validation

#### 2b. Authentication & authorization
- Missing auth checks on new endpoints or functions that handle sensitive operations
- Hardcoded credentials, API keys, tokens, or passwords (even in test code)
- Secrets in config files, `.env` files, or source — flag any string that looks like a key/token/password
- JWT/session handling issues (algorithm confusion, missing expiry, insecure storage)
- Privilege escalation: operations that bypass permission checks

#### 2c. Cryptography & data handling
- Weak or broken algorithms (MD5/SHA1 for security, DES, ECB mode)
- Hardcoded IVs, salts, or seeds
- Sensitive data (PII, credentials, financial data) logged, serialized unencrypted, or sent to third parties
- Insecure deserialization of untrusted input

#### 2d. Dependency risks
- New dependencies using `latest`/`*` version ranges, pinned to a raw commit hash, or with known CVE history
- `eval`, `exec`, or dynamic code execution introduced via new dependency usage

#### 2e. Infrastructure & configuration
- New env vars that accept secrets and may be logged at startup
- CORS, CSP, or security header regressions
- TLS/certificate verification disabled
- Debug flags or stack traces exposed to end users

For each finding: cite file and approximate line from the diff, describe the risk, suggest a fix. Mark **Critical** findings as push blockers.

### Step 3 — Test gaps

Look at the full diff for missing test coverage. Skip trivial getters, pure config changes, or code already covered by existing tests.

Flag if the branch introduces or modifies:
- **New business logic** — conditionals, calculations, state transitions with no test changes alongside them
- **Bug fixes** — no regression test to prevent recurrence
- **New public API surface** — exported functions, HTTP endpoints, gRPC handlers, CLI commands, event handlers
- **Error paths** — new error conditions or error-handling branches that are untested
- **Security-sensitive code** — auth checks, input validation, permission gates
- **Edge cases** — boundaries, empty/nil inputs, concurrent access

For each gap:
1. **What to test** — specific function/endpoint/behavior
2. **Test cases** — 2-5 scenarios (happy path + at least one failure/edge case)
3. **Test type** — unit, integration, or e2e
4. **Priority** — Required (security/critical path), Recommended (new logic), Optional (edge cases)

Cite any existing test file that covers the changed code. Do not write test code unless the user asks.

### Step 4 — Code quality analysis

Analyze new and modified code from the diff. Focus only on code introduced or changed by this branch.

#### 4a. Unused code
Flag variables, parameters, imports, constants, functions, types, or exported symbols that are declared but never referenced. For each: cite file and approximate line, state what is unused, and suggest removal.

#### 4b. Unreachable code
Flag code paths that can never execute (after unconditional return/throw, always-true/false conditions, shadowed switch cases). For each: cite file and line, explain why it's unreachable, suggest deletion.

#### 4c. Simplification opportunities
Flag patterns that are functionally correct but unnecessarily complex:
- `if x { return true } else { return false }` → `return x`
- Deep nesting that could be flattened with early returns
- Repeated identical expressions that should be extracted
- Unnecessary temporary variables assigned once and immediately returned
- Magic literals without named constants

For each: cite file and line, show current pattern → simpler form.

#### 4d. Naming and clarity
Flag: single-letter names outside idioms, boolean names that don't read as predicates, functions named after implementation not intent, inconsistent conventions in the same scope.

After analysis, offer: "Would you like me to apply the unused code removals and/or the simplifications above?"
If yes: make targeted edits (removals and inlinings only — no structural rewrites), then show a summary of what changed.

### Step 5 — Documentation review

Analyze the diff for documentation gaps:

- **Architectural changes**: new packages/services, public API changes, schema changes, routing changes, new config keys
- **New dependencies**: name, version, inferred purpose — flag heavy or unusual choices
- **Non-obvious code**: algorithms, concurrency patterns, error-handling surprises, workarounds — suggest brief inline comments explaining the *why*

### Step 6 — Commit history review

Use the "Commit details" section from the script output.

If there is only one commit and its message is clear, note "History looks clean." and skip to Step 7.

#### 6a. Squash candidates
Flag commits that signal noise: `fix typo`, `fix build`, `oops`, `wip`, `temp`, `address review`, `update function` (no why).

#### 6b. Reorganization opportunities
Map which files each commit touches. Flag:
- **Mixed concerns** — one commit touches unrelated files. Suggest split.
- **Scattered feature** — related changes spread across non-adjacent commits with noise in between. Suggest reorder + squash.
- **Fixup orphans** — a `fix X` commit far from what it patches.

#### 6c. Propose the ideal sequence

Show a before/after:

```
Before:
  abc1234 add user model
  def5678 wip
  ghi9012 fix typo in model

After:
  [1] "Add User model with validation"  (abc1234 + ghi9012 + def5678)
```

Proposed messages: imperative mood, ≤72 chars, describe *why* or *what it enables*.

#### 6d. Execute (with confirmation)

Ask: "Would you like me to apply this reorganization before you push?"

If yes and all commits collapse to one:
1. `git reset --soft <merge-base>` — collapses everything into the index.
2. Leave staged; the user creates the final commit with the proposed message.

If yes and multiple commits remain:
1. Generate exact `git rebase -i` instruction lines (pick/squash/fixup/reword/reorder).
2. Show the instruction list to the user first.
3. Write to a temp file and run: `GIT_SEQUENCE_EDITOR="cp <tempfile>" git rebase -i <merge-base>`
4. On conflict: stop, show conflict files, ask user to resolve then continue.
5. On success: show `git log --oneline` for verification.

If the branch has already been pushed, warn: "This branch has commits on the remote. Rewriting history will require a force-push. Is that safe for this branch?" Only proceed if explicitly confirmed.

### Step 7 — Rebase check

Use the upstream drift section from the script output.

#### 7a. Assess
Rebase candidate if:
- Base branch has 1–5 new commits — routine drift, low-risk
- Base branch has 6–20 new commits — meaningful drift; check overlapping files
- Base branch has 20+ new commits — flag prominently
- Any base branch commits touch the **same files** as this branch — conflict risk, rebase strongly recommended
- Base branch contains commits this branch's changes depend on — rebase required

Not recommended if: branch already pushed and others may have based work on it.

#### 7b. Conflict preview

If overlapping files exist (shown in script output), run:
`git diff <merge-base>..<upstream-tip> -- <overlapping-files>` to show what changed upstream in those files.

Summarize the overlap: which functions/sections changed upstream vs. what this branch changes.

#### 7c. Offer to rebase

Ask: "The base branch is N commits ahead. Would you like me to rebase this branch onto the latest `<base>`?"

If yes:
1. `git fetch origin`
2. `git rebase origin/<base>` (or `@{u}` if tracking is set)
3. Clean rebase: show `git log --oneline -5` and confirm success.
4. Conflicts: stop immediately, list conflicting files, instruct user to resolve (`git add <file>`, then `git rebase --continue`). Do not auto-resolve.
5. After successful rebase: note that `--force-with-lease` will be needed when pushing.

If no: note "Rebase skipped — branch is N commits behind `<base>`."

### Step 8 — Report

```
## Pre-push Review: <branch-name>

### Compile  ✓ / ✗
<results from gather script, or "not applicable">

### Lint  ✓ / ✗ / ⚠
<results from gather script>

### Security  ✓ / ⚠ / ✗
**Critical / High** (address before pushing):
- <file> — <issue> — <suggested fix>

**Medium / Low** (consider fixing):
- <file> — <issue>

### Test Gaps
- [ ] [Required]     <what> — <why> (unit/integration/e2e)
- [ ] [Recommended]  <what> — <why>
- [ ] [Optional]     <what> — <why>

### Code Quality  ✓ / ⚠
**Unused code:** ...
**Unreachable code:** ...
**Simplifications:** ...
**Naming:** ...
(or "No issues found.")

### Documentation Notes
**Architectural changes:** <item or "none">
**New dependencies:** <package vX.Y — purpose or "none">
**Non-obvious code:** <file:line — suggested comment or "none">

### Rebase  ✓ / ⚠ / —
<base> is N commits ahead.
Overlapping files: <list or "none">
Conflict risk: low / medium / high
(or "Up to date — no rebase needed.")

### Commit History  ✓ / ⚠
<"History looks clean." or issue list>

Before: <sha> "<msg>", ...
After:
  [1] "<proposed message>"  (<sha> + <sha>)
```

After the report, ask one combined question covering whichever apply:
- Rebase onto the latest `<base>`?
- Apply unused/unreachable code removals and simplifications?
- Add suggested inline comments/docs?
- Write the Required/Recommended tests?
- Reorganize commits into the proposed sequence?

Handle each response independently.

### Step 9 — Readiness summary

Finish with a plain-English summary:

- **Push blockers** (must fix): compile failures, Critical security issues, lint errors.
- **Worth fixing before review**: High security findings, Required tests, significant doc gaps, messy history.
- **Low priority**: Medium/Low security notes, Optional tests, minor style suggestions.
- If nothing is blocking: say "Branch looks good to push."

The user decides what to act on. This review is a prompt for care, not a gate.
