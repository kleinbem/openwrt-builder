---
description: Build a custom OpenWrt image
---

# Workflow: Build Image

To build an image for a specific board (e.g., `bpi-r4`):

1. **Verify Profile**: Ensure the profile exists in `profiles/`.

   ```bash
   just list
   ```

2. **Build Image**:

   ```bash
   just build bpi-r4
   ```

3. **Locate Artifact**: `just build` copies the images to `dist/`. Look for the `sysupgrade.itb` or `.img.gz` file. `dist/` keeps earlier builds, so run `just clean` first (or check the file's time) before picking an image to flash.
