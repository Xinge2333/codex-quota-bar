#!/usr/bin/env python3
"""Verify an npm-style /usr/bin/env node launcher in a path containing spaces."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary, node = (Path(value).resolve() for value in sys.argv[1:3])
with tempfile.TemporaryDirectory(prefix='quota-launcher-') as temporary:
    root = Path(temporary)
    directory = root / 'node version with spaces' / 'bin'
    directory.mkdir(parents=True)
    (directory / 'node').symlink_to(node)
    launcher = directory / 'codex'
    launcher.write_text('''#!/usr/bin/env node
const readline = require('node:readline');
readline.createInterface({input: process.stdin}).on('line', line => {
  const request = JSON.parse(line);
  if (request.method === 'initialize') {
    console.log(JSON.stringify({id: request.id, result: {}}));
  } else if (request.method === 'account/rateLimits/read') {
    console.log(JSON.stringify({id: request.id, result: {rateLimits: {
      primary: {usedPercent: 10, windowDurationMins: 300},
      secondary: {usedPercent: 40, windowDurationMins: 10080}
    }}}));
  }
});
''')
    launcher.chmod(0o700)
    environment = os.environ.copy()
    environment.update(HOME=str(root), CODEX_HOME=str(root / 'empty-home'), MARBLE_CODEX_PATH=str(launcher), PATH='/usr/bin:/bin')
    result = subprocess.run([str(binary), '--check-connection'], env=environment, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
    assert result.returncode == 0 and 'CONNECTED primary=true weekly=true' in result.stdout, 'npm-style launcher failed'
    print('PASS: npm-style Node launcher, missing Node in parent PATH, selected CLI path with spaces')
