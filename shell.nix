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
      # Core build tools (The Kitchen Sink)
      gnumake
      gcc11
      binutils
      patch
      diffutils
      file
      which
      time
      getopt # Essential utilities
      rsync
      gnutar
      gzip
      bzip2
      xz
      zstd
      cpio
      unzip
      flock
      fakeroot # Just in case host tools need it

      # System Utilities
      util-linux # Provides setsid, logger, etc.
      procps # Provides ps, kill
      coreutils

      # Build system
      gawk
      sed
      grep
      flex
      bison
      gettext
      quilt
      swig

      # Python (Bundled with Setuptools/Distutils)
      (python311.withPackages (ps: [
        ps.setuptools
        ps.pyelftools
      ]))

      # Perl (Standard)
      perl

      # Libraries (Headers included via .dev)
      ncurses
      ncurses.dev
      zlib
      zlib.dev
      openssl
      openssl.dev
    ]);

  # Disable hardening for host tools (elfutils fix)
  profile = ''
    umask 022
    export CFLAGS="-Wno-error=format-security"
    echo "Welcome to the OpenWrt FHS Builder Environment"
  '';
})
