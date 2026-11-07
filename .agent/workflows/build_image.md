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

3. **Locate Artifact**: The output will be in `bin/targets/mediatek/filogic/`. Look for the `sysupgrade.itb` or `.img.gz` file.
