#!/usr/bin/env bash
set -e

# Usage: ./build-source.sh [bpi-r4]
# Currently hardcoded for BPI-R4 logic but structure allows expansion.

# Auto-enter Nix FHS Environment if available (fixes CI runners missing headers)
if [ -z "$IN_OpenWrt_FHS" ] && command -v nix-build >/dev/null; then
    echo "❄️  Nix detected. Building FHS environment..."
    export IN_OpenWrt_FHS=1
    # Build the FHS wrapper
    # We use --no-out-link to avoid cluttering the workspace
    FHS=$(nix-build shell.nix --no-out-link -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixos-24.11.tar.gz)
    
    BUILD_CMD="$FHS/bin/openwrt-builder-env"
    
    echo "🔍 Debugging Host Namespace Capabilities:"
    echo "   User: $(id)"
    echo "   Sysctl userns: $(sysctl kernel.unprivileged_userns_clone 2>/dev/null || echo 'FAIL-READ')"
    if unshare -U echo "   Unshare test: SUCCESS"; then
        echo "   (Host allows user namespaces)"
    else
        echo "   Unshare test: FAILED (Host blocking namespaces)"
    fi
    
    # Execute the script INSIDE the FHS wrapper
    echo "🔄 Re-executing inside FHS container: $FHS"
    exec "$BUILD_CMD" "$0" "$@"
fi

SOURCE_DIR="openwrt-source"
# Correct OpenWrt fork for BPI-R4 (FrankW's patches are here)
REPO_URL="https://github.com/frank-w/openwrt.git"
BRANCH="bpi-r4-wifi-be14" # Using the Wi-Fi 7 enabled branch

echo "🚀 Starting Local Source Build (FrankW Fork)..."

# --- 1. PREPARE SOURCE ---
if [ -d "$SOURCE_DIR" ] && [ ! -d "$SOURCE_DIR/scripts" ]; then
    echo "⚠️  Detected invalid source directory. Cleaning up..."
    rm -rf "$SOURCE_DIR"
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "    Cloning source (Branch: $BRANCH)..."
    git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$SOURCE_DIR"
else
    echo "    Source directory exists. Pulling latest..."
    (cd "$SOURCE_DIR" && git pull)
fi

# --- 2. UPDATE FEEDS ---
echo "    Updating feeds..."
(cd "$SOURCE_DIR" && ./scripts/feeds update -a && ./scripts/feeds install -a)

# --- 3. CONFIGURE ---
echo "    Configuring for BPI-R4..."
cd "$SOURCE_DIR"
echo "CONFIG_TARGET_mediatek=y" > .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_bananapi_bpi-r4=y" >> .config

# --- BPI-R4 Optimizations ---
# 1. Resize Partitions (Utilize that 8GB eMMC!)
echo "CONFIG_TARGET_KERNEL_PARTSIZE=128" >> .config     # 128MB Kernel (Safe for future-proofing)
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config    # 2GB RootFS (Plenty for Podman/LXC)

# 2. Kernel Features (BBR, BTRFS, ZRAM)
echo "CONFIG_TCP_CONG_BBR=y" >> .config                # BBR Congestion Control
echo "CONFIG_DEFAULT_BBR=y" >> .config                 # Set BBR as default
echo "CONFIG_BTRFS_FS=y" >> .config                    # BTRFS Filesystem Support
echo "CONFIG_ZRAM=y" >> .config                        # ZRAM (Compressed RAM Block Device)
echo "CONFIG_ZSMALLOC=y" >> .config                    # Memory allocator for ZRAM

# 2.5 NixOS / LXC Requirements (Systemd Support)
echo "CONFIG_CGROUPS=y" >> .config                     # Control Groups (Required by Systemd)
echo "CONFIG_MEMCG=y" >> .config                       # Memory Resource Controller
echo "CONFIG_CGROUP_PIDS=y" >> .config                 # PIDs Resource Controller
echo "CONFIG_NAMESPACES=y" >> .config                  # Namespaces Support
echo "CONFIG_SECCOMP=y" >> .config                     # Seccomp Security (Required by Systemd)
echo "CONFIG_SECCOMP_FILTER=y" >> .config              # Seccomp Filter

# 3. Optimization
echo "CONFIG_DEVEL=y" >> .config                         # Enable advanced options
echo "CONFIG_CCACHE=y" >> .config                        # Enable compiler cache locally
make defconfig
cd ..

# --- 4. PREPARE FILES & SECRETS ---
echo "    Merging files and secrets..."
# The source build looks for a 'files' folder in its root.
mkdir -p "$SOURCE_DIR/files"

# 4.1 Common Files
if [ -d "files/common" ]; then
    cp -r files/common/* "$SOURCE_DIR/files/"
fi

# 4.2 Board Files
if [ -d "files/bpi-r4" ]; then
    cp -r files/bpi-r4/* "$SOURCE_DIR/files/"
fi

# 4.3 SECRETS (The Magic Part)
SECRETS_REPO="../openwrt-secrets"
if [ -d "$SECRETS_REPO" ] && [ -f "$SECRETS_REPO/decrypt.sh" ]; then
    echo "🔐 Secrets repo found. Decrypting..."
    SECRET_TMP=$(mktemp -d)
    trap 'rm -rf "$SECRET_TMP"' EXIT
    
    (cd "$SECRETS_REPO" && ./decrypt.sh "$SECRET_TMP")
    
    if [ -n "$(ls -A "$SECRET_TMP")" ]; then
         echo "    Injecting secrets into source build..."
         cp -r "$SECRET_TMP"/* "$SOURCE_DIR/files/"
    else
         echo "    (No secrets decrypted)"
    fi
fi

# --- 5. BUILD ---
echo "🔨 Building Firmware (This WILL take ~30-60 mins)..."
cd "$SOURCE_DIR"
# Use all cores, pipe to log, fallback to single core verbose on failure
mkdir -p ../logs
LOG_FILE="../logs/build-$(date +%F_%H-%M-%S).log"
echo "    Logging to: $LOG_FILE"

# Enable pipefail so if make fails, the whole pipe fails
set -o pipefail

make -j$(nproc) 2>&1 | tee "$LOG_FILE" || {
    echo "⚠️  Parallel build failed. Retrying with single core and verbose output..." | tee -a "$LOG_FILE"
    make -j1 V=s 2>&1 | tee -a "$LOG_FILE"
}

echo "✅ Build Complete!"
echo "    Images are in: $PWD/bin/targets/mediatek/filogic/"
