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
    # ------------------------------------
    # FIX: Package Definition Patching (The "Nuclear" Option)
    # ------------------------------------
    # Quilt patching proved unreliable (context mismatch or ignored).
    # We will now DIRECTLY MODIFY the 'package/network/services/ppp/Makefile'
    # to include a 'Build/Prepare' hook that sanitizes the source code.
    echo "🔧 Injecting 'Build/Prepare' hook into PPP Package Definition..."
    
    PPP_MK="$SOURCE_DIR/package/network/services/ppp/Makefile"
    
    # 1. Check if Build/Prepare exists. If so, append to it. If not, create it.
    # Most OpenWrt Makefiles use 'Build/Prepare/Default'.
    
    if grep -q "define Build/Prepare" "$PPP_MK"; then
         echo "   ⚠️ Build/Prepare already exists. Adding fix..."
         # Assuming it ends with 'endef', we insert before that.
         sed -i '/endef/i \\tfind $(PKG_BUILD_DIR) -name Makefile.linux -exec sed -i "s/4550/0755/g" {} +' "$PPP_MK"
    else
         echo "   ✨ Build/Prepare not found (using default). Overriding..."
         # We append the override at the end of the file, but before the "Evaluation" (last line usually) assertion?
         # No, OpenWrt Makefiles usually end with $(eval $(call ...)).
         # We can safely add the define block anywhere before that.
         # Let's add it right after PKG_INSTALL:=1 or include directives.
         
         # Find a safe insertion point (e.g. after 'include $(INCLUDE_DIR)/package.mk')
         INSERT_POINT="include \$(INCLUDE_DIR)/package.mk"
         
         # The Hook:
         # 1. Unpack (Default)
         # 2. Patch (Default)
         # 3. NUKE '4550' with '0755' in all Makefile.linux
         HOOK="define Build/Prepare\n\t\$(call Build/Prepare/Default)\n\t@echo '🧨 NUKING 4550 PERMISSIONS'\n\tfind \$(PKG_BUILD_DIR) -name Makefile.linux -exec sed -i 's/4550/0755/g' {} +\nendef\n"
         
         sed -i "/$INSERT_POINT/a $HOOK" "$PPP_MK"
    fi
    
    # Verify Injection
    if grep -q "NUKING 4550" "$PPP_MK"; then
        echo "✅ Injection Successful: PPP Build/Prepare now enforces 0755."
    else
        echo "❌ Injection Validation Failed."
        exit 1
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
    
    # VERIFICATION: Check if the 4550 permissions are actually gone
    echo "🔎 Verifying ppp fix specifically..."
    TARGET_PPP_DIR=$(find "$SOURCE_DIR/build_dir" -type d -path "*/linux-mediatek_filogic/ppp-default" | head -n 1)
    
    if [ -z "$TARGET_PPP_DIR" ]; then
        echo "❌ CRITICAL: Could not find ppp build directory for verification!"
        find "$SOURCE_DIR/build_dir" -maxdepth 4 -name "ppp-default"
        exit 1
    fi
    
    echo "   Checking directory: $TARGET_PPP_DIR"
    makefile_count=$(find "$TARGET_PPP_DIR" -name "Makefile" | wc -l)
    echo "   Found $makefile_count Makefiles to check."
    
    if [ "$makefile_count" -eq 0 ]; then
         echo "❌ CRITICAL: No Makefiles found in ppp build dir! Verification is invalid."
         exit 1
    fi

    if find "$TARGET_PPP_DIR" -name "Makefile" -exec grep -l "4550" {} +; then
        echo "❌ CRITICAL: '4550' permission string STILL FOUND in Makefiles after smoke test!"
        echo "   The fix did not apply correctly. Failing early to save time."
        find "$TARGET_PPP_DIR" -name "Makefile" -exec grep -H "4550" {} +
        exit 1
    else
        echo "✅ Verification Passed: No '4550' permissions found in $makefile_count files."
    fi
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
