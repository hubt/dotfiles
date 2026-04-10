#!/usr/bin/env bash
# Renders an ANSI stacked bar chart of Vertex AI daily spend by model.
#
# This script is intentionally separate from gather.sh so that ANSI color codes
# reach the terminal directly (via a Bash tool call) rather than being swallowed
# by Claude's text pipeline.
#
# Usage:
#   bash render-vertex-chart.sh
#
# Prerequisites:
#   Run gather.sh first — it populates ~/.cache/cloud-spend/gcp_vertex_daily_*.json.
#   The most recent cache file is used automatically.
#
# Output:
#   - Colored vertical stacked bar chart (one column per day, stacked by model)
#   - Legend with color swatches
#   - Summary table: 30-day gross and daily average per model
set -euo pipefail

# ── Locate most-recent cached Vertex AI daily data ────────────────────────────
CACHE_DIR="${HOME}/.cache/cloud-spend"
CACHE_FILE=$(find "${CACHE_DIR}" -name 'gcp_vertex_daily_*.json' 2>/dev/null | sort | tail -1)

if [[ -z "$CACHE_FILE" ]]; then
  echo "No cached Vertex AI data found. Run /cloud-spend first to populate the cache."
  exit 1
fi

# ── Terminal width + temp script ──────────────────────────────────────────────
TERM_WIDTH=${TERM_WIDTH:-$(tput cols 2>/dev/null || echo 120)}
_PY=$(mktemp /tmp/render_vertex_chart_XXXXX.py)
trap 'rm -f "$_PY"' EXIT

cat > "$_PY" << 'PYEOF'
import sys, json, datetime, os, shutil

# ── Parse JSON array from BigQuery (bq --format=json) ─────────────────────────
days = {}
all_models = set()
try:
    rows = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    rows = []
for row in rows:
    date  = str(row.get('usage_date', ''))
    model = str(row.get('model', ''))
    gross = float(row.get('gross', 0))
    if not date or not model or gross <= 0:
        continue
    all_models.add(model)
    if date not in days:
        days[date] = {}
    days[date][model] = days[date].get(model, 0) + gross

if not days or not all_models:
    print('  No Vertex AI charges found.')
    sys.exit(0)

# ── Terminal dimensions ────────────────────────────────────────────────────────
term_cols = int(os.environ.get('TERM_WIDTH', 0)) or shutil.get_terminal_size((120, 40)).columns

# ── Data ──────────────────────────────────────────────────────────────────────
models       = sorted(all_models, key=lambda m: sum(days[d].get(m, 0) for d in days), reverse=True)
sorted_dates = sorted(days.keys())
n_days       = len(sorted_dates)

# Derive total window size from env vars (set by the shell from the filename)
window_start_str = os.environ.get('WINDOW_START', '')
window_end_str   = os.environ.get('WINDOW_END', '')
if window_start_str and window_end_str:
    from datetime import date as _date
    window_days = (_date.fromisoformat(window_end_str) - _date.fromisoformat(window_start_str)).days
else:
    window_days = n_days

def short(m):
    # Keep " Text" to disambiguate e.g. "Gemini 2.5 Pro" vs "Gemini 2.5 Pro Text"
    return (m.replace('Gemini ', '')
             .replace(' Thinking Text', ' Think')
             .replace(' Image', ' Img'))

# ── Colors ────────────────────────────────────────────────────────────────────
PALETTE = ['\033[38;5;39m', '\033[38;5;208m', '\033[38;5;46m',
           '\033[38;5;213m', '\033[38;5;226m', '\033[38;5;51m']
RESET = '\033[0m'
BOLD  = '\033[1m'

def C(i):           return PALETTE[i % len(PALETTE)]
def swatch(i, w=2): return f'{C(i)}{"█" * w}{RESET}'

# ── Layout ────────────────────────────────────────────────────────────────────
CHART_H  = 20
Y_W      = 9
available = term_cols - Y_W - 1
col_total = max(2, available // n_days)
COL_W    = min(3, max(1, col_total - 1))
GAP      = 1
max_daily = max((sum(days[d].values()) for d in days), default=1)

# ── Per-day stacked row heights (largest-remainder, from bottom up) ───────────
# Largest-remainder method: each model gets floor(share), then the models with
# the largest fractional remainders each get +1 until the total_rows budget is met.
# This ensures bar heights always sum exactly to total_rows without rounding drift.
day_rows = {}
for date in sorted_dates:
    total      = sum(days[date].get(m, 0) for m in models)
    total_rows = round(total / max_daily * CHART_H)
    if total <= 0 or total_rows == 0:
        day_rows[date] = [0] * len(models)
        continue
    raw     = [days[date].get(m, 0) / total * total_rows for m in models]
    floored = [int(w) for w in raw]
    deficit = total_rows - sum(floored)
    for idx in sorted(range(len(models)), key=lambda i: raw[i] - floored[i], reverse=True)[:deficit]:
        floored[idx] += 1
    day_rows[date] = floored

def model_at_row(date, row):
    """Return model index for 1-based row counted from bottom, or None."""
    cum = 0
    for i in range(len(models)):
        cum += day_rows[date][i]
        if row <= cum:
            return i
    return None

# ── Title + legend ────────────────────────────────────────────────────────────
legend = '   '.join(f'{swatch(i)} {short(m)}' for i, m in enumerate(models))
active_note = f'{n_days} days with spend' if n_days < window_days else f'{n_days} days'
print(f'\n  Vertex AI Daily Spend — {window_days}-day window ({active_note}, gross)\n')
print(f'  {legend}')
print()

# ── Y-axis label helper ───────────────────────────────────────────────────────
label_rows = {round(f * CHART_H) for f in (0.25, 0.5, 0.75, 1.0)}
label_rows.add(CHART_H)

def y_label(row):
    val = max_daily * row / CHART_H
    s   = f'${val/1000:.1f}k' if val >= 1000 else f'${val:.0f}'
    return f'{s:>{Y_W - 3}} │ '

def y_blank():
    return f'{"":>{Y_W - 3}} │ '

# ── Plot rows top → bottom ────────────────────────────────────────────────────
for row in range(CHART_H, 0, -1):
    prefix = y_label(row) if row in label_rows else y_blank()
    cells  = ''
    for date in sorted_dates:
        idx = model_at_row(date, row)
        if idx is not None:
            cells += C(idx) + '█' * COL_W + RESET + ' ' * GAP
        else:
            cells += ' ' * (COL_W + GAP)
    print(prefix + cells)

# ── X-axis line ───────────────────────────────────────────────────────────────
print(f'{"":>{Y_W - 3}} └' + '─' * ((COL_W + GAP) * n_days))

# ── Date labels ───────────────────────────────────────────────────────────────
day_row   = ' ' * Y_W
month_row = ' ' * Y_W
prev_month = None
for i, date in enumerate(sorted_dates):
    dt         = datetime.date.fromisoformat(date)
    month_abbr = dt.strftime('%b')
    cell_w     = COL_W + GAP

    if COL_W >= 2 or dt.day % 5 == 0 or month_abbr != prev_month:
        day_row += f'{dt.day:<{cell_w}}'
    else:
        day_row += ' ' * cell_w

    if month_abbr != prev_month:
        month_row += f'{month_abbr:<{cell_w}}'
        prev_month  = month_abbr
    else:
        month_row += ' ' * cell_w

print(day_row)
if month_row.strip():
    print(month_row)

# ── Summary table ─────────────────────────────────────────────────────────────
col_w = max((len(short(m)) for m in models), default=10) + 2
sep   = f'  {"─" * col_w}  {"─" * 13}  {"─" * 10}'

print()
print(f'  {" " * col_w}  {"30-day gross":>13}  {"Daily avg":>10}')
print(sep)
for i, m in enumerate(models):
    total = sum(days[d].get(m, 0) for d in days)
    avg   = total / window_days if window_days else 0
    print(f'  {swatch(i)} {short(m):<{col_w - 2}}  ${total:>12,.2f}  ${avg:>9,.2f}')
grand = sum(sum(days[d].get(m, 0) for m in models) for d in days)
print(sep)
print(f'  {BOLD}{"TOTAL":<{col_w}}{RESET}  {BOLD}${grand:>12,.2f}{RESET}  {BOLD}${grand/window_days if window_days else 0:>9,.2f}{RESET}')
print()
PYEOF

# Extract window start/end from filename: gcp_vertex_daily_YYYY-MM-DD_YYYY-MM-DD.json
_BASE=$(basename "$CACHE_FILE" .json)
_WINDOW_START=$(echo "$_BASE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
_WINDOW_END=$(echo   "$_BASE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)

TERM_WIDTH="$TERM_WIDTH" WINDOW_START="$_WINDOW_START" WINDOW_END="$_WINDOW_END" \
  python3 "$_PY" < "$CACHE_FILE"
