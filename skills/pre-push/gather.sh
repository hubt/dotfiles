#!/usr/bin/env bash
# gather.sh — collects all deterministic pre-push data and prints structured context
# for LLM analysis. Run from the repo root.
set -euo pipefail

hr() { printf '\n---\n\n'; }

# ── Step 1: Branch scope ──────────────────────────────────────────────────────

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "## Branch: $BRANCH"
hr

MERGE_BASE=""
for ref in "@{u}" "origin/HEAD" "origin/main" "origin/master"; do
  if mb=$(git merge-base HEAD "$ref" 2>/dev/null); then
    MERGE_BASE="$mb"
    BASE_REF="$ref"
    break
  fi
done

if [ -z "$MERGE_BASE" ]; then
  echo "**WARNING:** Could not determine merge base. Showing last 20 commits as fallback."
  git log --oneline -20
  hr
  echo "**DIFF (last 20 commits fallback):**"
  git diff HEAD~20..HEAD
  exit 0
fi

COMMITS=$(git log --oneline "${MERGE_BASE}..HEAD")
if [ -z "$COMMITS" ]; then
  echo "Nothing to push — branch is up to date with upstream."
  exit 0
fi

echo "### Commits on this branch (vs $BASE_REF):"
echo "$COMMITS"
hr

echo "### File change summary:"
git diff --stat "${MERGE_BASE}..HEAD"
hr

echo "### Full diff:"
git diff "${MERGE_BASE}..HEAD"
hr

# ── Upstream drift ────────────────────────────────────────────────────────────

echo "## Upstream drift"
UPSTREAM_AHEAD=$(git rev-list --count "HEAD..@{u}" 2>/dev/null \
  || git rev-list --count "HEAD..origin/main" 2>/dev/null \
  || echo "0")
echo "Base branch commits ahead of this branch: $UPSTREAM_AHEAD"

if [ "$UPSTREAM_AHEAD" -gt 0 ] 2>/dev/null; then
  echo ""
  echo "Commits this branch is missing:"
  git log --oneline "HEAD..@{u}" 2>/dev/null \
    || git log --oneline "HEAD..origin/main" 2>/dev/null \
    || echo "(could not list)"

  echo ""
  echo "Files changed upstream (not in this branch):"
  git diff --name-only "${MERGE_BASE}..@{u}" 2>/dev/null \
    || git diff --name-only "${MERGE_BASE}..origin/main" 2>/dev/null \
    || echo "(could not list)"

  echo ""
  echo "Files changed on THIS branch:"
  git diff --name-only "${MERGE_BASE}..HEAD"

  echo ""
  echo "Overlapping files (changed both upstream and on this branch):"
  UPSTREAM_FILES=$(git diff --name-only "${MERGE_BASE}..@{u}" 2>/dev/null \
    || git diff --name-only "${MERGE_BASE}..origin/main" 2>/dev/null \
    || echo "")
  BRANCH_FILES=$(git diff --name-only "${MERGE_BASE}..HEAD")
  comm -12 <(echo "$UPSTREAM_FILES" | sort) <(echo "$BRANCH_FILES" | sort) || echo "(none)"
fi
hr

# ── Step 2: Project type detection ───────────────────────────────────────────

echo "## Project types detected"

CHANGED_FILES=$(git diff --name-only "${MERGE_BASE}..HEAD")

[ -f go.mod ]            && echo "- Go (go.mod found)"
[ -f package.json ]      && echo "- TypeScript/JS (package.json found)"
[ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ] \
                         && echo "- Python (pyproject.toml/setup.py/requirements.txt found)" || true
[ -f Cargo.toml ]        && echo "- Rust (Cargo.toml found)"
[ -f pom.xml ]           && echo "- Java/Maven (pom.xml found)"
[ -f build.gradle ]      && echo "- Java/Kotlin/Gradle (build.gradle found)"
[ -f CMakeLists.txt ]    && echo "- C/C++ (CMakeLists.txt found)"
echo "$CHANGED_FILES" | grep -q '\.sh$' && echo "- Shell scripts (.sh files changed)" || true
hr

# ── Step 3: Compile check ─────────────────────────────────────────────────────

echo "## Compile results"

if [ -f go.mod ]; then
  echo "### Go: go build ./..."
  if go build ./... 2>&1; then
    echo "✓ Build passed"
  else
    echo "✗ Build FAILED (push blocker)"
  fi
  echo ""
  echo "### Go: go vet ./..."
  if go vet ./... 2>&1; then
    echo "✓ vet passed"
  else
    echo "✗ vet FAILED"
  fi
fi

if [ -f Cargo.toml ]; then
  echo "### Rust: cargo check"
  if cargo check 2>&1; then echo "✓"; else echo "✗ (push blocker)"; fi
fi

if [ -f package.json ]; then
  echo "### TypeScript: tsc --noEmit"
  if command -v npx &>/dev/null && npx tsc --version &>/dev/null; then
    if npx tsc --noEmit 2>&1; then echo "✓"; else echo "✗ (push blocker)"; fi
  else
    echo "(tsc not available)"
  fi
fi
hr

# ── Step 4: Lint check ────────────────────────────────────────────────────────

echo "## Lint results"

if [ -f go.mod ]; then
  if command -v golangci-lint &>/dev/null; then
    echo "### golangci-lint"
    golangci-lint run 2>&1 || echo "✗ lint issues found"
  else
    echo "### golangci-lint: not installed"
  fi
fi

if [ -f package.json ]; then
  if command -v npx &>/dev/null; then
    if [ -f .eslintrc* ] || [ -f eslint.config* ] || grep -q '"eslint"' package.json 2>/dev/null; then
      echo "### ESLint"
      npx eslint . 2>&1 || echo "✗ lint issues found"
    fi
    if grep -q '"biome"' package.json 2>/dev/null || [ -f biome.json ]; then
      echo "### Biome"
      npx biome check . 2>&1 || echo "✗ lint issues found"
    fi
  fi
fi

if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; then
  if command -v ruff &>/dev/null; then
    echo "### ruff"
    ruff check . 2>&1 || echo "✗ lint issues found"
  fi
  if command -v mypy &>/dev/null; then
    echo "### mypy"
    mypy . 2>&1 || echo "✗ type errors found"
  fi
fi

if echo "$CHANGED_FILES" | grep -q '\.sh$'; then
  if command -v shellcheck &>/dev/null; then
    echo "### shellcheck"
    echo "$CHANGED_FILES" | grep '\.sh$' | xargs shellcheck 2>&1 || echo "✗ shellcheck issues found"
  else
    echo "### shellcheck: not installed"
  fi
fi
hr

# ── Commit detail (for history review) ───────────────────────────────────────

echo "## Commit details (for history review)"
while read -r sha msg; do
  echo "### $sha $msg"
  git show --stat "$sha"
  echo ""
done < <(git log --format="%h %s" "${MERGE_BASE}..HEAD")
hr

echo "## END OF CONTEXT"
