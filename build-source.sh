#!/usr/bin/env bash
set -e

# Usage: ./build-source.sh [bpi-r4]
# Currently hardcoded for BPI-R4 logic but structure allows expansion.

# Auto-enter Nix FHS Environment if available (fixes CI runners missing headers)
if [ -z "$IN_OpenWrt_FHS" ] && command -v nix-build >/dev/null; then
    echo "❄️  Nix detected. Building FHS environment..."
    export IN_OpenWrt_FHS=1
    # Allow building as root (fakeroot)
    export FORCE_UNSAFE_CONFIGURE=1
    # Build the FHS wrapper
    # We use --no-out-link to avoid cluttering the workspace
    FHS=$(nix-build shell.nix --no-out-link -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixos-24.11.tar.gz)
    
    # Execute the script INSIDE the FHS wrapper
    echo "🔄 Re-executing inside FHS container: $FHS"
    exec "$FHS/bin/openwrt-builder-env" "$0" "$@"
fi

SOURCE_DIR="openwrt-source"

# --- FAST FAIL SMOKE TEST & FIXES ---
echo "🛠️ Applying fixes and running smoke tests..."

# Fix ppp permissions (Remove setuid 4550 which fails in rootless build)
# Fix ppp permissions (Remove setuid 4550 which fails in rootless build)
if [ -d "$SOURCE_DIR" ]; then
    echo "🔧 Patching ppp OpenWrt Recipe to enforce permission fix..."
    PPP_MK="$SOURCE_DIR/package/network/services/ppp/Makefile"
    
    # Check if we can find the Build/Compile section
    if grep -q "define Build/Compile" "$PPP_MK"; then
        # Inject our fix at the start of Build/Compile
        # We use 'find' to be robust against directory structure changes
        sed -i '/define Build\/Compile/a \\tfind $(PKG_BUILD_DIR) -name Makefile -exec sed -i "s/4550/0755/g" {} +' "$PPP_MK"
        echo "   ✅ Injected fix into Build/Compile"
    else
        # Fallback: Append a pre-compile hook if Build/Compile is missing (default)
        echo "define Build/Compile" >> "$PPP_MK"
        echo -e "\tfind \$(PKG_BUILD_DIR) -name Makefile -exec sed -i 's/4550/0755/g' {} +" >> "$PPP_MK"
        echo -e "\t\$(call Build/Compile/Default)" >> "$PPP_MK"
        echo "endef" >> "$PPP_MK"
        echo "   ✅ Appended custom Build/Compile"
    fi
fi

# Smoke Test: Build ppp first (Fast Fail)
if [ -d "$SOURCE_DIR" ]; then
    echo "🔥 Running Smoke Test: Building ppp..."
    # Clean first ensuring our Modified Recipe runs from scratch
    make -C "$SOURCE_DIR" package/network/services/ppp/clean
    make -C "$SOURCE_DIR" package/network/services/ppp/compile -j$(nproc) || {
        echo "❌ Smoke Test Failed: ppp build error"
        exit 1
    }
    echo "✅ Smoke Test Passed!"
fi
# ------------------------------------
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
