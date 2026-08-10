---
name: apple-mail
description: Use when searching, reading, triaging, or counting email in Apple Mail / Mail.app on macOS, or creating and revising draft replies — inbox questions, unread counts, finding messages from a sender, reading a message body, listing mailboxes or accounts. Trigger on mentions of Apple Mail, Mail.app, Envelope Index, emlx, or "my email"/"my inbox" on a Mac.
allowed-tools: Bash(sqlite3:*) Bash(python3:*)
---

# apple-mail — search, read, and draft (never send) in Mail.app

Two engines, chosen by task:

1. **Read anything → SQLite.** Mail's own index at `~/Library/Mail/V*/MailData/Envelope Index` answers search/list/count queries in milliseconds. AppleScript iteration over the same data takes seconds to minutes (measured 137s for a subject search on a 32k mailbox vs 20ms in SQL). Never search or enumerate mail via AppleScript.
2. **Change anything → AppleScript** (`osascript`): create drafts, mark read, flag, move. Mail must be running; first use triggers an Automation permission prompt.

## Hard limits

**Never send email. There is no authorized path to send from this skill.**

- Never call `send`, never create an outgoing message with a send step, never UI-script the Send button, never use SMTP/IMAP credentials to transmit.
- Every compose/reply/forward request ends at a **saved draft** plus a message to the user: "draft is in Mail's Drafts — review and hit Send yourself."
- The user wrote "send it" / "get it ready to go" / "so I don't have to do anything"? Still a draft. Sending is the one action reserved for a human in Mail.app.
- Never delete or move messages except: (a) the user explicitly identified the exact message(s), or (b) deleting the *old copy* of a draft you just recreated as part of an edit.

Red flags that mean stop — you are about to violate the rule: "it's just a quick thank-you", "the user clearly wants it sent", "the draft is already perfect", "replying to a no-reply address is harmless".

## Fast path: Envelope Index (SQLite, read-only)

```bash
DB=$(ls -d "$HOME"/Library/Mail/V*/MailData/"Envelope Index" | sort -V | tail -1)
sqlite3 "file:$DB?mode=ro" "<SQL>"
```

- Always open with the `file:...?mode=ro` URI. Never `immutable=1` (skips the WAL → stale rows) and never copy the DB.
- "unable to open database file" → the terminal lacks Full Disk Access (System Settings → Privacy & Security → Full Disk Access). Ask the user to grant it; there is no workaround.
- Data is as fresh as Mail's last sync. Mail closed for a week = week-old index.
- `date_received`/`date_sent` are Unix epoch seconds: `datetime(m.date_received,'unixepoch','localtime')`.

### Schema (V10)

`messages` rows join outward: `subject`→`subjects.ROWID`, `sender`→`addresses.ROWID` (`address`, `comment`=display name), `mailbox`→`mailboxes.ROWID` (`url` like `imap://<account-uuid>/INBOX`, plus reliable `total_count`/`unread_count`), `summary`→`summaries.ROWID`. `recipients` (`message`, `address`→addresses, `type` 0=To 1=CC) covers To/CC. RFC Message-ID lives in `message_global_data.message_id_header`, joined `ON message_global_data.message_id = messages.message_id`. Threads group by `messages.conversation_id`.

Base template — always filter `m.deleted = 0` and exclude junk/trash mailboxes:

```sql
SELECT m.ROWID, datetime(m.date_received,'unixepoch','localtime') AS dt,
       a.address AS sender, a.comment AS sender_name, s.subject,
       m.read, m.flagged, mb.url AS mailbox
FROM messages m
JOIN subjects s   ON m.subject = s.ROWID
JOIN addresses a  ON m.sender  = a.ROWID
JOIN mailboxes mb ON m.mailbox = mb.ROWID
WHERE m.deleted = 0
  AND mb.url NOT LIKE '%Junk%' AND mb.url NOT LIKE '%Deleted%' AND mb.url NOT LIKE '%Trash%'
ORDER BY m.date_received DESC LIMIT 25;
```

### Recipes (add to the template's WHERE)

| Intent | Clause |
|---|---|
| From a sender | `AND (a.address LIKE '%capitalone%' OR a.comment LIKE '%Capital One%')` |
| Subject search | `AND s.subject LIKE '%invoice%'` |
| Only the inbox | `AND mb.url LIKE '%/INBOX'` |
| Unread | `AND m.read = 0` |
| Last N days | `AND m.date_received >= strftime('%s','now') - 86400*N` |
| Sent TO someone | join `recipients r ON r.message = m.ROWID JOIN addresses ra ON ra.ROWID = r.address` + `AND ra.address LIKE '%name%'` |
| Whole thread | `AND m.conversation_id = (SELECT conversation_id FROM messages WHERE ROWID = ?)` |
| Human mail only (skip automated) | `AND m.automated_conversation = 0 AND (m.unsubscribe_type IS NULL OR m.unsubscribe_type = 0)` |
| Newsletters/bulk | `AND m.unsubscribe_type > 0` |
| Attachments | join `attachments att ON att.message = m.ROWID` (has `name`) |

Mailbox/account survey: `SELECT ROWID, url, total_count, unread_count FROM mailboxes ORDER BY total_count DESC;` Account UUIDs in urls match directory names under `~/Library/Mail/V10/`; identify whose account a UUID is by its most-frequent recipient address.

**Unread-count gotcha:** the index's idea of unread can exceed what Mail's UI shows (observed 1730 vs 601 for the same INBOX). When the user asks "how many unread do I have", report Mail's own number — `osascript -e 'tell application "Mail" to get unread count of inbox'` — and use SQL counts only for filtered breakdowns, labeled as index counts.

## Reading a message body

Bodies are NOT in the Envelope Index. Two steps, cheap first:

1. `SELECT su.summary FROM messages m JOIN summaries su ON m.summary = su.ROWID WHERE m.ROWID = <ROWID>;` — Apple's extracted text, present for only a small fraction of recent messages.
2. `python3 scripts/mail-body.py <ROWID> [<ROWID>...]` (script lives in this skill's directory) — locates the `.emlx` file on disk and prints JSON with headers, text body, and attachment names. `.partial.emlx` (headers + truncated body) is used automatically when the full body isn't cached locally.

## Actions: AppleScript via osascript

Rules that prevent the known failures:

- **Find messages in SQL first**, then bridge to AppleScript by RFC Message-ID. Mail's numeric `id` is a 64-bit (often negative) integer that overflows AppleScript's integer type — `whose id is N` errors with "Can't make ... into type integer". `message id` (the RFC header, **without angle brackets**) works:

```bash
RFC=$(sqlite3 "file:$DB?mode=ro" "SELECT trim(g.message_id_header,'<>') FROM messages m
  JOIN message_global_data g ON g.message_id = m.message_id WHERE m.ROWID = 439521;")
```

- Use the app-level **unified mailboxes** — `inbox`, `drafts mailbox`, `sent mailbox` aggregate all accounts, so no account/mailbox loops. Per-account `mailbox "Drafts" of account X` lookups fail silently on some account types; inbox names are localized on non-English systems.
- Escape `\` then `"` in any shell-interpolated AppleScript string; unescaped quotes fail as opaque "Can't make" errors.
- Batch mutations into ONE osascript (each subprocess costs 100–300ms); wrap long operations in `with timeout of 300 seconds ... end timeout` (default 60s AppleEvent timeout breaks Exchange).

### Create a reply draft (verified recipe — no windows, no delays)

```applescript
tell application "Mail"
    set msgs to (messages of inbox whose message id is "RFC_ID_WITHOUT_BRACKETS")
    set r to reply (item 1 of msgs) without opening window
    set content of r to "Body text here.\n\nBest,\nJoe"
    set sender of r to "joe.goldin@kanary.com" -- else Mail routes via the default account
    save r -- lands in Drafts; DO NOT call send
    return "draft saved"
end tell
```

`reply theMsg with properties {...}` is invalid syntax — reply first, then set properties. Always set `sender`, or the draft silently lands under the wrong account's identity.

New (non-reply) draft: `make new outgoing message with properties {subject:"...", content:"...", visible:false}`, then `make new to recipient at end of to recipients of it with properties {address:"..."}`, set `sender`, `save`.

### Edit an existing draft

Saved drafts are read-only to AppleScript — `set content of <draft>` errors with "Can't set content of message". The edit is a replace:

1. Read the old draft from `drafts mailbox` (subject, content, `reply to`, recipients).
2. Create a new outgoing message / reply with the amended text and `save` it.
3. Delete the old draft (the one legitimate unprompted deletion).

### Mark read / flag / move (batch, one script)

```applescript
tell application "Mail"
    repeat with rfcId in {"id1@host", "id2@host"}
        set msgs to (messages of inbox whose message id is rfcId)
        if (count of msgs) > 0 then set read status of item 1 of msgs to true
        -- flag: set flagged status ... / move: move (item 1 of msgs) to mailbox "Archive" of account "iCloud"
    end repeat
end tell
```

Gmail-backed accounts: `move` can silently no-op; use `duplicate ... to <mailbox>` then `delete` the original.

## Common mistakes

| Mistake | Fix |
|---|---|
| Searching mail by looping AppleScript `messages of` every mailbox | SQL against the Envelope Index, bridge by Message-ID |
| `whose id is <number>` | Overflows on negative 64-bit ids → `whose message id is "<rfc>"` (brackets stripped) |
| `reply theMsg with properties {…}` | Invalid — `reply … without opening window`, then set properties |
| Editing a saved draft in place | Impossible — create replacement, delete old |
| Reply draft in the wrong account | Set `sender of r` explicitly |
| `visible:true` + `delay` choreography | `without opening window` / `visible:false`; no delays needed |
| Opening the DB with `immutable=1` or copying it | Stale WAL / corruption risk — `?mode=ro` URI only |
| Expecting body text in the index | Bodies live in `.emlx` files — use `scripts/mail-body.py` |
| Reporting the SQL unread count as "your unread mail" | UI truth comes from AppleScript `unread count` |
