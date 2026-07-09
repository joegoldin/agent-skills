# day-sync — coordinate the day/week across calendar, Notion, GitHub, and the daily note

Brief the user on their day/week: Google Calendar (via the `gws` CLI) +
Notion tasks assigned to them + their open/recent GitHub PRs + the daily
note in their Obsidian vault — plus what they finished locally that Notion
doesn't reflect yet. Read-only against every external system; writes only
the daily note.

## Configuration (required once)

`~/.config/day-sync/config.json` (override path via `DAY_SYNC_CONFIG`):

```json
{
  "vault": "/path/to/Obsidian Vault",
  "journal": "Notes/Journal",
  "timezone": "America/Los_Angeles",
  "notion_user_id": "<notion user uuid>",
  "notion_data_source_id": "<tasks db data-source uuid>",
  "notion_token_file": "/path/to/notion-api-token",
  "gh_org": "<github org to watch, omit to skip PRs>",
  "work_tag": "#work",
  "query_exclude_statuses": ["Archived", "Released"],
  "done_statuses": ["done", "complete", "released", "archived"],
  "almost_done_statuses": ["ready for release"]
}
```

`query_exclude_statuses` filters server-side and MUST name real status
options from the Notion DB (Notion 400s on unknown names); leave it out to
filter client-side only via `done_statuses`.

## How to run

From this skill's directory:

    ./day_sync.py brief --json      # machine-readable; use this when driving
    ./day_sync.py brief             # human text
    ./day_sync.py brief --week --json
    ./day_sync.py add --dry-run --yes   # diff of default insertions (non-interactive)
    ./day_sync.py add --yes         # insert defaults (missing events + in-progress Notion tasks + review PRs)
    ./day_sync.py add               # interactive numbered picker (user runs this in a terminal)

Auth: Notion token comes from `notion_token_file` (e.g. an
agenix-decrypted path); a missing-file warning means it isn't mounted.
Calendar needs the `gws` CLI authenticated (`gws auth login` — see the
google-workspace-cli skill). PRs need an authenticated `gh`.

## What to do with the data

1. Run `brief --json` (add `--week` if they asked about the week).
2. TLDR in this order, skipping empty sections:
   - Schedule: time-ordered events; call out conflicts and usable gaps.
   - Due/overdue Notion work: OVERDUE first, then due-today, then the rest
     grouped by status. Link titles to their Notion URLs.
   - Pull requests: authored PRs with review state, PRs awaiting their
     review, recently-merged ones — relay each correlation suggestion (they
     map PRs to 🅽 tasks / todo lines). claude -p powers matching; if it
     fails a deterministic fallback runs silently.
   - Note state: what's already planned in today's note vs. what the
     schedule/Notion say is missing (compare titles yourself).
   - Sync back to Notion: list each item's suggestion verbatim — things the
     user finished/moved locally that Notion still shows as open.
3. Offer the add step: "want me to insert the missing items?" On yes, run
   `add --dry-run --yes`, show the diff, then `add --yes` once confirmed.
   For cherry-picking, have the user run `./day_sync.py add` in a terminal.

## Conventions

- Inserted Notion tasks look like `- [ ] Title <work_tag> 🅽 <id> 📅 <due>`
  — the 🅽 marker is the dedup key; never strip it when editing task lines.
  A titled variant `🅽 [Title](<id>)` is also recognized.
- Don't insert calendar events that already have a matching line in the
  note (the script title-matches, but sanity-check its diff).
- This tool never writes to Notion, GitHub, or the calendar; sync-back is
  advisory.
