# OpenWrt Custom Image Builder

This repository contains a containerized build system designed to create custom OpenWrt images for various hardware architectures, with a focus on the **Banana Pi BPI-R4**.

It uses **Podman/Docker** to provide a clean, reproducible build environment (Ubuntu 22.04) while securely handling decrypted secrets from the host using **YubiKey**.

## Prerequisites

- **Nix** (with `direnv` used to load the shell environment)
- **Podman** (or Docker)
- **Just** (Command runner)
- **YubiKey** (For secret decryption)

## Directory Structure

- `Dockerfile`: Defines the build environment.
- `Justfile`: Orchestrates the build workflow (secrets -> container -> build).
- `build.sh`: Generic script run *inside* the container.
- `profiles/`: Configuration files (e.g., `bpi-r4.conf`).
- `files/`: Overlay files.
  - `files/common/`: Applied to all profiles.
  - `files/<profile_name>/`: Applied to specific profiles.

## Usage

Simply run `just build` with the profile name:

```bash
just build bpi-r4
```

### What happens?

1. **Cleanup**: Removes old Image Builder artifacts to prevent path pollution.
2. **Decryption**: Asks for your YubiKey PIN to decrypt secrets (WiFi keys, WireGuard, etc.) into a temporary in-memory directory on the host.
3. **Container Start**: Starts a Podman container, mounting the source code and the decrypted secrets.
4. **Build**:
    - Downloads the OpenWrt ImageBuilder.
    - Merges file overlays and secrets.
    - Generates the firmware image.
5. **Cleanup**: Wipes temporary secrets.

And that's it! The final image will be in `bin/targets/...`.

## Supported Profiles

### Banana Pi BPI-R4 (`bpi-r4`)

- **Target**: MediaTek Filogic 880
- **Features**:
  - Wi-Fi 7 (MediaTek proprietary drivers)
  - 10G SFP+ support
  - Tailscale & WireGuard pre-configured

> [!IMPORTANT]
> The BPI-R4 requires `mem=2048M` in `uEnv.txt` to prevent NPU/PPE crashes. This is handled via the `files/bpi-r4/boot/uEnv.txt` overlay.
