# Justfile for OpenWrt Builder

set dotenv-load

# kleinbem-secrets checkout to read from and write to. Override to use a
# jj workspace instead of the primary checkout:
#   KLEINBEM_SECRETS=../kleinbem-secrets.ws/<name> just ...
secrets := env_var_or_default("KLEINBEM_SECRETS", "../kleinbem-secrets")

default:
    @just --list

# Optional device bakes in kleinbem-secrets/openwrt/per-device/<device>.yaml,
# a stable dropbear host key, so a reflash keeps the SSH identity.
# Build in Podman; device (optional) adds its stable SSH host key
build profile device="": build-image
    #!/usr/bin/env bash
    set -e
    # 0. Clean previous artifacts (Avoid Nix store path pollution in standard container)
    echo "Cleaning previous ImageBuilder artifacts..."
    rm -rf openwrt-imagebuilder-*

    # 1. Prepare Secrets Directory. XDG_RUNTIME_DIR is tmpfs; the trap wipes the
    # plaintext (and build.sh's overlay copy) on every exit path.
    SECRET_TMP=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/openwrt-secrets.XXXXXX")
    trap 'rm -rf "$SECRET_TMP" openwrt-imagebuilder-*/files_overlay' EXIT
    echo "Decrypting secrets on host to $SECRET_TMP..."

    # 2. Decrypt on Host (requires YubiKey). nix-shell guarantees python3
    # for decrypt-secrets.sh even outside the devshell.
    SECRETS_FILE="{{secrets}}/openwrt/firmware-files.yaml"
    if [ -f "$SECRETS_FILE" ]; then
        nix-shell -p python3 --run "./scripts/decrypt-secrets.sh \"$SECRETS_FILE\" \"$SECRET_TMP\""
    else
        echo "Warning: Secrets file not found at $SECRETS_FILE."
    fi

    # 2.5 Per-device overlay, decrypted into the same dir after the shared
    # file, so it wins on a colliding path.
    if [ -n "{{device}}" ]; then
        DEVICE_SECRETS_FILE="{{secrets}}/openwrt/per-device/{{device}}.yaml"
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

# Writes kleinbem-secrets/openwrt/per-device/<device>.yaml for
# `build <profile> <device>`. Needs the device's creation rule in
# kleinbem-secrets/.sops.yaml first; no YubiKey (public recipients only).
# Refuses to overwrite: a key rotation is done by hand.
# New device: stable dropbear host key + its known_hosts line
device-key device ip:
    #!/usr/bin/env bash
    set -euo pipefail
    out="{{secrets}}/openwrt/per-device/{{device}}.yaml"
    if [ -e "$out" ]; then echo "❌ $out already exists"; exit 1; fi
    tmp=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/device-key.XXXXXX")
    trap 'rm -rf "$tmp" "$out.tmp"' EXIT
    nix shell nixpkgs#dropbear -c dropbearkey -t ed25519 -f "$tmp/key" >/dev/null
    pub=$(nix shell nixpkgs#dropbear -c dropbearkey -y -f "$tmp/key" | grep '^ssh-ed25519' | cut -d' ' -f1,2)
    # path must be relative: decrypt-secrets.sh skips anything that
    # resolves outside its target dir, and os.path.join drops the target
    # for an absolute path.
    printf 'files:\n    - path: etc/dropbear/dropbear_ed25519_host_key\n      encoding: base64\n      mode: "0600"\n      content: %s\n' \
        "$(base64 -w0 "$tmp/key")" \
        | (cd "{{secrets}}" && sops -e --filename-override "openwrt/per-device/{{device}}.yaml" \
            --input-type yaml --output-type yaml /dev/stdin) > "$out.tmp"
    mv "$out.tmp" "$out"
    echo "✅ wrote $out"
    echo "known_hosts: {{device}},{{ip}} $pub"

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
    shellcheck build.sh scripts/*.sh
