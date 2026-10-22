# Justfile for OpenWrt Builder

set dotenv-load

default:
    @just --list

# Build using Docker/Podman (Default). device is optional — selects a
# stable per-device dropbear host key from kleinbem-secrets/openwrt/
# per-device/<device>.yaml instead of letting dropbear generate a fresh
# one on first boot (see ansible.cfg's host_key_checking note). Real
# devices today: core-gateway, ap-upstairs (bpi-r4); the Orbi APs
# (orbi-rbr50 / orbi-rbs50) get theirs when they are named in inventory.nix.
build profile device="": build-image
    #!/usr/bin/env bash
    set -e
    # 0. Clean previous artifacts (Avoid Nix store path pollution in standard container)
    echo "Cleaning previous ImageBuilder artifacts..."
    rm -rf openwrt-imagebuilder-*

    # 1. Prepare Secrets Directory
    SECRET_TMP=$(mktemp -d)
    echo "Decrypting secrets on host to $SECRET_TMP..."

    # 2. Decrypt on Host (requires YubiKey). The nix-shell wrapper guarantees
    # python3 for decrypt-secrets.sh even outside the devshell. Reads from
    # kleinbem-secrets (cutover 2026-08-08, replaces openwrt-secrets).
    SECRETS_FILE="../kleinbem-secrets/openwrt/firmware-files.yaml"
    if [ -f "$SECRETS_FILE" ]; then
        nix-shell -p python3 --run "./scripts/decrypt-secrets.sh \"$SECRETS_FILE\" \"$SECRET_TMP\""
    else
        echo "Warning: Secrets file not found at $SECRETS_FILE."
    fi

    # 2.5 Per-device overlay (stable dropbear host key etc), decrypted into
    # the same temp dir so it lands in files_overlay/ alongside the shared
    # secrets above — see build.sh's own per-device merge for why order
    # here doesn't matter (last decrypt into a given path wins either way,
    # and there's no overlap today).
    if [ -n "{{device}}" ]; then
        DEVICE_SECRETS_FILE="../kleinbem-secrets/openwrt/per-device/{{device}}.yaml"
        if [ -f "$DEVICE_SECRETS_FILE" ]; then
            echo "Decrypting per-device secrets for {{device}}..."
            nix-shell -p python3 --run "./scripts/decrypt-secrets.sh \"$DEVICE_SECRETS_FILE\" \"$SECRET_TMP\""
        else
            echo "Warning: No per-device secrets file for '{{device}}' ($DEVICE_SECRETS_FILE)."
        fi
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
    # BPI-R4: *.img.gz (eMMC/SD) + *.itb. Orbi (Netgear DNI): *-factory.img
    # for nmrpflash / first install, *-sysupgrade.bin for in-place upgrades.
    find openwrt-imagebuilder-*/bin/targets -name "*.img.gz" -exec cp {} dist/ \;
    find openwrt-imagebuilder-*/bin/targets -name "*.itb" -exec cp {} dist/ \;
    find openwrt-imagebuilder-*/bin/targets -name "*-factory.img" -exec cp {} dist/ \;
    find openwrt-imagebuilder-*/bin/targets -name "*-sysupgrade.bin" -exec cp {} dist/ \;
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
