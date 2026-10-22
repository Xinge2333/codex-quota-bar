#!/usr/bin/env python3
"""Offline protocol checks using synthetic helper processes, never a real account."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HELPER = r'''
import json, os, sys
scenario = SCENARIO
for line in sys.stdin:
    request = json.loads(line)
    method = request.get('method')
    with open(RECORD, 'a') as stream: stream.write(method + '\n')
    assert method in ('initialize', 'initialized', 'account/rateLimits/read')
    assert not any(key in os.environ for key in ('GH_TOKEN', 'OPENAI_API_KEY', 'UNRELATED_SECRET'))
    if method == 'initialize':
        print(json.dumps({'id': request['id'], 'result': {}}), flush=True)
    elif method == 'account/rateLimits/read':
        identifier = request['id']
        if scenario == 'closed': sys.exit(0)
        if scenario == 'timeout': continue
        if scenario == 'oversized':
            sys.stdout.write('x' * 1100000 + '\n'); sys.stdout.flush(); continue
        if scenario == 'not_logged_in':
            response = {'id': identifier, 'error': {'code': -32001, 'message': 'synthetic auth failure'}}
        elif scenario == 'unsupported':
            response = {'id': identifier, 'error': {'code': -32601, 'message': 'synthetic old interface'}}
        elif scenario == 'missing_data':
            response = {'id': identifier, 'result': {'rateLimits': None}}
        else:
            bucket = {'primary': {'usedPercent': 20, 'windowDurationMins': 300, 'resetsAt': 1577947920}}
            if scenario != 'one_window': bucket['secondary'] = {'usedPercent': 50, 'windowDurationMins': 10080, 'resetsAt': 1578556800}
            result = {'rateLimitsByLimitId': {'codex': bucket}}
            if scenario != 'no_credits':
                result['rateLimitResetCredits'] = {'availableCount': 1, 'credits': [{'resetType': 'codexRateLimits', 'status': 'available', 'title': 'Full reset (Weekly + 5 hr)'}]}
            response = {'id': identifier, 'result': result}
        print(json.dumps(response), flush=True)
'''

def main():
    binary = Path(sys.argv[1]).resolve()
    assert binary.is_file(), 'Pass the compiled application binary path'
    with tempfile.TemporaryDirectory(prefix='quota-protocol-') as temporary:
        root = Path(temporary)
        for case in ('success', 'one_window', 'no_credits', 'not_logged_in', 'unsupported', 'missing_data', 'oversized', 'closed', 'timeout', 'missing_cli'):
            record = root / f'{case}.methods'
            helper = root / f'{case}.helper'
            helper.write_text(f'#!{sys.executable}\n' + f'SCENARIO={case!r}\nRECORD={str(record)!r}\n' + HELPER)
            helper.chmod(0o700)
            environment = os.environ.copy()
            environment.update(HOME=str(root), CODEX_HOME=str(root / 'empty-codex-home'),
                MARBLE_CODEX_PATH=str(root / 'missing') if case == 'missing_cli' else str(helper),
                GH_TOKEN='synthetic-sentinel', OPENAI_API_KEY='synthetic-sentinel', UNRELATED_SECRET='synthetic-sentinel')
            result = subprocess.run([str(binary), '--check-connection'], env=environment, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
            expected = 0 if case in ('success', 'one_window', 'no_credits') else 1
            assert result.returncode == expected, f'{case}: unexpected exit {result.returncode}'
            assert 'synthetic-sentinel' not in result.stdout + result.stderr
            assert '1577947920' not in result.stdout + result.stderr
            if expected == 0:
                assert 'CONNECTED primary=true' in result.stdout
                assert f'weekly={"false" if case == "one_window" else "true"}' in result.stdout
            if case == 'unsupported': assert 'Update Codex CLI' in result.stdout
            if record.exists():
                assert record.read_text().splitlines()[:3] == ['initialize', 'initialized', 'account/rateLimits/read']
            print(f'PASS: {case}', flush=True)
    print('PASS: offline compatibility matrix; no account credentials or network used')

if __name__ == '__main__': main()
