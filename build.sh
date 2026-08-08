#!/usr/bin/env bash
set -euo pipefail

# Usage: ./build.sh <profile_name>
PROFILE_NAME="${1:-}"

if [ -z "$PROFILE_NAME" ]; then
    echo "Usage: $0 <profile_name>"
    echo "Available profiles:"
    find profiles -name '*.conf' -printf '%f\n' | sed 's/\.conf$//'
    exit 1
fi

PROFILE_CONFIG="profiles/${PROFILE_NAME}.conf"

if [ ! -f "$PROFILE_CONFIG" ]; then
    echo "❌ Error: Profile '$PROFILE_NAME' not found in profiles/ directory."
    exit 1
fi

# --- 1. LOAD PROFILE ---
echo "🔧 Loading Profile: $PROFILE_NAME"
# shellcheck disable=SC1090 # profile chosen at runtime
source "$PROFILE_CONFIG"

# Check required variables — the sha256 pin is mandatory so a compromised
# or silently-changed download mirror can't reach the build.
if [ -z "${BUILDER_URL:-}" ] || [ -z "${BOARD:-}" ] || [ -z "${BUILDER_SHA256:-}" ]; then
    echo "❌ Error: Profile must define BUILDER_URL, BUILDER_SHA256 and BOARD."
    exit 1
fi

BUILDER_FILE="builder-${PROFILE_NAME}.tar.zst"
BUILDER_DIR_NAME="openwrt-imagebuilder-${PROFILE_NAME}"

# --- 2. PREPARE BUILDER ---
echo "[1/5] Checking for Image Builder..."
if [ ! -d "$BUILDER_DIR_NAME" ]; then
    echo "    Downloading specific builder..."
    wget -O "$BUILDER_FILE" "$BUILDER_URL"

    echo "    Verifying checksum..."
    echo "${BUILDER_SHA256}  ${BUILDER_FILE}" | sha256sum -c -

    echo "    Extracting..."
    mkdir -p "$BUILDER_DIR_NAME"
    tar -xf "$BUILDER_FILE" --strip-components=1 -C "$BUILDER_DIR_NAME"
    rm "$BUILDER_FILE"
fi

# Optimization: Use global package cache if mounted
if [ -d "/workspace/dl" ]; then
    echo "📦 Using persistent package cache..."
    rm -rf "$BUILDER_DIR_NAME/dl"
    ln -s /workspace/dl "$BUILDER_DIR_NAME/dl"
fi

cd "$BUILDER_DIR_NAME"

# --- 2.5 PREPARE SECRETS ---
# kleinbem-secrets (cutover 2026-08-08, replaces openwrt-secrets). This
# fallback only matters for a bare-metal (non-container) run of build.sh —
# the containerized `just build` path always sets EXTERNAL_SECRETS_DIR and
# doesn't mount kleinbem-secrets into the container at all.
SECRETS_FILE="../../kleinbem-secrets/openwrt/firmware-files.yaml"
DECRYPT_SCRIPT="../scripts/decrypt-secrets.sh"
SECRETS_SOURCE=""

if [ -n "${EXTERNAL_SECRETS_DIR:-}" ] && [ -d "${EXTERNAL_SECRETS_DIR:-}" ]; then
    echo "🔐 Using external secrets from environment: $EXTERNAL_SECRETS_DIR"
    SECRETS_SOURCE="$EXTERNAL_SECRETS_DIR"
elif [ -f "$SECRETS_FILE" ] && [ -f "$DECRYPT_SCRIPT" ]; then
    echo "🔐 Secrets file found. Decrypting to a temp dir, merged below..."

    SECRET_TMP=$(mktemp -d)
    trap 'rm -rf "$SECRET_TMP"' EXIT

    "$DECRYPT_SCRIPT" "$SECRETS_FILE" "$SECRET_TMP"

    # Check if we have files to merge
    if [ -n "$(ls -A "$SECRET_TMP")" ]; then
         echo "    Merging secrets into build..."
         SECRETS_SOURCE="$SECRET_TMP"
    else
         echo "    (No secrets decrypted)"
    fi
fi

# --- 3. PREPARE FILES ---
echo "[2/5] Merging Files..."
# Create a temporary 'files' folder inside the builder
rm -rf files_overlay
mkdir -p files_overlay

# Layer 1: Common files (SSH keys, etc.)
if [ -d "../files/common" ]; then
    cp -r ../files/common/* files_overlay/
fi

# Layer 2: Board specific files (uEnv.txt, etc.)
if [ -d "../files/${PROFILE_NAME}" ]; then
    cp -r ../files/"${PROFILE_NAME}"/* files_overlay/
fi

# Layer 3: Secrets (Highest Priority - Overwrites defaults)
# Skip cleanly when the source is empty — public/CI builds mount an empty
# secrets dir (no kleinbem-secrets checkout), and under `set -e` a glob that
# matches nothing would abort the whole build. `/.` copies contents incl.
# dotfiles without relying on the shell glob.
if [ -n "$SECRETS_SOURCE" ] && [ -d "$SECRETS_SOURCE" ] && [ -n "$(ls -A "$SECRETS_SOURCE" 2>/dev/null)" ]; then
    echo "    Applying decrypted secrets..."
    cp -r "$SECRETS_SOURCE"/. files_overlay/
fi

# --- 4. BUILD ---
echo "[3/5] Cleaning previous builds..."
make clean
mkdir -p tmp

echo "[4/5] Building Firmware for $BOARD..."
make image PROFILE="$BOARD" \
           PACKAGES="$PACKAGES" \
           FILES="files_overlay" \
           DISABLED_SERVICES="$DISABLED_SERVICES"

# --- 5. FINISH ---
echo "[5/5] Done!"
echo "    Image is located in: $PWD/bin/targets/"