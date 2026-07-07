# Justfile for OpenWrt Builder

set dotenv-load

default:
    @just --list

# Build using Docker/Podman (Default)
build profile: build-image
    #!/usr/bin/env bash
    set -e
    # 0. Clean previous artifacts (Avoid Nix store path pollution in standard container)
    echo "Cleaning previous ImageBuilder artifacts..."
    rm -rf openwrt-imagebuilder-*

    # 1. Prepare Secrets Directory
    SECRET_TMP=$(mktemp -d)
    echo "Decrypting secrets on host to $SECRET_TMP..."

    # 2. Decrypt on Host (requires YubiKey). The nix-shell wrapper guarantees
    # python3 for decrypt.sh even outside the devshell.
    if [ -f "../openwrt-secrets/decrypt.sh" ]; then
        nix-shell -p python3 --run "cd ../openwrt-secrets && ./decrypt.sh \"$SECRET_TMP\""
    else
        echo "Warning: Secrets repo not found."
    fi

    # 3. Run Build in Container (no -t: must also work without a TTY in CI)
    echo "Starting Container Build..."
    mkdir -p dl
    podman run --rm -i \
        --userns=keep-id \
        -v "$PWD":/workspace \
        -v "$PWD/dl":/workspace/dl \
        -v "$SECRET_TMP":/secrets:ro \
        -w /workspace \
        -e EXTERNAL_SECRETS_DIR=/secrets \
        openwrt-builder \
        bash -c "bash build.sh {{profile}}"

    # 4. Extract Relevant Artifacts to Host
    mkdir -p dist
    find openwrt-imagebuilder-*/bin/targets -name "*.img.gz" -exec cp {} dist/ \;
    find openwrt-imagebuilder-*/bin/targets -name "*.itb" -exec cp {} dist/ \;
    find openwrt-imagebuilder-*/bin/targets -name "sha256sums" -exec cp {} dist/ \;
    echo "✅ Firmware images copied to ./dist/"

    # 5. Cleanup sensitive data
    rm -rf "$SECRET_TMP"

# Build environment container image
build-image:
    podman build -t openwrt-builder .

# List available profiles
list:
    @ls profiles/*.conf | xargs -n 1 basename | sed 's/.conf//'

# Clean build artifacts
clean:
    rm -rf openwrt-imagebuilder-* bin/ dist/

# Validate scripts
check:
    shellcheck build.sh
