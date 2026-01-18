# AI Context: OpenWrt Firmware Factory

## Project Identity

**Repo Name:** `openwrt-builder`
**Role:** The "Factory". Produces immutable OS artifacts (.img files).
**Target Hardware:** Banana Pi BPI-R4 (MediaTek Filogic 880).
**Build System:** Containerized Image Builder (Podman/Docker).

## Architectural Constraints (CRITICAL)

1. **Memory Limit:** MUST enforce `mem=2048M` in `uEnv.txt` to prevent NPU/PPE crashes on the BPI-R4.
2. **Containerized Build:** All builds MUST run inside the provided Docker container to ensure reproducibility and compatibility (avoiding NixOS `fakeroot` issues).
3. **Secrets:** Secrets are stored encrypted in the `openwrt-secrets` repo. They are decrypted **on the host** into memory and mounted into the container.

## Current State

- **Stable & reproducible.**
- `Justfile`: Main entry point (`just build <profile>`).
- `Dockerfile`: Provides the build environment (Ubuntu 22.04 + Tools).
- `profiles/bpi-r4.conf`: Configured for Wi-Fi 7, SFP+, and Containers.

## Package Manifest Strategy

- **Base:** `base-files`, `busybox`, `uci`, `dropbear`.
- **Network:** `tailscale`, `dawn` (roaming), `wireguard`.
- **Virtualization:** `lxc`, `kmod-veth`, `kmod-macvlan`.
- **Monitoring:** `prometheus-node-exporter-lua`.

## Usage

```bash
just build bpi-r4
```
