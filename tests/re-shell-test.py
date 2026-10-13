#!/usr/bin/env python3
"""Exercise launcher option routing and cached VM selection without a VM."""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

LAUNCHER = Path(__file__).resolve().parents[1] / 'packages/re-shell/re-shell.sh'


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        RE_SHELL_STATE_DIR=str(self.root / 'state'),
                        RE_SHELL_VFKIT_APP=str(self.root / 'vfkit.app'),
                        TEST_LOG=str(self.root / 'calls'), TEST_OS='Darwin')
        self.script('uname', 'if [ "$1" = -s ]; then echo "$TEST_OS"; else echo arm64; fi')
        self.script('sw_vers', 'echo 27.0.1')
        self.script('codesign', 'exit 0')
        self.script('script', 'shift 2; exec "$@"')
        self.script('nix', '''printf '%s\\n' "$*" >> "$TEST_LOG"
if [ "$1" = build ]; then
  while [ "$1" != --out-link ]; do shift; done
  shift; dest=$1
  mkdir -p "$dest/bin"
  cat > "$dest/bin/microvm-run" <<'SH'
#!/usr/bin/env bash
printf 'ran %s\\n' "$0" >> "$TEST_LOG"
ctl=$(dirname "$(dirname "$(dirname "$0")")")
echo 0 > "$ctl/status"
SH
  chmod +x "$dest/bin/microvm-run"
fi''')
        app = self.root / 'vfkit.app/Contents/MacOS/vfkit'
        app.parent.mkdir(parents=True)
        app.write_text('#!/bin/sh\nexit 0\n')
        app.chmod(0o755)

    def script(self, name, text):
        p = self.bin / name
        p.write_text(('#!/usr/bin/env bash\nset -eu\n' + text + '\n').replace(
            '#!/usr/bin/env bash', '#!' + shutil.which('bash')))
        p.chmod(0o755)

    def run_launcher(self, *args):
        return subprocess.run(['bash', str(LAUNCHER), *args], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_usb_uses_separate_cache_and_enables_vm_option(self):
        for args in [(), ('--usb',), ('--usb',)]:
            result = self.run_launcher(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.root / 'calls').read_text()
        self.assertEqual(calls.count('build '), 2, calls)
        self.assertIn('/runner-usb/bin/microvm-run', calls)
        expression = next((self.root / 'state/sessions').glob('*/vm.nix')).read_text()
        self.assertIn('usbPassthrough = true;', expression)

    def test_usb_rejects_linux_before_nix(self):
        self.env['TEST_OS'] = 'Linux'
        result = self.run_launcher('--usb')
        self.assertEqual(result.returncode, 2)
        self.assertIn('--usb requires macOS', result.stderr)
        self.assertFalse((self.root / 'calls').exists())

    def test_missing_app_explains_setup(self):
        self.env['RE_SHELL_VFKIT_APP'] = str(self.root / 'missing.app')
        result = self.run_launcher('--usb')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('activate your vfkit dotfiles configuration', result.stderr)
        self.assertFalse((self.root / 'calls').exists())

    def test_linux_command_arguments_unchanged(self):
        self.env['TEST_OS'] = 'Linux'
        result = self.run_launcher('-f', 'example:flake', '--', 'echo', 'two words')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('develop example:flake#re-shell --command echo two words',
                      (self.root / 'calls').read_text())


if __name__ == '__main__':
    unittest.main()
