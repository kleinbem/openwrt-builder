#!/usr/bin/env bash
set -e

# Decrypt kleinbem-secrets/openwrt/firmware-files.yaml's `files: [{path,
# content}]` payload into a target directory for the ImageBuilder overlay.
# Relocated here from openwrt-secrets/decrypt.sh (cutover 2026-08-08) — this
# is build tooling, not secret storage, so it belongs with the consumer.
#
# Usage: ./decrypt-secrets.sh <sops_file> <target_dir>
SOPS_FILE="$1"
TARGET_DIR="$2"

if [ -z "$SOPS_FILE" ] || [ -z "$TARGET_DIR" ]; then
    echo "Usage: $0 <sops_file> <target_dir>"
    exit 1
fi

if [ ! -f "$SOPS_FILE" ]; then
    echo "Secrets file not found: $SOPS_FILE"
    exit 1
fi

echo "🔓 Decrypting secrets to $TARGET_DIR..."

# Decrypt to JSON stream and parse with Python (avoids extra dependencies)
sops -d --output-type json "$SOPS_FILE" | python3 -c "
import sys, json, os

target_dir = '$TARGET_DIR'
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f'❌ Error parsing JSON from sops: {exc}')
    sys.exit(1)

if not data or 'files' not in data:
    print('ℹ️  No files definition found in secrets.')
    sys.exit(0)

for item in data['files']:
    path = item.get('path')
    content = item.get('content')
    if not path or content is None:
        continue

    # Secure path check to prevent writing outside target_dir
    full_path = os.path.join(target_dir, path)
    if not os.path.abspath(full_path).startswith(os.path.abspath(target_dir)):
        print(f'⚠️  Skipping unsafe path: {path}')
        continue

    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, 'w') as f:
        f.write(content)
    print(f'-> 🔓 Wrote secret: {path}')
"

echo "✅ Secrets injected."
