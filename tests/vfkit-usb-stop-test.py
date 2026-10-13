#!/usr/bin/env python3
"""A failed REST request must not leave a LaunchServices VM running."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

WRAPPER = Path(__file__).resolve().parents[1] / 'packages/re-shell/vfkit-usb.sh'


class StopTests(unittest.TestCase):
    def test_stop_before_rest_socket_is_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / 'vfkit.app'
            app.mkdir()
            opener = root / 'open'
            opener.write_text('#!' + sys.executable + '''
import os, subprocess, sys
from pathlib import Path
app = sys.argv[sys.argv.index('-a') + 1]
args = sys.argv[sys.argv.index('--args') + 1:]
p = subprocess.Popen([app + '/Contents/MacOS/vfkit', '-c', 'import time; time.sleep(600)', *args], executable=sys.executable)
Path(os.environ['TEST_PID']).write_text(str(p.pid))
sys.exit(p.wait())
''')
            opener.chmod(0o755)
            wrapper = root / 'wrapper'
            wrapper.write_text(WRAPPER.read_text().replace('/usr/bin/open', str(opener))
                               .replace('/usr/bin/curl', shutil.which('false'))
                               .replace('/bin/ps', shutil.which('ps') or '/bin/ps')
                               .replace('console=$(tty)', 'console=/dev/null'))
            env = dict(os.environ, RE_SHELL_VFKIT_APP=str(app), TEST_PID=str(root / 'pid'))
            process = subprocess.Popen(['bash', str(wrapper), '--restful-uri', 'unix:///tmp/re-stop-test.sock'], env=env)
            unrelated = subprocess.Popen([str(app / 'Contents/MacOS/vfkit'), '-c',
                                          'import time; time.sleep(600)', '--restful-uri',
                                          'unix:///tmp/re-other-session.sock'], executable=sys.executable)
            child = None
            try:
                deadline = time.monotonic() + 5
                while not (root / 'pid').exists() and time.monotonic() < deadline:
                    time.sleep(.05)
                child = int((root / 'pid').read_text())
                process.send_signal(signal.SIGTERM)
                try:
                    code = process.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    self.fail('wrapper waited indefinitely after REST shutdown failed')
                self.assertEqual(code, 143)
                self.assertIsNone(unrelated.poll(), 'stopped an unrelated vfkit session')
                with self.assertRaises(ProcessLookupError):
                    os.kill(child, 0)
            finally:
                unrelated.kill()
                unrelated.wait()
                if child:
                    try:
                        os.kill(child, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                if process.poll() is None:
                    process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
