#!/usr/bin/env bash
# Gathers AWS and GCP cloud spend data and outputs structured text for Claude.
#
# Two-script architecture:
#   gather.sh       — fetches data via AWS CE / GCP bq, populates the cache,
#                     and prints plain-text tables that Claude reads and summarizes.
#   render-chart.sh — reads the cached Bedrock JSON and renders an ANSI stacked
#                     bar chart directly to the terminal (run as a Bash tool call
#                     so colors reach the terminal rather than going through Claude).
set -euo pipefail

# Parse arguments
NO_CACHE=false
for arg in "$@"; do
  case "$arg" in
    --no-cache) NO_CACHE=true ;;
  esac
done

# Compute last month's date range
YEAR=$(date -v-1m +%Y 2>/dev/null || date -d "last month" +%Y)
MONTH=$(date -v-1m +%m 2>/dev/null || date -d "last month" +%m)
START="${YEAR}-${MONTH}-01"
END=$(date +%Y-%m-01)   # first day of current month = exclusive end
TODAY=$(date +%Y-%m-%d)
CUR_MONTH_START=$(date +%Y-%m-01)
BEDROCK_START=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "30 days ago" +%Y-%m-%d)

echo "=== Cloud Spend Report: ${START} to ${END} ==="
echo ""

# ── Cache helpers ─────────────────────────────────────────────────────────────
CACHE_DIR="${HOME}/.cache/cloud-spend"
mkdir -p "$CACHE_DIR"

if $NO_CACHE; then
  rm -f "${CACHE_DIR}"/*.json "${CACHE_DIR}"/*.txt
fi

CACHE_STATUS_FILE=$(mktemp)
trap 'rm -f "$CACHE_STATUS_FILE"' EXIT

# aws_ce_cached KEY [get-cost-and-usage args...]
# Serves from cache if < 1 day old; otherwise fetches, caches, and returns.
# Logs cache status to CACHE_STATUS_FILE for the freshness summary.
# Exits non-zero on fetch failure.
aws_ce_cached() {
  local key="$1"; shift
  local f="${CACHE_DIR}/${key}.json"
  local now; now=$(date +%s)
  local max_age=86400  # 1 day

  if [[ -f "$f" ]]; then
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    if (( now - mtime < max_age )); then
      local age_s=$(( now - mtime ))
      local age_h=$(( age_s / 3600 ))
      local age_m=$(( (age_s % 3600) / 60 ))
      local filled_at
      filled_at=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null \
                  || date -d "@$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
      printf 'CACHED  %-45s  filled %s  (%dh %02dm ago)\n' \
        "$key" "$filled_at" "$age_h" "$age_m" >> "$CACHE_STATUS_FILE"
      cat "$f"
      return 0
    fi
  fi

  printf 'FRESH   %-45s  fetched now\n' "$key" >> "$CACHE_STATUS_FILE"
  local tmp; tmp=$(mktemp)
  if aws ce "$@" --output json > "$tmp" 2>&1; then
    mv "$tmp" "$f"
    cat "$f"
  else
    # Show error and clean up — do not cache failures
    cat "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi
}

# bq_cached KEY SQL
# Serves from cache if < 1 hour old; otherwise queries BigQuery, caches, and returns.
# On query failure, prints the error output to stdout and returns 1.
bq_cached() {
  local key="$1" sql="$2"
  local f="${CACHE_DIR}/${key}.txt"
  local now; now=$(date +%s)
  local max_age=3600  # 1 hour

  if [[ -f "$f" ]]; then
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    if (( now - mtime < max_age )); then
      local age_s=$(( now - mtime ))
      local age_h=$(( age_s / 3600 ))
      local age_m=$(( (age_s % 3600) / 60 ))
      local filled_at
      filled_at=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null \
                  || date -d "@$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
      printf 'CACHED  %-45s  filled %s  (%dh %02dm ago)\n' \
        "$key" "$filled_at" "$age_h" "$age_m" >> "$CACHE_STATUS_FILE"
      cat "$f"
      return 0
    fi
  fi

  printf 'FRESH   %-45s  fetched now\n' "$key" >> "$CACHE_STATUS_FILE"
  local tmp; tmp=$(mktemp)
  if bq query --nouse_legacy_sql --format=pretty "$sql" > "$tmp" 2>&1; then
    mv "$tmp" "$f"
    cat "$f"
  else
    cat "$tmp"
    rm -f "$tmp"
    return 1
  fi
}

# bq_cached_json KEY SQL
# Like bq_cached but uses JSON array output (--format=json), stores as .json,
# and does NOT echo to stdout — the file is consumed by render scripts (e.g.
# render-vertex-chart.sh). Still logs cache status to CACHE_STATUS_FILE.
bq_cached_json() {
  local key="$1" sql="$2"
  local f="${CACHE_DIR}/${key}.json"
  local now; now=$(date +%s)
  local max_age=3600  # 1 hour

  if [[ -f "$f" ]]; then
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    if (( now - mtime < max_age )); then
      local age_s=$(( now - mtime ))
      local age_h=$(( age_s / 3600 ))
      local age_m=$(( (age_s % 3600) / 60 ))
      local filled_at
      filled_at=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null \
                  || date -d "@$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null)
      printf 'CACHED  %-45s  filled %s  (%dh %02dm ago)\n' \
        "$key" "$filled_at" "$age_h" "$age_m" >> "$CACHE_STATUS_FILE"
      return 0
    fi
  fi

  printf 'FRESH   %-45s  fetched now\n' "$key" >> "$CACHE_STATUS_FILE"
  local tmp; tmp=$(mktemp)
  if bq query --nouse_legacy_sql --format=json "$sql" > "$tmp" 2>&1; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"
    return 1
  fi
}

# ── AWS ──────────────────────────────────────────────────────────────────────
echo "## AWS"
if ! command -v aws &>/dev/null; then
  echo "ERROR: aws CLI not found — install with: brew install awscli"
else
  # Gate: try fetching account data; if it fails (auth error etc.) bail out
  ACCT_JSON=$(aws_ce_cached "acct_${START}_${END}" \
    get-cost-and-usage \
    --time-period "Start=${START},End=${END}" \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --group-by Type=DIMENSION,Key=LINKED_ACCOUNT 2>/dev/null) || {
      echo "ERROR: AWS Cost Explorer query failed — check auth (aws sso login?)"
      ACCT_JSON=""
    }

  if [[ -n "$ACCT_JSON" ]]; then
    echo ""
    echo "### By Account"
    echo "$ACCT_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data['ResultsByTime'][0]['Groups']
rows = [(g['Keys'][0], float(g['Metrics']['UnblendedCost']['Amount'])) for g in groups]
rows.sort(key=lambda x: x[1], reverse=True)
total = sum(r[1] for r in rows)
print(f'Total across all accounts: \${total:.4f} USD')
print()
print(f'  {\"Account\":<20} {\"Cost (USD)\":>12}')
print(f'  {\"-\"*20} {\"-\"*12}')
for acct, cost in rows:
    print(f'  {acct:<20} \${cost:>11.4f}')
"

    echo ""
    echo "### By Service — gross vs net (top 25 by gross usage, before and after credits)"
    GROSS_JSON=$(aws_ce_cached "svc_gross_${START}_${END}" \
      get-cost-and-usage \
      --time-period "Start=${START},End=${END}" \
      --granularity MONTHLY \
      --metrics UnblendedCost \
      --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
      --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null)
    NET_JSON=$(aws_ce_cached "svc_net_${START}_${END}" \
      get-cost-and-usage \
      --time-period "Start=${START},End=${END}" \
      --granularity MONTHLY \
      --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null)
    python3 -c "
import sys, json
gross_data, net_data = json.load(sys.stdin)
gross = {g['Keys'][0]: float(g['Metrics']['UnblendedCost']['Amount'])
         for g in gross_data['ResultsByTime'][0]['Groups']}
net   = {g['Keys'][0]: float(g['Metrics']['UnblendedCost']['Amount'])
         for g in net_data['ResultsByTime'][0]['Groups']}
all_svcs = sorted(gross.keys(), key=lambda s: gross.get(s, 0), reverse=True)
total_gross = sum(gross.values())
total_net   = sum(net.values())
print(f'  Total gross usage: \${total_gross:.2f} USD    Net after credits: \${total_net:.2f} USD')
print()
print(f'  {\"Service\":<50} {\"Gross (USD)\":>12} {\"Net (USD)\":>12} {\"Credits\":>12}')
print(f'  {\"-\"*50} {\"-\"*12} {\"-\"*12} {\"-\"*12}')
for svc in all_svcs[:25]:
    g = gross.get(svc, 0)
    n = net.get(svc, 0)
    credit = n - g
    if g > 0.01 or abs(credit) > 0.01:
        print(f'  {svc:<50} \${g:>11.2f} \${n:>11.2f} \${credit:>11.2f}')
# Merge the two CE responses into a two-element JSON array so Python can unpack both in one read.
" <<< "[${GROSS_JSON}, ${NET_JSON}]"

    echo ""
    echo "### Bedrock — Daily Spend by Model (last 30 days, gross)"
    # Fetches daily Bedrock cost data and populates the cache for render-chart.sh.
    # Outputs a plain-text summary table for Claude to read; the visual chart is
    # rendered separately by render-chart.sh so ANSI colors reach the terminal.
    BEDROCK_JSON=$(aws_ce_cached "bedrock_daily_${BEDROCK_START}_${TODAY}" \
      get-cost-and-usage \
      --time-period "Start=${BEDROCK_START},End=${TODAY}" \
      --granularity DAILY \
      --metrics UnblendedCost \
      --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
      --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null)
    echo "$BEDROCK_JSON" | python3 -c "
import sys, json

data = json.load(sys.stdin)
results = data['ResultsByTime']

# ── Aggregate daily costs per model ───────────────────────────────────────────
days = {}
all_models = set()
for period in results:
    date = period['TimePeriod']['Start']
    days[date] = {}
    for group in period['Groups']:
        svc  = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        if 'Bedrock' in svc or 'Claude' in svc:
            all_models.add(svc)
            days[date][svc] = cost

if not all_models:
    print('  No Bedrock charges found in the last 30 days.')
    sys.exit(0)

models = sorted(all_models, key=lambda m: sum(days[d].get(m, 0) for d in days), reverse=True)
n_days = len(days)

def short(m):
    return m.replace(' (Amazon Bedrock Edition)', '').replace('Claude ', '')

# ── Summary table ─────────────────────────────────────────────────────────────
col_w = max((len(short(m)) for m in models), default=10) + 2
sep   = f'  {\"─\" * col_w}  {\"─\" * 13}  {\"─\" * 10}'

print(f'  {\" \" * col_w}  {\"30-day gross\":>13}  {\"Daily avg\":>10}')
print(sep)
for m in models:
    total = sum(days[d].get(m, 0) for d in days)
    avg   = total / n_days if n_days else 0
    print(f'  {short(m):<{col_w}}  \${total:>12,.2f}  \${avg:>9,.2f}')
grand = sum(sum(days[d].get(m, 0) for m in models) for d in days)
print(sep)
print(f'  {\"TOTAL\":<{col_w}}  \${grand:>12,.2f}  \${grand/n_days if n_days else 0:>9,.2f}')
"

    echo ""
    echo "### By Record Type (charges vs credits vs refunds)"
    aws_ce_cached "record_type_${START}_${END}" \
      get-cost-and-usage \
      --time-period "Start=${START},End=${END}" \
      --granularity MONTHLY \
      --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=RECORD_TYPE 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data['ResultsByTime'][0]['Groups']
rows = [(g['Keys'][0], float(g['Metrics']['UnblendedCost']['Amount'])) for g in groups]
rows.sort(key=lambda x: x[1], reverse=True)
net = sum(r[1] for r in rows)
print(f'Net total (after credits/refunds): \${net:.4f} USD')
print()
for rtype, cost in rows:
    print(f'  {rtype:<30} \${cost:>11.4f}')
"

    echo ""
    echo "### By Account + Service (top 30)"
    aws_ce_cached "acct_svc_${START}_${END}" \
      get-cost-and-usage \
      --time-period "Start=${START},End=${END}" \
      --granularity MONTHLY \
      --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=LINKED_ACCOUNT Type=DIMENSION,Key=SERVICE 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data['ResultsByTime'][0]['Groups']
rows = [(g['Keys'][0], g['Keys'][1], float(g['Metrics']['UnblendedCost']['Amount'])) for g in groups]
rows.sort(key=lambda x: x[2], reverse=True)
print(f'  {\"Account\":<15} {\"Service\":<45} {\"Cost (USD)\":>12}')
print(f'  {\"-\"*15} {\"-\"*45} {\"-\"*12}')
for acct, svc, cost in rows[:30]:
    if cost > 0.000001:
        print(f'  {acct:<15} {svc:<45} \${cost:>11.4f}')
"

    if [[ "$CUR_MONTH_START" != "$START" ]]; then
      echo ""
      echo "### Current month (${CUR_MONTH_START} to ${TODAY}) — gross vs net by service"
      CUR_GROSS_JSON=$(aws_ce_cached "cur_gross_${CUR_MONTH_START}" \
        get-cost-and-usage \
        --time-period "Start=${CUR_MONTH_START},End=${TODAY}" \
        --granularity MONTHLY \
        --metrics UnblendedCost \
        --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
        --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null)
      CUR_NET_JSON=$(aws_ce_cached "cur_net_${CUR_MONTH_START}" \
        get-cost-and-usage \
        --time-period "Start=${CUR_MONTH_START},End=${TODAY}" \
        --granularity MONTHLY \
        --metrics UnblendedCost \
        --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null)
      python3 -c "
import sys, json
gross_data, net_data = json.load(sys.stdin)
gross = {g['Keys'][0]: float(g['Metrics']['UnblendedCost']['Amount'])
         for g in gross_data['ResultsByTime'][0]['Groups']}
net   = {g['Keys'][0]: float(g['Metrics']['UnblendedCost']['Amount'])
         for g in net_data['ResultsByTime'][0]['Groups']}
all_svcs = sorted(gross.keys(), key=lambda s: gross.get(s, 0), reverse=True)
total_gross = sum(gross.values())
total_net   = sum(net.values())
print(f'  Total gross usage: \${total_gross:.2f} USD    Net after credits: \${total_net:.2f} USD')
print()
print(f'  {\"Service\":<50} {\"Gross (USD)\":>12} {\"Net (USD)\":>12} {\"Credits\":>12}')
print(f'  {\"-\"*50} {\"-\"*12} {\"-\"*12} {\"-\"*12}')
for svc in all_svcs[:25]:
    g = gross.get(svc, 0)
    n = net.get(svc, 0)
    credit = n - g
    if g > 0.01 or abs(credit) > 0.01:
        print(f'  {svc:<50} \${g:>11.2f} \${n:>11.2f} \${credit:>11.2f}')
# Merge the two CE responses into a two-element JSON array so Python can unpack both in one read.
" <<< "[${CUR_GROSS_JSON}, ${CUR_NET_JSON}]"
    fi
  fi
fi

echo ""

# ── GCP ──────────────────────────────────────────────────────────────────────
echo "## GCP"
if ! command -v gcloud &>/dev/null; then
  echo "ERROR: gcloud CLI not found — install from https://cloud.google.com/sdk"
elif ! command -v bq &>/dev/null; then
  echo "ERROR: bq CLI not found — install with: gcloud components install bq"
else
  BILLING_DATASET="${GCP_BILLING_DATASET:-}"
  BILLING_TABLE="${GCP_BILLING_TABLE:-}"

  if [[ -z "$BILLING_DATASET" || -z "$BILLING_TABLE" ]]; then
    echo "INFO: GCP_BILLING_DATASET and GCP_BILLING_TABLE env vars not set."
    echo "      Searching for billing export tables in accessible projects..."
    echo ""
    FOUND=""
    while IFS= read -r project; do
      DATASETS=$(bq ls --project_id="$project" --format=prettyjson 2>/dev/null \
        | python3 -c "import sys,json; [print(d['datasetReference']['projectId']+'.'+d['datasetReference']['datasetId']) for d in json.load(sys.stdin) if 'billing' in d['datasetReference']['datasetId'].lower()]" 2>/dev/null || true)
      if [[ -n "$DATASETS" ]]; then
        FOUND="$FOUND $DATASETS"
      fi
    done < <(gcloud projects list --format="value(projectId)" --limit=20 2>/dev/null)

    if [[ -z "$FOUND" ]]; then
      echo "No BigQuery billing export dataset found."
      echo ""
      echo "To enable GCP cost reporting, set up billing export:"
      echo "  1. Go to: Billing → Billing export → BigQuery export"
      echo "  2. Enable 'Standard usage cost' export to a dataset"
      echo "  3. Re-run this skill with:"
      echo "     export GCP_BILLING_DATASET=<project.dataset>"
      echo "     export GCP_BILLING_TABLE=gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX"
      gcloud config get-value project 2>/dev/null | xargs -I{} echo "Active project: {}"
    else
      echo "Found potential billing datasets:$FOUND"
      echo "Set GCP_BILLING_DATASET and GCP_BILLING_TABLE and re-run."
    fi
  else
    FULL_TABLE="${BILLING_DATASET}.${BILLING_TABLE}"

    echo "Dataset: ${FULL_TABLE}"
    echo ""

    echo "### Total spend — gross vs net"
    bq_cached "gcp_total_${START}_${END}" \
      "WITH base AS (
         SELECT cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${START}'
           AND DATE(usage_start_time) < '${END}'
       )
       SELECT FORMAT('%.2f', SUM(cost))                          AS gross,
              FORMAT('%.2f', SUM(credit_amount))                 AS credits,
              FORMAT('%.2f', SUM(cost) + SUM(credit_amount))     AS net,
              currency
       FROM base
       GROUP BY currency" || echo "ERROR: query failed"

    echo ""
    echo "### By Service — gross vs net (top 15)"
    bq_cached "gcp_svc_${START}_${END}" \
      "WITH base AS (
         SELECT service.description AS service,
                cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${START}'
           AND DATE(usage_start_time) < '${END}'
       ), agg AS (
         SELECT service,
                SUM(cost)                          AS gross_cost,
                SUM(credit_amount)                 AS total_credits,
                SUM(cost) + SUM(credit_amount)     AS net_cost,
                currency
         FROM base
         GROUP BY service, currency
       )
       SELECT service,
              FORMAT('%.2f', gross_cost)      AS gross,
              FORMAT('%.2f', total_credits)   AS credits,
              FORMAT('%.2f', net_cost)        AS net,
              currency
       FROM agg
       ORDER BY gross_cost DESC
       LIMIT 15" || echo "ERROR: query failed"

    echo ""
    echo "### By Project — gross vs net (top 15)"
    bq_cached "gcp_proj_${START}_${END}" \
      "WITH base AS (
         SELECT project.id AS project,
                cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${START}'
           AND DATE(usage_start_time) < '${END}'
       ), agg AS (
         SELECT project,
                SUM(cost)                          AS gross_cost,
                SUM(credit_amount)                 AS total_credits,
                SUM(cost) + SUM(credit_amount)     AS net_cost,
                currency
         FROM base
         GROUP BY project, currency
       )
       SELECT project,
              FORMAT('%.2f', gross_cost)      AS gross,
              FORMAT('%.2f', total_credits)   AS credits,
              FORMAT('%.2f', net_cost)        AS net,
              currency
       FROM agg
       ORDER BY gross_cost DESC
       LIMIT 15" || echo "ERROR: query failed"

    echo ""
    echo "### By SKU — gross vs net (top 10 — largest individual line items)"
    bq_cached "gcp_sku_${START}_${END}" \
      "WITH base AS (
         SELECT service.description AS service,
                sku.description AS sku,
                cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${START}'
           AND DATE(usage_start_time) < '${END}'
       ), agg AS (
         SELECT service,
                sku,
                SUM(cost)                          AS gross_cost,
                SUM(credit_amount)                 AS total_credits,
                SUM(cost) + SUM(credit_amount)     AS net_cost,
                currency
         FROM base
         GROUP BY service, sku, currency
       )
       SELECT service,
              sku,
              FORMAT('%.2f', gross_cost)      AS gross,
              FORMAT('%.2f', total_credits)   AS credits,
              FORMAT('%.2f', net_cost)        AS net,
              currency
       FROM agg
       ORDER BY gross_cost DESC
       LIMIT 10" || echo "ERROR: query failed"

    echo ""
    echo "### Vertex AI — By Model (last 30 days, gross vs net)"
    bq_cached "gcp_vertex_model_${BEDROCK_START}_${TODAY}" \
      "WITH base AS (
         SELECT TRIM(REGEXP_REPLACE(sku.description,
                  r'\s+(?:Input|Output|Batch)(?:\s.*)?$', '')) AS model,
                cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${BEDROCK_START}'
           AND DATE(usage_start_time) < '${TODAY}'
           AND service.description = 'Vertex AI'
       ), agg AS (
         SELECT model,
                SUM(cost)                          AS gross_cost,
                SUM(credit_amount)                 AS total_credits,
                currency
         FROM base
         GROUP BY model, currency
       )
       SELECT model,
              FORMAT('%.2f', gross_cost)                    AS gross_30d,
              FORMAT('%.2f', gross_cost / 30)               AS daily_avg,
              FORMAT('%.2f', total_credits)                 AS credits,
              FORMAT('%.2f', gross_cost + total_credits)    AS net_30d,
              currency
       FROM agg
       ORDER BY gross_cost DESC
       LIMIT 15" || echo "ERROR: query failed"

    echo ""
    echo "### Vertex AI — By SKU (last 30 days, gross vs net)"
    bq_cached "gcp_vertex_sku_${BEDROCK_START}_${TODAY}" \
      "WITH base AS (
         SELECT sku.description AS sku,
                cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${BEDROCK_START}'
           AND DATE(usage_start_time) < '${TODAY}'
           AND service.description = 'Vertex AI'
       ), agg AS (
         SELECT sku,
                SUM(cost)                          AS gross_cost,
                SUM(credit_amount)                 AS total_credits,
                currency
         FROM base
         GROUP BY sku, currency
       )
       SELECT sku,
              FORMAT('%.2f', gross_cost)                    AS gross_30d,
              FORMAT('%.2f', gross_cost / 30)               AS daily_avg,
              FORMAT('%.2f', total_credits)                 AS credits,
              FORMAT('%.2f', gross_cost + total_credits)    AS net_30d,
              currency
       FROM agg
       ORDER BY gross_cost DESC
       LIMIT 20" || echo "ERROR: query failed"

    # Cache daily-by-model data for render-vertex-chart.sh (not echoed to stdout)
    bq_cached_json "gcp_vertex_daily_${BEDROCK_START}_${TODAY}" \
      "WITH base AS (
         SELECT FORMAT_DATE('%Y-%m-%d', DATE(usage_start_time)) AS usage_date,
                TRIM(REGEXP_REPLACE(sku.description,
                  r'\s+(?:Input|Output|Batch)(?:\s.*)?$', '')) AS model,
                cost,
                (SELECT IFNULL(SUM(c.amount), 0) FROM UNNEST(credits) AS c) AS credit_amount,
                currency
         FROM \`${FULL_TABLE}\`
         WHERE DATE(usage_start_time) >= '${BEDROCK_START}'
           AND DATE(usage_start_time) < '${TODAY}'
           AND service.description = 'Vertex AI'
       ), agg AS (
         SELECT usage_date, model,
                SUM(cost)          AS gross,
                SUM(credit_amount) AS credits,
                currency
         FROM base GROUP BY usage_date, model, currency
       )
       SELECT usage_date, model, gross, credits, currency
       FROM agg
       ORDER BY usage_date, gross DESC" || true
  fi
fi

if [[ -s "$CACHE_STATUS_FILE" ]]; then
  echo "## Data Freshness"
  echo ""
  echo "  Status   Key                                               Filled / Fetched"
  echo "  -------- ------------------------------------------------- ----------------------------"
  while IFS= read -r line; do
    echo "  $line"
  done < "$CACHE_STATUS_FILE"
  echo ""
fi

echo "=== END OF RAW DATA ==="
