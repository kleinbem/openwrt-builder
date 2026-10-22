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
> The BPI-R4 boots with its full 4 GiB since 2026-10-20 (`files/bpi-r4/boot/uEnv.txt` carries no `mem=` limit). The old `mem=2048M` cap only mattered for MT7988 **hardware flow offloading**, which our config keeps off for SQM/cake. If HW offload is ever enabled, re-test with 4 GiB first; a stale `mem=` in a saved U-Boot environment overrides uEnv.txt, and the Ansible common role asserts the board actually sees ~4 GiB (`expected_ram_mib`).
> The BPI-R4's first-boot network layout (`eth0`/`eth1`, `lan1–3` into `br-lan`, `192.168.1.1` bench address) lives in `files/bpi-r4/etc/uci-defaults/` — it names R4 interfaces, so it is not a common overlay.

### Netgear Orbi RBR50 v1 / RBS50 v1 (`orbi-rbr50`, `orbi-rbs50`)

- **Target**: Qualcomm IPQ40xx (`ipq40xx/generic`), the old Orbi mesh kit reused as plain wired access points behind the BPI-R4s.
- **Features**: three ath10k radios (2.4 GHz + 2× 5 GHz), DAWN/802.11r roaming, Prometheus exporter, LuCI; no routing packages — the gateway owns DHCP/DNS/QoS.
- **Size budget**: the Netgear DNI factory image must stay under 36175872 bytes (`IMAGE_MAX_BYTES`, checked by `build.sh`); the recipe has no check-size step of its own.
- `orbi-rbs50` only overrides `BOARD` and sources `orbi-rbr50.conf` — same release pin, packages and budget.

> [!WARNING]
> v1 hardware only (4 GB eMMC, USB port on the back). The NAND-based v2 (`artmtd -r hw_revision` → `02`, no USB port) is not supported by OpenWrt stable yet; these images will not boot on it.
> Install with `nmrpflash` and the `*-factory.img` on the LAN port nearest the power button, or through the OEM web UI only after switching to boot partition 2 (`artmtd -w boot_part 02`). See `openwrt/docs/SYSTEM_REFERENCE.md`.
