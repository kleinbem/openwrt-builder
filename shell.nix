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
    swig

    # Python
    python311
    python311Packages.setuptools # Provides distutils fallback
    # python311Packages.distutils # Legacy if needed, but 3.11 still has it partially or via setuptools better

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
