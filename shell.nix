{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Orchestration
    just

    # Container Runtime
    podman

    # Secrets Management
    sops
    age
    ssh-to-age

    # Host-side Scripting
    python3
    git
  ];

  shellHook = ''
    echo "Welcome to the OpenWrt Builder Host Shell"
    echo "Run 'just build bpi-r4' to start."
  '';
}
