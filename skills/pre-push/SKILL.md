---
name: pre-push
description: Pre-push review: compile, lint, security, test gaps, docs, and commit history before pushing a branch
---

# pre-push

Run this skill before pushing a branch to share it with others. The goal is not to block work — it's to catch things worth fixing before they become someone else's problem to review or revert.

## Instructions

### Step 1 — Establish the branch scope

Determine what's on this branch that hasn't been pushed yet. Run in parallel:
- `git rev-parse --abbrev-ref HEAD` — current branch name
- `git log --oneline $(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null)..HEAD` — all commits on this branch not yet merged upstream
- `git diff $(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null)..HEAD` — full diff of all changes on the branch
- `git diff --stat $(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null)..HEAD` — file change summary

Also run in parallel to assess upstream drift:
- `git fetch --dry-run 2>&1 || true` — check if a fetch would pull new commits (non-destructive)
- `git rev-list --count HEAD..@{u} 2>/dev/null || git rev-list --count HEAD..origin/main 2>/dev/null || echo 0` — how many commits the base branch is ahead of this branch
- `git log --oneline @{u}..HEAD 2>/dev/null || git log --oneline origin/main..HEAD 2>/dev/null` — commits on the base branch not yet in this branch
- `git log --oneline HEAD..@{u} 2>/dev/null || git log --oneline HEAD..origin/main 2>/dev/null` — commits this branch is missing from the base

Store the merge-base SHA and upstream-ahead count for use in later steps. If none of the merge-base commands succeed, fall back to `git log --oneline -20` and note that the base could not be determined.

If the branch has no commits beyond the base, say "Nothing to push — branch is up to date with upstream." and stop.

### Step 2 — Detect project type(s)

From the changed file extensions and root config files, identify the active tech stacks:
- Go: `go.mod` exists → `go build ./...` and `go vet ./...`
- TypeScript/JS: `package.json` exists → look for `tsc`, `eslint`, `biome`, `prettier`
- Python: `pyproject.toml`, `setup.py`, or `requirements.txt` → look for `ruff`, `mypy`, `flake8`, `pylint`
- Rust: `Cargo.toml` → `cargo check` and `cargo clippy`
- Java/Kotlin: `pom.xml` or `build.gradle` → `mvn compile` or `gradle compileJava`
- C/C++: `CMakeLists.txt` or `Makefile` → `make -n` or `cmake --build`
- Shell: any `.sh` files → `shellcheck` if available

Only check stacks relevant to the changed files — skip stacks with no changes on this branch.

### Step 3 — Compile check

For each detected stack:

1. Run the compile/build command (non-destructive, no side effects). Use `--dry-run` / check-only flags where available.
2. If it fails: show the errors and flag as a **push blocker** — the branch will likely break CI.
3. If it passes: note ✓.

Do not run tests here.

### Step 4 — Lint check

For each detected stack:

1. Run the project's configured linter against the changed files (pass the file list where the linter supports it).
2. Prefer project-local configs (`.eslintrc`, `ruff.toml`, `.golangci.yml`, etc.) over defaults.
3. **Errors** (exit non-zero): flag as a push blocker, offer to auto-fix if the linter supports `--fix`.
4. **Warnings only**: list them and note they are non-blocking.

### Step 5 — Security review

Analyze the full branch diff for security issues. Severity: **Critical**, **High**, **Medium**, **Low**.

#### 5a. Injection vulnerabilities
- SQL/NoSQL injection: raw string concatenation into queries without parameterization
- Command injection: user input passed to `exec`, `shell`, `subprocess`, `os.system`, template strings in shell calls
- XSS: unescaped user content rendered into HTML/JS
- Path traversal: user-controlled paths used in file operations without sanitization
- SSRF: user-supplied URLs fetched without allowlist validation

#### 5b. Authentication & authorization
- Missing auth checks on new endpoints or functions that handle sensitive operations
- Hardcoded credentials, API keys, tokens, or passwords (even in test code)
- Secrets in config files, `.env` files, or source — flag any string that looks like a key/token/password
- JWT/session handling issues (algorithm confusion, missing expiry, insecure storage)
- Privilege escalation: operations that bypass permission checks

#### 5c. Cryptography & data handling
- Weak or broken algorithms (MD5/SHA1 for security, DES, ECB mode)
- Hardcoded IVs, salts, or seeds
- Sensitive data (PII, credentials, financial data) logged, serialized unencrypted, or sent to third parties
- Insecure deserialization of untrusted input

#### 5d. Dependency risks
- New dependencies using `latest`/`*` version ranges, pinned to a raw commit hash (supply chain risk), or with known CVE history
- `eval`, `exec`, or dynamic code execution introduced via new dependency usage

#### 5e. Infrastructure & configuration
- New env vars that accept secrets and may be logged at startup
- CORS, CSP, or security header regressions
- TLS/certificate verification disabled
- Debug flags or stack traces exposed to end users

For each finding: cite the file and approximate line from the diff, describe the risk, and suggest a fix. Mark **Critical** findings as push blockers.

### Step 6 — Test gaps

Look at the full branch diff for missing test coverage. Skip trivial getters, pure config changes, or code already covered by existing tests.

Flag if the branch introduces or modifies:
- **New business logic** — conditionals, calculations, state transitions with no test changes alongside them
- **Bug fixes** — no regression test to prevent recurrence
- **New public API surface** — exported functions, HTTP endpoints, gRPC handlers, CLI commands, event handlers
- **Error paths** — new error conditions or error-handling branches that are untested
- **Security-sensitive code** — auth checks, input validation, permission gates (see Step 5)
- **Edge cases** — boundaries, empty/nil inputs, concurrent access

For each gap:
1. **What to test** — specific function/endpoint/behavior
2. **Test cases** — 2-5 scenarios (happy path + at least one failure/edge case)
3. **Test type** — unit, integration, or e2e
4. **Priority** — Required (security/critical path), Recommended (new logic), Optional (edge cases)

Cite any existing test file that covers the changed code. Do not write test code unless the user asks.

### Step 7 — Code quality analysis

Analyze the new and modified code on the branch diff for quality issues. Focus only on code introduced or changed by this branch — do not flag pre-existing issues unless the branch touches those lines.

#### 7a. Unused code
Flag variables, parameters, imports, constants, functions, types, or exported symbols that are:
- Declared but never referenced within the diff's scope
- Reachable only by dead branches (e.g., after an unconditional `return`, inside `if false`, unreachable `case` in a switch)
- Imports that are no longer used after the branch's changes
- Parameters that are accepted but ignored throughout the function body (use `_` or remove)
- Exported symbols with no callers anywhere in the repo (check with grep across the codebase — if nothing references it, flag it)

For each: cite file and approximate line, state what is unused, and suggest removal or renaming to `_`.

#### 7b. Unreachable code
Flag code paths that can never execute:
- Statements after `return`, `panic`, `os.Exit`, `throw`, `raise`, or equivalent final statements
- Conditions that are always true or always false given the surrounding logic (e.g., checking a value that was just assigned a literal)
- `else` branches that can never be reached due to prior `return`/`throw` in the `if`
- Switch/match cases shadowed by a prior case or default
- Loop bodies that `break` or `return` unconditionally on the first iteration

For each: cite file and line, explain why it's unreachable, and suggest deletion.

#### 7c. Simplification opportunities
Flag patterns that are functionally correct but unnecessarily complex or harder to read than they need to be. Only flag where the simplification is clear and unambiguous — do not suggest stylistic rewrites or premature abstractions.

- **Redundant conditionals** — `if x { return true } else { return false }` → `return x`
- **Unnecessary negation** — `if !ok { ... } else { ... }` where swapping branches removes the negation
- **Double negatives** — `!(!x)`, `!(x == y)` where `x != y` is clearer
- **Nested ifs that can flatten** — deeply nested conditions that could be rewritten as early returns (guard clauses)
- **Repeated identical expressions** — the same sub-expression computed multiple times; extract to a variable
- **Unnecessary temporary variables** — assigned once and immediately returned; inline them
- **Long function doing multiple distinct things** — note it (don't auto-split), suggest the logical break points
- **Magic literals** — inline numbers or strings with non-obvious meaning that should be named constants
- **Over-engineered for current use** — abstraction layers, interfaces, or generics with only one concrete implementation and no near-term need for more

For each: cite file and line, show the current pattern, and show the simpler equivalent in one or two lines. Do not rewrite the code unless the user asks.

#### 7d. Naming and clarity
Flag names that make code harder to follow:
- Variables or functions with single-letter names outside of well-understood idioms (`i`/`j` loop indices, `err`, `ctx`, `ok` are fine)
- Boolean names that don't read as a predicate (`flag`, `check`, `data` → `isReady`, `hasError`, `userData`)
- Functions named after implementation rather than intent (`processData`, `doThing`, `handleStuff`)
- Inconsistent naming conventions within the same scope (camelCase mixed with snake_case, etc.)

For each: cite file and line, state the current name, and suggest an alternative.

After analysis, offer: "Would you like me to apply the unused code removals and/or the simplifications above?"
If yes: make the targeted edits (removals and inlinings only — no structural rewrites), then show a summary of what changed.

### Step 8 — Documentation review

Analyze the full branch diff for documentation gaps:

#### 7a. Architectural changes
Flag if the branch introduces or removes:
- New packages/modules/services
- Public API changes (exported functions, REST endpoints, gRPC definitions, event schemas)
- Data model or schema changes
- Dependency injection wiring, middleware registration, routing changes
- New configuration keys or environment variables

For each: one sentence on what changed and why it matters architecturally.

#### 7b. New dependencies
Detect additions to `go.mod`, `package.json`, `requirements.txt`, `Cargo.toml`, `pom.xml`, `build.gradle`, etc.

For each: name, version, inferred purpose. Flag heavy or unusual choices.

#### 7c. Non-obvious code
Identify code a future reviewer would likely misunderstand:
- Non-obvious algorithms or data structures
- Magic numbers/strings without named constants
- Concurrency patterns (locks, channels, goroutines, async/await chains)
- Error handling that silences or transforms errors unexpectedly
- Workarounds, known-fragile code, or deliberate shortcuts
- Performance-sensitive hot paths

For each: suggest a brief inline comment explaining the *why*, not the *what*.

### Step 9 — Commit history review

Use the commits and file stats from Step 1. If there is only one commit and its message is clear, note "History looks clean." and skip to the report.

#### 8a. Squash candidates

Flag commits whose messages signal noise rather than intent:
- **Redundant** — amends a prior commit: `fix typo`, `fix build`, `address review`, `oops`, `forgot to`, `tweak`
- **Irrelevant** — pure noise: `wip`, `temp`, `checkpoint`, `save`, `debugging`, `remove console.log`
- **Obvious** — states only what git records: `add file`, `update function`, `change X` (no *why*)
- **Incremental fixups** — multiple commits forming one logical unit

#### 8b. Reorganization opportunities

Map which files each commit touches (from `git show --stat` per commit in the branch range), then flag:

- **Mixed concerns** — one commit touches unrelated files (bug fix bundled with unrelated refactor). Suggest split.
- **Scattered feature** — related changes spread across non-adjacent commits with noise in between. Suggest reorder + squash.
- **Inverted order** — a test commit before its implementation, or a fix before the thing it fixes. Suggest reorder.
- **Refactor entangled with feature** — suggest splitting into pure refactor, then feature on top.
- **Fixup orphans** — a `fix X` commit far from what it patches. Suggest moving adjacent then squashing.

#### 8c. Propose the ideal sequence

Show a before/after of the proposed clean history:

```
Before:
  abc1234 add user model
  def5678 wip
  ghi9012 add auth endpoint
  jkl3456 fix typo in model
  mno7890 add tests
  pqr2345 address review comments

After:
  [1] "Add User model with validation"  (abc1234 + jkl3456)
  [2] "Add auth endpoint with tests"    (ghi9012 + mno7890 + def5678 + pqr2345)
```

Proposed messages: imperative mood, ≤72 chars, describe *why* or *what it enables* — not implementation details. Infer style from `git log` on the base branch.

#### 8d. Execute (with confirmation)

Ask: "Would you like me to apply this reorganization before you push?"

If yes:

**All commits collapse to one:**
1. `git reset --soft <merge-base>` — collapses everything into the index.
2. Leave staged; the user creates the final commit with the proposed message.

**Multiple commits remain:**
1. Generate the exact `git rebase -i` instruction lines (pick/squash/fixup/reword/reorder).
2. Show the instruction list to the user first.
3. Write to a temp file and run: `GIT_SEQUENCE_EDITOR="cp <tempfile>" git rebase -i <merge-base>`
4. On conflict: stop, show conflict files, ask user to resolve then continue.
5. On success: show `git log --oneline` for verification.

If the branch has already been pushed to a remote, warn first:
> "This branch has commits on the remote. Rewriting history will require a force-push. Is that safe for this branch?"
Only proceed if the user explicitly confirms.

### Step 10 — Rebase check

Use the upstream-ahead count and missing-commits list gathered in Step 1.

#### 9a. Assess the situation

The base branch is a **rebase candidate** if any of the following are true:
- The base branch has **1–5 new commits** not in this branch — routine drift, rebase is clean and low-risk
- The base branch has **6–20 new commits** — meaningful drift; check if any touch the same files as this branch
- The base branch has **20+ new commits** — significant drift; flag this prominently
- Any of the base branch's new commits touch the **same files** this branch modifies — conflict risk, rebase strongly recommended before pushing
- The base branch contains commits that **this branch's changes depend on** (e.g., a shared interface or type was updated upstream) — rebase required for correctness

Also flag if a rebase is **not recommended**:
- This branch has already been pushed and others may have based work on it — rebasing would rewrite shared history
- The branch is a long-running release or integration branch where merge commits are preferred for traceability

#### 9b. Conflict preview

If the base has new commits that touch overlapping files, run:
`git diff <merge-base>..<upstream-tip> -- <overlapping-files>` to show what changed upstream in those files.

Summarize the overlap: which functions/sections changed upstream vs. what this branch changes in the same files. This helps the user anticipate whether the rebase will be clean or contentious.

#### 9c. Offer to rebase

Present the finding, then ask:
> "The base branch is N commits ahead. Would you like me to rebase this branch onto the latest `<base>`?"

If the user says yes:
1. Run `git fetch origin` to ensure the local remote ref is current.
2. Run `git rebase origin/<base>` (or `@{u}` if tracking is set).
3. If the rebase completes cleanly: show `git log --oneline -5` and confirm success.
4. If conflicts arise: stop immediately, list the conflicting files, and instruct the user to resolve them (`git add <file>`, then `git rebase --continue`). Do not attempt to auto-resolve conflicts.
5. After a successful rebase, note that the branch will need `--force-with-lease` when pushing (safer than `--force`).

If the user says no: note it in the report as "Rebase skipped — branch is N commits behind `<base>`."

### Step 11 — Report

```
## Pre-push Review: <branch-name>

### Compile  ✓ / ✗
<results or "not applicable">

### Lint  ✓ / ✗ / ⚠
<results>

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
**Unused code:**
- <file:line> — <what> — remove / rename to `_`

**Unreachable code:**
- <file:line> — <why unreachable> — delete

**Simplifications:**
- <file:line> — <current pattern> → <simpler form>

**Naming:**
- <file:line> — `<current>` → `<suggested>`
(or "No issues found.")

### Documentation Notes
**Architectural changes:** <item or "none">
**New dependencies:** <package vX.Y — purpose or "none">
**Non-obvious code:** <file:line — suggested comment or "none">

### Rebase  ✓ / ⚠ / —
<base> is N commits ahead.
Overlapping files: <list or "none">
Conflict risk: low / medium / high
(or "Up to date — no rebase needed." / "Rebase not recommended — branch already shared.")

### Commit History  ✓ / ⚠
<"History looks clean." or issue list>

Before: <sha> "<msg>", ...
After:
  [1] "<proposed message>"  (<sha> + <sha>)
  [2] "<proposed message>"  (<sha>)
```

After the report, ask one combined question covering whichever of the following apply:
- Rebase onto the latest `<base>`?
- Apply unused/unreachable code removals and simplifications?
- Add suggested inline comments/docs?
- Write the Required/Recommended tests?
- Reorganize commits into the proposed sequence?

Handle each response independently.

### Step 12 — Readiness summary

Finish with a plain-English summary:

- **Push blockers** (must fix): list any compile failures, Critical security issues, or lint errors.
- **Worth fixing before review**: High security findings, Required tests, significant doc gaps, messy history.
- **Low priority**: Medium/Low security notes, Optional tests, minor style suggestions.
- If nothing is blocking: say "Branch looks good to push."

The user decides what to act on. This review is a prompt for care, not a gate.
