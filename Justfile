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
    
    # 2. Decrypt on Host (requires YubiKey)
    if [ -f "../openwrt-secrets/decrypt.sh" ]; then
        # We need python3 for the decryption script (usually provided by shell.nix)
        # We use nix-shell -p only if not already in an environment with python3?
        # Actually simpler: Just rely on PATH having python3 (from shell.nix).
        # But previous fix used nix-shell wrapper. Let's keep the wrapper if it works, or simplify?
        # Step 325 failed with YubiKey, likely due to nix-shell masking agent.
        # Step 290 worked with nix-shell.
        # Step 332 worked with nix-shell.
        # The wrapper ensures python3 is available.
        nix-shell -p python3 --run "cd ../openwrt-secrets && ./decrypt.sh \"$SECRET_TMP\""
    else
        echo "Warning: Secrets repo not found."
    fi

    # 3. Clean previous build artifacts inside container?
    # No, we already cleaned openwrt-imagebuilder-* above.

    # 4. Run Build in Container
    echo "Starting Container Build..."
    podman run --rm -it \
        --userns=keep-id \
        -v "$PWD":/workspace \
        -v "$PWD/dl":/workspace/dl \
        -v "$SECRET_TMP":/secrets:ro \
        -w /workspace \
        -e EXTERNAL_SECRETS_DIR=/secrets \
        openwrt-builder \
        bash -c "bash build.sh {{profile}}"

    # 5. Cleanup
    rm -rf "$SECRET_TMP"

# Build environment container image
build-image:
    podman build -t openwrt-builder .

# List available profiles
list:
    @ls profiles/*.conf | xargs -n 1 basename | sed 's/.conf//'

# Clean build artifacts
clean:
    rm -rf openwrt-imagebuilder-* bin/

# Validate scripts
check:
    shellcheck build.sh
