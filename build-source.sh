#!/usr/bin/env bash
set -e

# ==============================================================================
# OpenWrt Build Script (Containerized Version) 🐳
# ==============================================================================
# This script automatically relaunches itself inside a Docker/Podman container
# to ensure a consistent, FHS-compliant build environment (Ubuntu 22.04).
# ==============================================================================

# 1. CONTAINER LAUNCH LOGIC
# ------------------------------------------------------------------------------
if [ -z "$IN_BUILD_CONTAINER" ]; then
    echo "🚢 Setting up Container Environment..."

    # A. Detect Engine (Prefer Podman on NixOS)
    if command -v podman >/dev/null; then
        ENGINE="podman"
    elif command -v docker >/dev/null; then
        ENGINE="docker"
    else
        echo "❌ Error: Neither podman nor docker found. Please install one."
        exit 1
    fi
    echo "    Engine detected: $ENGINE"

    # B. Secrets Handling (Decrypt on Host -> Mount RO to Container)
    # We decrypt on the host because the host has 'sops' configured.
    SECRETS_REPO="../openwrt-secrets"
    SECRET_MOUNT_ARGS=""
    HOST_SECRET_TMP=""
    
    if [ -d "$SECRETS_REPO" ] && [ -f "$SECRETS_REPO/decrypt.sh" ]; then
        echo "🔐 Secrets repo found. Decrypting on Host..."
        HOST_SECRET_TMP=$(mktemp -d)
        # Ensure cleanup on host
        trap 'rm -rf "$HOST_SECRET_TMP"' EXIT
        
        # Run decryption
        (cd "$SECRETS_REPO" && ./decrypt.sh "$HOST_SECRET_TMP")
        
        # Verify if secrets were actually decrypted
        if [ -n "$(ls -A "$HOST_SECRET_TMP")" ]; then
            echo "    Secrets decrypted to temporary location."
            # Mount this tmp dir to /secrets in the container
            SECRET_MOUNT_ARGS="-v $HOST_SECRET_TMP:/secrets:ro"
        else
            echo "    (No secrets decrypted/empty output)"
        fi
    fi

    # C. Cache Directories (Host -> Container)
    # Persist downloads and compiler cache for speed
    HOST_DL_DIR="$(pwd)/openwrt-source/dl"
    HOST_CCACHE_DIR="$HOME/.ccache"
    mkdir -p "$HOST_DL_DIR" "$HOST_CCACHE_DIR"

    # D. Launch Container
    echo "🚀 Launching $ENGINE container (ubuntu:22.04)..."
    exec $ENGINE run --rm -ti \
        --name openwrt-builder-$(date +%s) \
        -v "$(pwd):/workspace" \
        -w "/workspace" \
        -v "$HOST_CCACHE_DIR:/root/.ccache" \
        $SECRET_MOUNT_ARGS \
        -e IN_BUILD_CONTAINER=1 \
        -e DEBIAN_FRONTEND=noninteractive \
        ubuntu:22.04 \
        /workspace/build-source.sh "$@"
fi

# ==============================================================================
# 2. IN-CONTAINER BUILD LOGIC
# ==============================================================================
echo "📦 [Container] Running Build Logic..."

# A. Bootstrap Environment (Install Deps)
# Check for a marker file to avoid re-running apt-get (optimization for interactive use)
if [ ! -f "/tmp/deps_installed" ]; then
    echo "    Installing Dependencies (apt-get)..."
    apt-get update -qq
    apt-get install -y -qq build-essential clang flex bison g++ gawk \
        gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
        python3-distutils rsync unzip zlib1g-dev file wget python3 ccache \
        libelf-dev python3-setuptools swig >/dev/null
    touch /tmp/deps_installed
fi

SOURCE_DIR="openwrt-source"

# B. Prepare Secrets (Inject from Mount)
if [ -d "/secrets" ]; then
    echo "🔐 [Container] Injecting secrets..."
    mkdir -p "$SOURCE_DIR/files" 2>/dev/null || true
    # We copy them because openwrt build might modify files dir (unlikely but safer)
    cp -r /secrets/* "$SOURCE_DIR/files/" 2>/dev/null || true
fi

# C. Config Variables
REPO_URL="https://github.com/frank-w/openwrt.git"
BRANCH="bpi-r4-wifi-be14"

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

# Clean up any 'nuclear' hacks referenced in previous versions if they exist
# (We are clean now, but just in case)
git checkout package/network/services/ppp/Makefile 2>/dev/null || true

echo "CONFIG_TARGET_mediatek=y" > .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_bananapi_bpi-r4=y" >> .config

# BPI-R4 Optimizations
echo "CONFIG_TARGET_KERNEL_PARTSIZE=128" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config
echo "CONFIG_TCP_CONG_BBR=y" >> .config
echo "CONFIG_DEFAULT_BBR=y" >> .config
echo "CONFIG_BTRFS_FS=y" >> .config
echo "CONFIG_ZRAM=y" >> .config
echo "CONFIG_ZSMALLOC=y" >> .config

# Systemd Support (LXC/Podman friendly)
echo "CONFIG_CGROUPS=y" >> .config
echo "CONFIG_MEMCG=y" >> .config
echo "CONFIG_CGROUP_PIDS=y" >> .config
echo "CONFIG_NAMESPACES=y" >> .config
echo "CONFIG_SECCOMP=y" >> .config
echo "CONFIG_SECCOMP_FILTER=y" >> .config

# Optimization
echo "CONFIG_DEVEL=y" >> .config
echo "CONFIG_CCACHE=y" >> .config
make defconfig
cd ..

# --- 4. FILES (Overlay) ---
echo "    Merging files..."
mkdir -p "$SOURCE_DIR/files"
if [ -d "files/common" ]; then
    cp -r files/common/* "$SOURCE_DIR/files/"
fi
if [ -d "files/bpi-r4" ]; then
    cp -r files/bpi-r4/* "$SOURCE_DIR/files/"
fi

# --- 5. BUILD ---
echo "🔨 Building Firmware (In Container)..."
cd "$SOURCE_DIR"
mkdir -p ../logs
LOG_FILE="../logs/build-$(date +%F_%H-%M-%S).log"
echo "    Logging to: $LOG_FILE"

set -o pipefail
# We use $(nproc) but usually -1 inside containers to be nice, but here we want speed.
make -j$(nproc) 2>&1 | tee "$LOG_FILE" || {
    echo "⚠️  Parallel build failed. Retrying single core..." | tee -a "$LOG_FILE"
    make -j1 V=s 2>&1 | tee -a "$LOG_FILE"
}

echo "✅ Build Complete!"
echo "    Images: bin/targets/mediatek/filogic/"
exit 0
