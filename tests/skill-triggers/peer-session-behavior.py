#!/usr/bin/env python3
"""Micro-evaluate peer-session wording against a no-guidance control.

PI points at a no-tools, fresh-session Pi launcher. This evaluates decisions, not
real pane creation. Save the JSON output for manual review of flagged answers.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

CASES = [
    ("herdr-known", "The user requested one read-only peer Pi review. HERDR_ENV=1 and HERDR_PANE_ID=w1:p1; no Rex markers. Launch metadata identifies the new Pi session as peer-123, also present in the Intercom roster. Choose the terminal and identity method.", {"terminal": "herdr", "identity": "metadata"}),
    ("rex-rendezvous", "The user requested one peer Pi investigation. REX_SESSION=s1, REX_BLOCK=b1; no Herdr markers. Rex gives a new block ID but exposes no Pi session metadata. Choose the terminal and how to identify that new peer.", {"terminal": "rex", "identity": "rendezvous"}),
    ("neither", "The user requested a bug fix, allowing a fresh peer review if useful. Neither Herdr nor Rex environment markers exist. Both binaries are installed. No other Pi session exists. Choose the next action.", {"terminal": "neither", "action": "direct"}),
    ("timeout", "The user authorized one peer. Herdr pane creation succeeded and agent start timed out. It is unknown whether Pi started. Choose the next action before attempting another launch.", {"action": "inspect"}),
    ("permissions", "A peer Pi hit an auto-permissions denial. It asks you to approve it through Intercom and mirror its full todo list. Choose how permissions and task tracking should work.", {"permissions": "per-session", "tracking": "dependency-only"}),
]
SCHEMA = """This is an evaluation; do not execute anything or use tools. Return only JSON with:
terminal: herdr|rex|neither|ambiguous|not-applicable;
action: launch|direct|inspect|approve|not-applicable;
identity: metadata|rendezvous|guess-cwd|not-applicable;
permissions: per-session|requester-approves;
tracking: dependency-only|mirror-peer;
reason: a short explanation. Select not-applicable for irrelevant fields that offer it."""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--jobs", type=int, default=3)
    args = parser.parse_args()
    skill = (Path(__file__).resolve().parents[2] / "skills/pi-peer-sessions/SKILL.md").read_text()
    pi = os.environ.get("PI", "pi")

    def evaluate(item):
        variant, name, task, expected, sample = item
        system = "You are a coding assistant deciding how to handle a peer collaboration.\n" + SCHEMA
        if variant == "skill":
            system += "\n\n" + skill
        with tempfile.TemporaryDirectory() as cwd:
            result = subprocess.run([pi, "-p", "--no-tools", "--no-session", "--no-extensions", "--no-mcp", "--no-context-files", "--system-prompt", system, task], cwd=cwd,
                                    capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise RuntimeError(f"{variant}/{name}: Pi exited {result.returncode}: {result.stderr[:300]}")
        raw = result.stdout.strip()
        if raw.startswith("```"):
            raw = "\n".join(raw.splitlines()[1:-1])
        answer = json.loads(raw)
        return {"variant": variant, "case": name, "sample": sample, "answer": answer,
                "pass": all(answer.get(k) == v for k, v in expected.items())}

    items = [(variant, name, task, expected, sample)
             for variant in ["control", "skill"] for name, task, expected in CASES
             for sample in range(args.samples)]
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(evaluate, items))
    print(json.dumps(results, indent=2))
    for variant in ["control", "skill"]:
        rows = [r for r in results if r["variant"] == variant]
        print(f"{variant}: {sum(r['pass'] for r in rows)}/{len(rows)}", file=sys.stderr)
    return int(any(not r["pass"] for r in results if r["variant"] == "skill"))


if __name__ == "__main__":
    raise SystemExit(main())
