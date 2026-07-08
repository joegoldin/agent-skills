# google-workspace-cli — Calendar, Drive, Docs, Sheets, Slides via `gws`

`gws` (googleworkspace/cli) is one CLI for all Google Workspace APIs, generated from Google's Discovery Service. Joe uses it mainly for **Calendar**, occasionally Drive/Docs/Sheets/Slides.

## The two syntax rules (violating these is the #1 failure)

1. **API parameters go in `--params '<JSON>'`** (query/path params) and `--json '<JSON>'` (request body). There are NO per-parameter flags like `--calendar-id` or `--query` — that's gcloud-style syntax and it does not exist here.
2. **Helpers are prefixed with `+`** (`+agenda`, `+read`, `+write`, `+upload`, `+append`, `+insert`) and DO take normal flags.

```bash
# ❌ WRONG (invented flags)          # ✅ RIGHT
gws calendar events list \          gws calendar events list --params '{
  --calendar-id primary \             "calendarId": "primary",
  --time-min ... --single-events      "timeMin": "2026-07-08T00:00:00-07:00",
                                      "timeMax": "2026-07-09T00:00:00-07:00",
                                      "singleEvents": true, "orderBy": "startTime"}'
```

**Don't guess parameter names** — print the real schema: `gws schema calendar.events.list`, `gws schema drive.files.list`, etc. Every level also has `--help`.

## Auth

First time on a machine: `gws auth setup` (configures GCP project + OAuth client; needs `gcloud`), then `gws auth login` (browser OAuth, pick scopes). Check with `gws auth status`; credentials are encrypted locally. Auth errors mid-command → have the user rerun `gws auth login`.

## Calendar (primary use)

```bash
gws calendar +agenda --today                 # today's events, all calendars (JSON default)
gws calendar +agenda --week --format table   # this week, human-readable
gws calendar +agenda --days 3 --timezone America/Los_Angeles
gws calendar calendarList list               # calendar IDs
# Precise window with recurrences expanded (the params above in one line):
gws calendar events list --params '{"calendarId":"primary","timeMin":"2026-07-08T00:00:00-07:00","timeMax":"2026-07-09T00:00:00-07:00","singleEvents":true,"orderBy":"startTime"}'
```

`+agenda` is read-only. Event JSON: `.summary`, `.start.dateTime` (or `.start.date` for all-day), `.end.*`, `.status` ("cancelled" = skip).

## Drive / Docs / Sheets / Slides (occasional)

```bash
gws drive files list --params '{"q":"name contains \"budget\"","pageSize":10}'   # search (Drive q syntax)
gws drive files export --params '{"fileId":"ID","mimeType":"text/plain"}' --output out.txt  # export a Google Doc
gws drive +upload ./file.pdf --name "Report"
gws docs documents get --params '{"documentId":"ID"}'      # full doc JSON
gws docs +write --document ID --text 'appended text'
gws sheets +read --spreadsheet ID --range 'Sheet1!A1:D10'
gws sheets +append --spreadsheet ID --range 'Sheet1!A:B' --values 'Alice,95'
gws slides presentations get --params '{"presentationId":"ID"}'
```

## Output & paging

JSON by default; `--format table|yaml|csv` for humans. `--page-all` auto-paginates (NDJSON, one page per line; `--page-limit N`). `--dry-run` validates a request without sending — use it when unsure.

## Common mistakes

| Mistake | Fix |
|---|---|
| Inventing `--flag-style` API params | Everything goes in `--params`/`--json` as JSON |
| Guessing param names | `gws schema <service.resource.method>` |
| `gws calendar agenda` | It's `gws calendar +agenda` (helpers need `+`) |
| First-time auth with only `gws auth login` | Run `gws auth setup` first (needs gcloud) |
| Forgetting `"singleEvents": true` | Recurring events won't expand into instances |
| Quoting Drive `q` wrong in fish/bash | Single-quote the JSON, escape inner double quotes |
