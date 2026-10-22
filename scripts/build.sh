#!/bin/bash
set -euo pipefail
quota_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$quota_root"
quota_build="$(mktemp -d "${TMPDIR:-/tmp}/quota-build.XXXXXX")"
trap 'rm -rf "$quota_build"' EXIT
mkdir -p dist "$quota_build/stage/额度条.app/Contents/MacOS"
quota_sdk="$(xcrun --sdk macosx --show-sdk-path)"
for quota_arch in arm64 x86_64; do
    swiftc -O -whole-module-optimization -module-name CodexQuotaBar \
        -module-cache-path "$quota_build/cache-$quota_arch" \
        -sdk "$quota_sdk" -target "$quota_arch-apple-macos13.0" \
        Sources/main.swift -o "$quota_build/$quota_arch"
done
lipo -create "$quota_build/arm64" "$quota_build/x86_64" \
    -output "$quota_build/stage/额度条.app/Contents/MacOS/MarbleQuotaBar"
strip -x "$quota_build/stage/额度条.app/Contents/MacOS/MarbleQuotaBar"
cp Resources/Info.plist "$quota_build/stage/额度条.app/Contents/Info.plist"
cp INSTALL.txt "$quota_build/stage/使用说明.txt"
cp INSTALL.en.txt "$quota_build/stage/INSTALL.en.txt"
plutil -lint "$quota_build/stage/额度条.app/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign - "$quota_build/stage/额度条.app"
codesign --verify --deep --strict "$quota_build/stage/额度条.app"
quota_binary="$quota_build/stage/额度条.app/Contents/MacOS/MarbleQuotaBar"
"$quota_binary" --self-test
python3 scripts/audit.py --stage "$quota_build/stage"
python3 - "$quota_build/stage" "$quota_root/dist" <<'PY'
from pathlib import Path
import hashlib, sys, zipfile
stage, dist = map(Path, sys.argv[1:])
archive = dist / 'CodexQuotaBar-v1.2.0-macos-universal.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in sorted(stage.rglob('*')):
        if path.is_file():
            info = zipfile.ZipInfo(path.relative_to(stage).as_posix())
            info.create_system = 3
            info.external_attr = (0o100755 if path.name == 'MarbleQuotaBar' else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, path.read_bytes())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(dist / 'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')
print(f'Created {archive.name}; SHA256 {digest}')
PY
python3 scripts/audit.py --archive dist/CodexQuotaBar-v1.2.0-macos-universal.zip
printf 'Universal architectures: '
lipo -archs "$quota_binary"
