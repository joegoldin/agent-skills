#!/usr/bin/env python3
import subprocess
import sys
import tempfile
import time
from pathlib import Path


with tempfile.TemporaryDirectory() as scratch:
    root = Path(scratch)
    checklist = root / '.pi/todo/upgrade.test/checklist.md'
    checklist.parent.mkdir(parents=True)
    runbook = root / 'docs/staging notes.md'
    runbook.parent.mkdir()
    runbook.write_text('# Staging runbook\n\nConfirm the deployment.\n')
    checklist.write_text(
        '# Upgrade staging\n\n'
        '- [ ] Run smoke tests\n'
        '- [/] Deploy upgrade ([runbook](../../../docs/staging%20notes.md))\n'
        '- [x] Check prerequisites\n'
    )
    socket = root / 'tmux.sock'

    def tmux(*args, check=True):
        return subprocess.run(
            ['tmux', '-u', '-f', '/dev/null', '-S', str(socket), *args],
            cwd=root, capture_output=True, encoding='utf-8', check=check,
        )

    def screen(*expected):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            view = tmux('capture-pane', '-p').stdout
            if all(text in view for text in expected):
                return view
            time.sleep(0.05)
        raise AssertionError(f'{expected!r} not visible:\n{view}')

    def send(*keys):
        tmux('send-keys', *keys)

    try:
        tmux('new-session', '-d', '-x', '50', '-y', '18', sys.argv[1], str(checklist))
        view = screen('□', '◩', '✓', 'runbook', 'SPC State', '^S Save', 'q Quit')
        assert 'Deploy upgrade (runbook)' in view, view
        assert 'staging%20notes.md' not in view, view
        print(view.rstrip())

        send('3', 'G', 'Space')
        screen('◩ Run smoke tests')
        send('Space', 'C-s')
        screen('✓ Run smoke tests')
        assert '- [x] Run smoke tests' in checklist.read_text()

        send('0', 'e')
        screen('Esc Preview')
        send(' ', 'C-s')
        screen('SPC State')
        assert '\n - [x] Run smoke tests\n' in checklist.read_text()

        updated = checklist.with_suffix('.new')
        updated.write_text(checklist.read_text().replace('[/] Deploy', '[x] Deploy'))
        updated.replace(checklist)
        screen('✓ Deploy upgrade')

        send('4', 'G', '0', 'Enter')
        screen('Staging runbook', 'Confirm the deployment.')
        send('q')
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and tmux('has-session', check=False).returncode == 0:
            time.sleep(0.05)
        assert tmux('has-session', check=False).returncode != 0, 'q did not quit'
        print('Verified rendering, status cycling, editing, saving, external reload, relative links, and quit.')
    finally:
        tmux('kill-server', check=False)
