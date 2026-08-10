#!/usr/bin/env python3
"""Print Apple Mail message bodies as JSON, given Envelope Index ROWIDs.

Usage: python3 mail-body.py <rowid> [rowid ...]
Output: JSON array of {rowid, path, subject, from, date, body, attachments, partial}

Locates <rowid>.emlx (or <rowid>.partial.emlx) under ~/Library/Mail/V*/ and
parses it with the stdlib email package. Read-only; never touches the SQLite DB.
"""
import email
import email.policy
import glob
import json
import os
import re
import sys


def find_emlx(rowid):
    roots = sorted(glob.glob(os.path.expanduser("~/Library/Mail/V*")))
    for root in reversed(roots):  # highest V version first
        for suffix in (f"{rowid}.emlx", f"{rowid}.partial.emlx"):
            for dirpath, _dirnames, filenames in os.walk(root):
                if suffix in filenames:
                    return os.path.join(dirpath, suffix)
    return None


def clean_html(text):
    text = re.sub(r"<(style|script)[^>]*>.*?</\1>", " ", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&lt;", "<", text)
    text = re.sub(r"&gt;", ">", text)
    text = re.sub(r"&#\d+;|&[a-z]+;", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def parse_emlx(path):
    with open(path, "rb") as fh:
        fh.readline()  # first line is an emlx byte count, not part of the RFC 822 message
        msg = email.message_from_bytes(fh.read(), policy=email.policy.default)
    body, attachments = "", []
    for part in msg.walk():
        if part.get_filename():
            attachments.append(part.get_filename())
            continue
        ctype = part.get_content_type()
        if ctype in ("text/plain", "text/html") and "attachment" not in str(part.get("Content-Disposition", "")):
            payload = part.get_payload(decode=True)
            if not payload:
                continue
            text = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
            if ctype == "text/html":
                text = clean_html(text)
            if len(text) > len(body):  # prefer the richest text part
                body = text
    return msg, body.strip(), attachments


def main():
    results = []
    for rowid in sys.argv[1:]:
        path = find_emlx(rowid)
        if not path:
            results.append({"rowid": rowid, "path": None, "body": "[not cached locally — Mail has not downloaded this message]"})
            continue
        msg, body, attachments = parse_emlx(path)
        results.append({
            "rowid": rowid,
            "path": path,
            "subject": str(msg.get("Subject", "")),
            "from": str(msg.get("From", "")),
            "date": str(msg.get("Date", "")),
            "body": body[:8000],
            "attachments": attachments,
            "partial": path.endswith(".partial.emlx"),
        })
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
