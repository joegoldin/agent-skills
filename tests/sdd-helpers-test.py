#!/usr/bin/env python3
"""Exercise SDD artifacts in real Git and jj workspaces, without user config."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "skills/subagent-driven-development/scripts"


class HelpersTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        home = self.root / "home"
        home.mkdir()
        self.env = os.environ | {
            "HOME": str(home), "XDG_CONFIG_HOME": str(home),
            "JJ_CONFIG": str(home / "jj.toml"),
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
        }
        (home / "jj.toml").write_text('[user]\nname = "Test"\nemail = "test@example.invalid"\n')
        self.repo = self.root / "repo with spaces"
        self.repo.mkdir()

    def run_cmd(self, *args, cwd=None, check=True):
        return subprocess.run(args, cwd=cwd or self.repo, env=self.env,
                              text=True, capture_output=True, check=check)

    def helper(self, name, *args, cwd=None, check=True):
        return self.run_cmd(str(SCRIPTS / name), *args, cwd=cwd, check=check)

    def init_repo(self, vcs):
        if vcs == "git":
            self.run_cmd("git", "init", "-q")
        else:
            self.run_cmd("jj", "git", "init", "--" + vcs)
        (self.repo / "source.txt").write_text("before\n")
        if vcs == "git":
            self.run_cmd("git", "add", "source.txt")
            self.run_cmd("git", "commit", "-qm", "base")
            return self.run_cmd("git", "rev-parse", "HEAD").stdout.strip()
        self.run_cmd("jj", "commit", "-m", "base")
        return self.run_cmd("jj", "log", "--no-graph", "-r", "@-", "-T", "commit_id").stdout.strip()

    def check_workspace(self, repo):
        nested = repo / "nested"
        nested.mkdir()
        result = self.helper("sdd-workspace", cwd=nested)
        self.assertEqual(result.stdout.strip(), str(repo / ".agent-skills/sdd"))
        plan = self.root / "plan.md"
        plan.write_text("# Task 1: First\nKeep exact values.\n# Task 2: Next\nNot this.\n")
        self.helper("task-brief", str(plan), "1", cwd=nested)
        brief = repo / ".agent-skills/sdd/task-1-brief.md"
        self.assertEqual(brief.read_text(), "# Task 1: First\nKeep exact values.\n")
        self.assertEqual((brief.parent / ".gitignore").read_text(), "*\n")

    def test_git_workspace(self):
        self.init_repo("git")
        self.check_workspace(self.repo)
        self.assertNotIn(".agent-skills", self.run_cmd("git", "status", "--porcelain").stdout)

    def test_git_linked_worktree(self):
        self.init_repo("git")
        linked = self.root / "linked"
        self.run_cmd("git", "worktree", "add", "-b", "task", str(linked))
        self.check_workspace(linked)

    def test_jj_non_colocated_workspace(self):
        self.init_repo("no-colocate")
        self.check_workspace(self.repo)
        self.assertNotIn(".agent-skills", self.run_cmd("jj", "status").stdout)

    def test_jj_secondary_workspace(self):
        self.init_repo("colocate")
        linked = self.root / "linked"
        self.run_cmd("jj", "workspace", "add", str(linked))
        self.check_workspace(linked)
        self.assertFalse((linked / ".git").exists())

    def check_review(self, vcs):
        base = self.init_repo(vcs)
        (self.repo / "source.txt").write_text("after\n")
        if vcs == "git":
            self.run_cmd("git", "commit", "-qam", "change")
            head = "HEAD"
        else:
            head = "@"
        out = self.root / "review.diff"
        self.helper("review-package", base, head, str(out))
        text = out.read_text()
        self.assertIn("-before", text)
        self.assertIn("+after", text)
        self.assertIn("## Commits", text)
        self.assertIn("## Files changed", text)
        self.assertNotIn(".agent-skills", text)

    def test_git_review(self):
        self.check_review("git")

    def test_jj_review(self):
        self.check_review("no-colocate")

    def test_jj_colocated_review_uses_working_copy(self):
        self.check_review("colocate")

    def test_jj_secondary_review(self):
        base = self.init_repo("colocate")
        linked = self.root / "linked"
        self.run_cmd("jj", "workspace", "add", str(linked))
        (linked / "new.txt").write_text("secondary change\n")
        out = self.root / "review.diff"
        self.helper("review-package", base, "@", str(out), cwd=linked)
        self.assertIn("+secondary change", out.read_text())

    def test_default_jj_package_records_resolved_ids(self):
        base = self.init_repo("no-colocate")
        (self.repo / "source.txt").write_text("after\n")
        self.helper("review-package", base, "@")
        packages = list((self.repo / ".agent-skills/sdd").glob("review-*.diff"))
        self.assertEqual(len(packages), 1)
        self.assertIn("+after", packages[0].read_text())
        self.assertNotIn("..@", packages[0].read_text())
        self.assertNotIn(".agent-skills", self.run_cmd("jj", "status").stdout)

    def test_jj_multi_revision_is_rejected(self):
        self.init_repo("no-colocate")
        out = self.root / "review.diff"
        out.write_text("keep\n")
        result = self.helper("review-package", "all()", "@", str(out), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(out.read_text(), "keep\n")

    def test_nested_git_repo_does_not_use_outer_jj(self):
        self.init_repo("no-colocate")
        nested = self.repo / "inner"
        nested.mkdir()
        self.run_cmd("git", "init", "-q", cwd=nested)
        self.check_workspace(nested)

    def test_bad_revision_does_not_overwrite_output(self):
        base = self.init_repo("git")
        out = self.root / "review.diff"
        out.write_text("keep\n")
        result = self.helper("review-package", base, "missing", str(out), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(out.read_text(), "keep\n")

    def test_outside_repository_fails_without_artifacts(self):
        result = self.helper("sdd-workspace", cwd=self.root, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / ".agent-skills").exists())


if __name__ == "__main__":
    unittest.main()
