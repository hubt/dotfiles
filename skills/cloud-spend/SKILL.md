---
name: cloud-spend
description: Summary of AWS and GCP cloud spending over the past month. Invoke when user asks about cloud costs, AWS/GCP spend, billing summary, or monthly cloud bill.
---

# cloud-spend

Fetch and summarize AWS and GCP cloud spending for the past calendar month.

## Scripts

- **`gather.sh`** — Fetches data from AWS Cost Explorer and GCP BigQuery, populates a local cache, and prints plain-text tables for Claude to read and summarize.
- **`render-chart.sh`** — Reads the cached Bedrock data and renders an ANSI stacked bar chart directly to the terminal. Must be run as a Bash tool call (not echoed as text) so colors display correctly.
- **`render-vertex-chart.sh`** — Reads the cached Vertex AI daily data and renders an ANSI stacked bar chart by Gemini model. Must be run as a Bash tool call so colors display correctly.

## Instructions

### Step 1 — Gather spend data

Check whether the user passed `--no-cache` as an argument to this skill. If they did, append `--no-cache` to the gather script invocation:

```
bash /Users/hubertchen/.claude/skills/cloud-spend/gather.sh [--no-cache]
```

`--no-cache` deletes all cached responses before fetching, forcing a full refresh from AWS Cost Explorer and GCP BigQuery.

Use the script output as the source of truth for all steps below. Do **not** re-run any CLI commands the script already ran.

### Step 2 — Render the Bedrock chart

Run the chart script as a separate Bash tool call so ANSI colors reach the terminal:

```
bash /Users/hubertchen/.claude/skills/cloud-spend/render-chart.sh
```

Do not summarize or describe its output — the chart is self-explanatory. If the script exits with "No cached Bedrock data found", the gather step did not produce any Bedrock data (no charges in the last 30 days).

### Step 2b — Render the Vertex AI chart

Run the Vertex AI chart script as a separate Bash tool call:

```
bash /Users/hubertchen/.claude/skills/cloud-spend/render-vertex-chart.sh
```

Do not summarize or describe its output — the chart is self-explanatory. If the script exits with "No cached Vertex AI data found", the gather step did not produce Vertex AI data (GCP auth may have failed, or no Vertex AI charges in the last 30 days).

### Step 3 — Summarize AWS spend

From the AWS section of the gather output:

- State the **total AWS spend** for the month with currency.
- List the **top services by cost** — flag any that look unexpectedly high or show significant change.
- If multiple accounts are present, note the breakdown.
- If the script reported an error (missing CLI, permissions, no Cost Explorer), explain what the user needs to do to fix it.

### Step 4 — Summarize GCP spend

From the GCP section of the gather output:

- State the **total GCP spend** for the month with currency.
- List the **top services and projects by cost**.
- Call out any large SKU-level line items that warrant attention.
- If billing export isn't configured, give the user clear next steps (the script already prints them — echo and briefly explain).

### Step 5 — Combined summary

Produce a brief combined view:

- **Total cloud spend** = AWS + GCP (convert to a common currency if needed, note the assumption).
- **Biggest cost drivers** across both clouds.
- **Anything unusual**: unexpected spikes, idle resources, services that look misconfigured based on cost.
- Keep this section to 5–8 bullet points — focus on signal, not repetition.

### Formatting rules

- Use a markdown table for service-level breakdowns when there are more than 3 rows.
- Round dollar amounts to two decimal places.
- Do not speculate about causes beyond what the data shows; flag uncertainty explicitly.
- If either cloud had errors, note it prominently at the top so the user knows the summary is incomplete.
