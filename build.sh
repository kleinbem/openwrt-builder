#!/usr/bin/env bash
set -e

# Usage: ./build.sh <profile_name>
PROFILE_NAME="$1"

if [ -z "$PROFILE_NAME" ]; then
    echo "Usage: $0 <profile_name>"
    echo "Available profiles:"
    ls profiles/*.conf | xargs -n 1 basename | sed 's/.conf//'
    exit 1
fi

PROFILE_CONFIG="profiles/${PROFILE_NAME}.conf"

if [ ! -f "$PROFILE_CONFIG" ]; then
    echo "❌ Error: Profile '$PROFILE_NAME' not found in profiles/ directory."
    exit 1
fi

# --- 1. LOAD PROFILE ---
echo "🔧 Loading Profile: $PROFILE_NAME"
source "$PROFILE_CONFIG"

# Check required variables
if [ -z "$BUILDER_URL" ] || [ -z "$BOARD" ]; then
    echo "❌ Error: Profile must define BUILDER_URL and BOARD."
    exit 1
fi

BUILDER_FILE="builder-${PROFILE_NAME}.tar.zst"
BUILDER_DIR_NAME="openwrt-imagebuilder-${PROFILE_NAME}"

# --- 2. PREPARE BUILDER ---
echo "[1/5] Checking for Image Builder..."
if [ ! -d "$BUILDER_DIR_NAME" ]; then
    echo "    Downloading specific builder..."
    wget -O "$BUILDER_FILE" "$BUILDER_URL"
    
    echo "    Extracting..."
    mkdir -p "$BUILDER_DIR_NAME"
    tar -xf "$BUILDER_FILE" --strip-components=1 -C "$BUILDER_DIR_NAME"
    rm "$BUILDER_FILE"
fi

cd "$BUILDER_DIR_NAME"

# --- 2.5 PREPARE SECRETS ---
SECRETS_REPO="../../openwrt-secrets"

if [ -n "$EXTERNAL_SECRETS_DIR" ] && [ -d "$EXTERNAL_SECRETS_DIR" ]; then
    echo "🔐 Using external secrets from environment: $EXTERNAL_SECRETS_DIR"
    SECRETS_SOURCE="$EXTERNAL_SECRETS_DIR"
elif [ -d "$SECRETS_REPO" ] && [ -f "$SECRETS_REPO/decrypt.sh" ]; then
    echo "🔐 Secrets repo found. Decrypting..."
    # We decrypt into the common files area temporarily or directly into overlays?
    # Let's decrypt to a temporary location that we can merge.
    
    SECRET_TMP=$(mktemp -d)
    trap 'rm -rf "$SECRET_TMP"' EXIT
    
    # Run the decrypt script from the secrets repo side
    (cd "$SECRETS_REPO" && ./decrypt.sh "$SECRET_TMP")
    
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
    cp -r ../files/${PROFILE_NAME}/* files_overlay/
fi

# Layer 3: Secrets (Highest Priority - Overwrites defaults)
if [ -n "$SECRETS_SOURCE" ] && [ -d "$SECRETS_SOURCE" ]; then
    echo "    Applying decrypted secrets..."
    cp -r "$SECRETS_SOURCE"/* files_overlay/
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