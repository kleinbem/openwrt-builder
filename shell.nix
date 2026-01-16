{
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.11.tar.gz") { },
}:

# Using buildFHSUserEnv to provide a standard /bin/bash and other FHS paths
# This fixes "bad interpreter: /bin/bash" errors in OpenWrt host tools (like util-linux)
(pkgs.buildFHSUserEnv {
  name = "openwrt-builder-env";
  targetPkgs =
    pkgs:
    (with pkgs; [
      # Core build tools
      gnumake
      gcc11
      perl
      wget
      unzip
      git
      file
      which
      rsync
      patch
      diffutils

      # Build system
      gawk
      flex
      bison
      gettext
      quilt
      swig

      # Python
      python311
      python311Packages.setuptools

      # Libraries
      ncurses
      zlib
      openssl

      # Utilities
      zstd
    ]);

  # Disable hardening for host tools (elfutils fix)
  profile = ''
    export CFLAGS="-Wno-error=format-security"
    echo "Welcome to the OpenWrt FHS Builder Environment"
  '';
})
