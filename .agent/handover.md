# AI Context: OpenWrt Firmware Factory

## Project Identity

**Repo Name:** `openwrt-builder`
**Role:** The "Factory". Produces immutable OS artifacts (.img files).
**Target Hardware:** Banana Pi BPI-R4 (MediaTek Filogic 880).
**Build System:** Containerized Image Builder (Podman/Docker).

## Architectural Constraints (CRITICAL)

1. **Memory:** the BPI-R4 runs with its full 4 GiB (no `mem=` in `uEnv.txt`, since 2026-10-20). The former `mem=2048M` cap only protected MT7988 hardware flow offloading, which the config keeps off. Do NOT re-add it unless HW offload is enabled and 4 GiB is shown to break it.
2. **Containerized Build:** All builds MUST run inside the provided Docker container to ensure reproducibility and compatibility (avoiding NixOS `fakeroot` issues).
3. **Secrets:** Secrets are stored encrypted in `kleinbem-secrets` (`openwrt/`). They are decrypted **on the host** into a tmpfs dir under `$XDG_RUNTIME_DIR` (`/tmp` without one), mounted read-only into the container and copied into the build's `files_overlay`; both are wiped when the build exits.

## Current State

- **Stable & reproducible.**
- `Justfile`: Main entry point (`just build <profile>`).
- `Dockerfile`: Provides the build environment (Ubuntu 26.04 + Tools).
- `profiles/bpi-r4.conf`: Configured for Wi-Fi 7, SFP+, and Containers.

## Package Manifest Strategy

- **Base:** `base-files`, `busybox`, `uci`, `dropbear`.
- **Network:** `netbird`, `dawn` (roaming), `wireguard`.
- **Virtualization:** `lxc`, `kmod-veth`, `kmod-macvlan`.
- **Monitoring:** `prometheus-node-exporter-lua`.

## Usage

```bash
just build bpi-r4
```
