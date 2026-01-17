#!/usr/bin/env bash
set -e

# ==============================================================================
# OpenWrt PPP Permission Fixer
# ==============================================================================
# Problem: Old PPP versions in OpenWrt try to install plugins with '4550' (setuid)
#          permissions, which fails in rootless containers (GitHub Runners).
# Fix:     Recursively find all Makefiles in the ppp build directory and 
#          replace '4550' with '0755'.
# ==============================================================================

BUILD_DIR="$1"

if [ -z "$BUILD_DIR" ]; then
    echo "Usage: $0 <path-to-build-dir>"
    exit 1
fi

echo "🔧 [Fixer] Scanning for '4550' permissions in $BUILD_DIR..."

# Find the PPP build directory safely
TARGET_PPP_DIR=$(find "$BUILD_DIR" -type d -path "*/linux-mediatek_filogic/ppp-default" | head -n 1)

if [ -z "$TARGET_PPP_DIR" ]; then
    echo "⚠️  [Fixer] Warning: PPP build directory not found yet. This might be a pre-download run."
    # Fallback to broad search if specific path fails/doesn't exist
    TARGET_PPP_DIR="$BUILD_DIR"
fi

echo "   Target: $TARGET_PPP_DIR"

# Count matches before fixing
MATCH_COUNT=$(grep -r "4550" "$TARGET_PPP_DIR" 2>/dev/null | wc -l || true)

if [ "$MATCH_COUNT" -gt 0 ]; then
    echo "   Found $MATCH_COUNT instances of '4550'. Patching..."
    # Apply the fix globally to Makefiles
    find "$TARGET_PPP_DIR" -name "Makefile" -exec sed -i 's/4550/0755/g' {} +
    echo "✅ [Fixer] Patched all Makefiles."
else
    echo "✅ [Fixer] No '4550' permissions found. Already clean?"
fi
