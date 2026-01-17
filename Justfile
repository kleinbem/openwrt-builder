# Justfile for OpenWrt Builder

set dotenv-load

default:
    @just --list

# Build using Docker/Podman (Recommended)
# Build using Docker/Podman (Recommended)
build profile:
    @just build-container {{profile}}

# Build natively using Nix FHS (Legacy)
build-native profile:
    nix-build shell.nix -o result
    ./result/bin/openwrt-builder-env -c "bash build.sh {{profile}}"

# Build environment container image
build-image:
    podman build -t openwrt-builder .

# Orchestrate the containerized build with host-side decryption
build-container profile: build-image
    #!/usr/bin/env bash
    set -e
    # 0. Clean previous artifacts (Avoid Nix store path pollution in standard container)
    echo "Cleaning previous ImageBuilder artifacts..."
    rm -rf openwrt-imagebuilder-*

    # 1. Prepare Secrets Directory
    SECRET_TMP=$(mktemp -d)
    echo "Decrypting secrets on host to $SECRET_TMP..."
    
    # 2. Decrypt on Host (requires YubiKey)
    if [ -f "../openwrt-secrets/decrypt.sh" ]; then
        nix-shell -p python3 --run "cd ../openwrt-secrets && ./decrypt.sh \"$SECRET_TMP\""
    else
        echo "Warning: Secrets repo not found."
    fi

    # 3. Release YubiKey/Smartcard resources (optional cleanup)
    # 4. Run Build in Container
    echo "Starting Container Build..."
    # Map Current User to Builder User in Container to fix permissions
    
    podman run --rm -it \
        --userns=keep-id \
        -v "$PWD":/workspace \
        -v "$SECRET_TMP":/secrets:ro \
        -w /workspace \
        -e EXTERNAL_SECRETS_DIR=/secrets \
        openwrt-builder \
        bash -c "bash build.sh {{profile}}"

    # 5. Cleanup
    rm -rf "$SECRET_TMP"

# List available profiles
list-profiles:
    @ls profiles/*.conf | xargs -n 1 basename | sed 's/.conf//'

# Clean build artifacts
clean:
    rm -rf openwrt-imagebuilder-* bin/

# Validate scripts
check:
    shellcheck build.sh
