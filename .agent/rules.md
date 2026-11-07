---
priority: critical
role: FirmwareFactory
---

# SYSTEM HANDOVER: OpenWrt Firmware Factory

## Project Identity

**Repo Name:** `openwrt-builder`
**Target:** Banana Pi BPI-R4 (MediaTek Filogic 880)

## CRITICAL RULES (DO NOT VIOLATE)

1. **Memory:** `uEnv.txt` for BPI-R4 builds carries NO `mem=` limit (full 4 GiB, since 2026-10-20). The old `mem=2048M` cap was only for MT7988 hardware flow offloading, which stays disabled; never re-add it without a measured reason.
2. **No Hardcoding:** Never edit `build.sh` logic for a specific board. Always edit `profiles/*.conf`.
3. **Filesystem:** Do not output artifacts to the root. Use `bin/`.

## Architecture

- `build.sh`: The logic script.
- `profiles/`: The hardware definitions.
- `files/`: The overlay files.

## Maintenance

- Keep `Dockerfile` dependencies updated.
- Verify `profiles/*.conf` URLs against OpenWrt snapshot updates.
