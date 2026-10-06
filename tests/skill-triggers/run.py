#!/usr/bin/env python3
"""Which skills does a model pick for a task, given the descriptions it sees?

Descriptions decide which skills load, so rewording one can quietly stop a
skill loading where it should, or start it loading everywhere. This asks a
real pi session, with its real skill listing, which skills it would load for
each task in cases.json, without doing the task, and checks the answer
against what each case expects and forbids.

It needs a live model, so it is a script rather than a Nix check. Point PI at
the build under test:

    PI=$(nix build --no-link --print-out-paths .#...)/bin/pi tests/skill-triggers/run.py
    tests/skill-triggers/run.py --save baseline.json   # snapshot
    tests/skill-triggers/run.py --compare baseline.json

pi reads skills from ~/.agents/skills, which follows the active home-manager
generation, so a build's own skills are only seen with --skills pointing at
its home-files (.agents/skills inside the home-files output).

Exit status is non-zero when any case misses an expected skill or picks a
forbidden one.
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent

QUESTION = """You are being asked about skill selection only. Do not perform the task below, do not call any tools, and do not read any files.

Task a user just gave you:
<task>
{task}
</task>

Using only the names and descriptions of the skills available to you, which skills would you load before starting this task? Reply with one line: the skill names separated by commas, or the word none."""


def ask(pi: str, task: str, timeout: int, env: dict[str, str] | None) -> list[str]:
    # An empty directory, so no project context files leak into the choice.
    with tempfile.TemporaryDirectory() as cwd:
        out = subprocess.run(
            [pi, "-p", QUESTION.format(task=task)],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            stdin=subprocess.DEVNULL,
        )
    lines = [l for l in out.stdout.strip().splitlines() if l.strip() and not l.startswith("Warning:")]
    answer = lines[-1] if lines else ""
    if answer.strip().lower() in {"none", "none."}:
        return []
    return sorted({s.strip().strip("`.") for s in re.split(r"[,\n]", answer) if s.strip()})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cases", default=str(HERE / "cases.json"))
    parser.add_argument("--save", help="write the picks to this JSON file")
    parser.add_argument("--compare", help="show where picks differ from a saved run")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--skills", help="skills directory to list instead of ~/.agents/skills")
    args = parser.parse_args()

    pi = os.environ.get("PI", "pi")
    cases = json.loads(Path(args.cases).read_text())
    with tempfile.TemporaryDirectory() as home:
        env = None
        if args.skills:
            # A stand-in HOME: the real ~/.pi for login and settings, linked
            # rather than copied, and the skills under test.
            (Path(home) / ".agents").mkdir()
            (Path(home) / ".agents" / "skills").symlink_to(Path(args.skills).resolve())
            (Path(home) / ".pi").symlink_to(Path.home() / ".pi")
            env = os.environ | {"HOME": home}
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            picks = list(pool.map(lambda c: ask(pi, c["task"], args.timeout, env), cases))

    previous = json.loads(Path(args.compare).read_text()) if args.compare else {}
    failures = 0
    for case, picked in zip(cases, picks):
        missing = [s for s in case["expect"] if s not in picked]
        forbidden = [s for s in case["forbid"] if s in picked]
        ok = not missing and not forbidden
        failures += not ok
        line = f"{'ok  ' if ok else 'FAIL'} {case['task'][:70]:<70}  -> {', '.join(picked) or 'none'}"
        if missing:
            line += f"  [missing: {', '.join(missing)}]"
        if forbidden:
            line += f"  [forbidden: {', '.join(forbidden)}]"
        before = previous.get(case["task"])
        if before is not None and before != picked:
            line += f"  (was: {', '.join(before) or 'none'})"
        print(line)

    if args.save:
        Path(args.save).write_text(json.dumps({c["task"]: p for c, p in zip(cases, picks)}, indent=2) + "\n")
    print(f"\n{len(cases) - failures}/{len(cases)} cases pass")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
