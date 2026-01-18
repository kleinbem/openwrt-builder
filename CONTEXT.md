# OpenWrt Builder Context

This repository is responsible for **building** custom OpenWrt firmware images using the Image Builder (ImageBuilder).

## Core Philosophy

- **Profile-based**: Different hardware (e.g., `bpi-r4`, `x86`) has its own configuration in `profiles/`.
- **Stateless**: The build process should be reproducible. All customizations (files, packages) must be committed.
- **Extensible**: New boards are added by creating a new `.conf` file in `profiles/`.

## Key Files

- `build.sh`: The main entry point. Downloads builder -> applies files -> runs `make image`.
- `profiles/*.conf`: Shell scripts that define `BOARD`, `BUILDER_URL`, and `PACKAGES` variables.
- `files/`: Directory containing filesystem overlays.
  - `common/`: Applied to ALL images.
  - `<profile>/`: Applied only to that specific profile.

## AI Workflow

To build an image:

1. Check `profiles/` for available targets.
2. Run `just build <profile_name>`.
3. Artifacts are in `bin/targets/...`.
