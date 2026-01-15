# OpenWrt Custom Image Builder

This repository contains a modular build system designed to create custom OpenWrt images for **various hardware architectures**.
While the current focus is on the **Banana Pi BPI-R4**, the system is architecture-agnostic and relies on profiles to switch targets.

## Directory Structure

- `build.sh`: **Generic** build script that orchestrates the process based on the selected profile.
- `profiles/`: Configuration files defining specific hardware targets (e.g., `bpi-r4.conf`, `x86-64.conf`).
- `files/`: Overlay files to be included in the image.
  - `files/common/`: Files applied to ALL profiles (e.g., SSH keys).
  - `files/<profile_name>/`: Files applied only to that specific profile.

## Usage

Run the build script with the desired profile name:

```bash
./build.sh <profile_name>
```

The script will:

1. Load the `profiles/<profile_name>.conf` configuration.
2. Download the OpenWrt ImageBuilder (if not present).
3. Merge `files/common` and `files/<profile_name>` overlays.
4. Build the firmware image.
5. Output the result to `bin/targets/...`

## Workflows

### 1. Hybrid Workflow (Recommended)

This is the safest and most efficient method.

- **GitHub Actions**: Runs lightweight checks and "Speed Builds" (Official Kernel) to verify configuration validity. **No secrets are included.**
- **Local Build**: Runs `build-source.sh` on your local machine.
  - Features: **FrankW Kernel** + **Decrypted Secrets**.
  - Usage: `./build-source.sh`
  - Result: Production-ready image.

### 2. Speed Build (CI/Local)

- Usage: `./build.sh bpi-r4`
- fast (~5 mins) but uses Official Kernel (missing some drivers).
- Local run includes secrets; CI run does not.

## Supported Profiles

### Banana Pi BPI-R4 (`bpi-r4`)

To build for the BPI-R4:

```bash
./build.sh bpi-r4
```

> [!IMPORTANT]
> **Memory Limit**: The BPI-R4 requires `mem=2048M` in `uEnv.txt` to prevent NPU/PPE crashes. This is handled via the `files/bpi-r4/boot/uEnv.txt` overlay.

- **Target**: MediaTek Filogic 880
- **Features**:
  - Wi-Fi 7 (MediaTek proprietary drivers)
  - 10G SFP+ support
  - Docker/LXC containerization support
  - Tailscale & WireGuard
