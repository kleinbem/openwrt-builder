---
priority: critical
role: FirmwareFactory
---

# SYSTEM HANDOVER: OpenWrt Firmware Factory

## Project Identity

**Repo Name:** `openwrt-builder`
**Target:** Banana Pi BPI-R4 (MediaTek Filogic 880)

## CRITICAL RULES (DO NOT VIOLATE)

1. **Memory Limit:** You MUST ensure `mem=2048M` is present in `uEnv.txt` for BPI-R4 builds. This prevents NPU crashes.
2. **No Hardcoding:** Never edit `build.sh` logic for a specific board. Always edit `profiles/*.conf`.
3. **Filesystem:** Do not output artifacts to the root. Use `bin/`.

## Architecture

- `build.sh`: The logic script.
- `profiles/`: The hardware definitions.
- `files/`: The overlay files.

## Maintenance

- Keep `Dockerfile` dependencies updated.
- Verify `profiles/*.conf` URLs against OpenWrt snapshot updates.
