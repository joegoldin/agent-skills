#!/usr/bin/env python3
"""Prompt construction tests; the model process is the external boundary."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("skill_triggers", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ExplicitSkillTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        self.skills = Path(self.home.name) / ".agents" / "skills"
        self.write_skill("manual-release", "Publish the requested dependency safely.")
        self.write_skill("another-command", "OTHER_HIDDEN_DESCRIPTION")
        self.env = os.environ | {"HOME": self.home.name}

    def write_skill(self, name, description):
        folder = self.skills / name
        folder.mkdir(parents=True)
        (folder / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: {description}\n"
            "disable-model-invocation: true\n---\nBODY_MUST_NOT_BE_LOADED\n"
        )

    def question(self, task):
        result = subprocess.CompletedProcess([], 0, stdout="none\n", stderr="")
        with patch.object(runner.subprocess, "run", return_value=result) as child:
            self.assertEqual(runner.ask("pi", task, 10, self.env), [])
        return child.call_args.args[0][-1]

    def test_explicit_manual_command_supplies_its_description_to_the_model(self):
        question = self.question("/manual-release dependency: publish it")
        self.assertIn("Publish the requested dependency safely.", question)
        self.assertNotIn("OTHER_HIDDEN_DESCRIPTION", question)
        self.assertNotIn("BODY_MUST_NOT_BE_LOADED", question)

    def test_automatic_selection_does_not_expose_manual_commands(self):
        question = self.question("Publish a dependency safely.")
        self.assertNotIn("Publish the requested dependency safely.", question)
        self.assertNotIn("OTHER_HIDDEN_DESCRIPTION", question)

    def test_unknown_or_embedded_command_does_not_supply_hidden_metadata(self):
        for task in ("/unknown dependency", "Explain /manual-release", "/../manual-release"):
            with self.subTest(task=task):
                self.assertNotIn("Publish the requested dependency safely.", self.question(task))

    def test_failed_model_process_is_not_a_successful_empty_selection(self):
        # Python rejects Pi's -p flag, exercising a real child-process failure.
        with self.assertRaises(subprocess.CalledProcessError):
            runner.ask(sys.executable, "Explain a function.", 10, self.env)

    def test_pi_skill_command_syntax_supplies_only_requested_metadata(self):
        question = self.question("/skill:manual-release dependency")
        self.assertIn("Publish the requested dependency safely.", question)
        self.assertNotIn("OTHER_HIDDEN_DESCRIPTION", question)


if __name__ == "__main__":
    unittest.main()
