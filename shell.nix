{
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.11.tar.gz") { },
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Core build tools
    gnumake
    gcc
    perl
    wget
    unzip
    git
    file
    which
    rsync
    patch
    diffutils # for cmp

    # Build system
    gawk
    flex
    bison
    gettext
    quilt

    # Python
    python3
    python3Packages.setuptools # Provides distutils in newer python versions

    # Libraries
    ncurses
    zlib
    openssl

    # Utilities
    zstd
  ];

  shellHook = ''
    echo "Welcome to the OpenWrt Builder Environment"
  '';
}
