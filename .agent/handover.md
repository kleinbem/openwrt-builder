# AI Context: OpenWrt Firmware Factory

## Project Identity

**Repo Name:** `openwrt-builder`
**Role:** The "Factory". Produces immutable OS artifacts (.img files).
**Target Hardware:** Banana Pi BPI-R4 (MediaTek Filogic 880).
**Base System:** OpenWrt Snapshot (FrankW fork logic applied via Builder).

## Architectural Constraints (CRITICAL)

1. **Memory Limit:** MUST enforce `mem=2048M` in `uEnv.txt` to prevent NPU/PPE crashes on the BPI-R4.
2. **Modular Profiles:** Do NOT hardcode board logic in `build.sh`. Use `profiles/*.conf`.
3. **No Secrets:** SSH keys in `files/common` must be placeholders or public keys only.

## Current State

- `build.sh`: Modular script implemented. Loads profile config to download ImageBuilder.
- `profiles/bpi-r4.conf`: Defines packages for 10G SFP+, Wi-Fi 7, and LXC/Docker support.
- `files/bpi-r4/boot/uEnv.txt`: Contains the 2GB limit fix.

## Package Manifest Strategy

- **Base:** `base-files`, `busybox`, `uci`, `dropbear`.
- **Network:** `tailscale`, `dawn` (roaming), `wireguard`.
- **Virtualization:** `lxc`, `kmod-veth`, `kmod-macvlan` (for containers).
- **Monitoring:** `prometheus-node-exporter-lua`.

## Immediate Next Tasks for AI

1. **Validation:** Run a dry-run of `./build.sh bpi-r4` to verify Image Builder download URL is valid.
2. **Profile Expansion:** Create a `profiles/generic-x86.conf` template for future use.
3. **CI/CD:** Generate a GitHub Actions workflow to cache the ImageBuilder and run a syntax check on scripts.
