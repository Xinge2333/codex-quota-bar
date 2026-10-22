#!/usr/bin/env python3
"""Conservative local release scan. Prints rule names and paths, never matches."""
import argparse
import plistlib
import re
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
RULES = {
    'GitHub credential': rb'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}',
    'API credential': rb'sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}',
    'JWT credential': rb'eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}',
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'personal macOS path': rb'/Users/[A-Za-z0-9._-]+/|/private/var/folders/[A-Za-z0-9/]+',
    'pet account identifier': rb'pet_[a-f0-9]{24,}',
    'signed transport URL': rb'[?&](?:sig|X-Amz-Signature|X-Goog-Signature)=',
}
APP = '额度条.app/Contents/'
ALLOWED = {
    '使用说明.txt', 'INSTALL.en.txt', APP + 'Info.plist', APP + 'MacOS/MarbleQuotaBar',
    APP + '_CodeSignature/CodeResources',
}

def check_bytes(name, data):
    failures = []
    for rule, pattern in RULES.items():
        if re.search(pattern, data):
            failures.append(f'{name}: {rule}')
    return failures

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    failures = []
    files = {}
    for folder in ('Sources', 'Resources', 'scripts'):
        for path in (ROOT / folder).rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                failures += check_bytes(path.relative_to(ROOT).as_posix(), path.read_bytes())
    for filename in ('README.md', 'README.en.md', 'INSTALL.txt', 'INSTALL.en.txt', 'RELEASE_NOTES.md', 'SECURITY.md', 'CHECK_REPORT.md', 'CHECKS.json', '.gitignore'):
        path = ROOT / filename
        if path.exists(): failures += check_bytes(filename, path.read_bytes())
    source = (ROOT / 'Sources/main.swift').read_text()
    for forbidden in ('--verify-menubar', 'menu-bar-verification.json', 'URLSession', 'NSTask', '/bin/sh'):
        if forbidden in source: failures.append(f'Sources/main.swift: unexpected release capability {forbidden}')
    if args.stage:
        files = {p.relative_to(args.stage).as_posix(): p.read_bytes() for p in args.stage.rglob('*') if p.is_file()}
    if args.archive:
        with zipfile.ZipFile(args.archive) as archive:
            if archive.testzip() is not None: failures.append('ZIP integrity error')
            for info in archive.infolist():
                if info.extra or info.comment: failures.append('ZIP contains extended metadata')
            files = {name: archive.read(name) for name in archive.namelist()}
            binary = archive.getinfo(APP + 'MacOS/MarbleQuotaBar')
            if not (binary.external_attr >> 16) & 0o111: failures.append('ZIP lost executable permission')
    if files:
        if set(files) != ALLOWED: failures.append('Package file allowlist mismatch')
        for name, data in files.items(): failures += check_bytes(name, data)
        plist = plistlib.loads(files[APP + 'Info.plist'])
        if plist['LSMinimumSystemVersion'] != '13.0': failures.append('Unexpected deployment target')
        binary = files[APP + 'MacOS/MarbleQuotaBar']
        if not binary.startswith((b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf')):
            failures.append('Expected universal Mach-O')
    if failures:
        print('\n'.join(f'FAIL: {item}' for item in failures))
        return 1
    print(f'PASS: credential/path scan; release capability checks; {len(files)} package files checked')
    print('Scope: heuristic scan and explicit file allowlist; not a guarantee of absence of every secret.')
    return 0

if __name__ == '__main__': sys.exit(main())
