# NixOS Self-Hosted GitHub Runner Setup

This guide details how to configure your NixOS machine to act as a secure, high-performance GitHub Actions runner for your repositories.

## 1. Prerequisites

* A **Universal Fine-Grained Personal Access Token (PAT)**.
* `sops-nix` set up for secret management.

## 2. GitHub Token Creation

To manage multiple runners with a single credential, create a **Fine-Grained PAT**.

1. Go to **GitHub Settings** -> **Developer Settings** -> **Personal access tokens** -> **Fine-grained tokens**.
2. Click **Generate new token**.
3. **Token Name**: `NixOS-Runner-Manager` (or something descriptive).
4. **Expiration**: Set to **Maximum** (usually 1 year) to minimize rotation.
5. **Description**: "Automated runner registration for NixOS".
6. **Resource owner**: `kleinbem`.
7. **Repository access**: Select **All repositories** (as per your preference).
8. **Permissions**:
    * Click **Repository permissions**.
    * Scroll to **Administration**.
    * Change access to **Read and Write**. (Critically required to register runners).
    * *Note: Metadata (Read-only) will be selected automatically.*
9. Click **Generate token** and copy it `github_pat_...`.

## 3. Secret Management (sops-nix)

Store this single token in your sops secrets.

```bash
sops secrets.yaml
# Add key: github_fine_grained_pat: "github_pat_..."
```

Update your `secrets.nix` (or wherever you define sops secrets):

```nix
sops.secrets.github_fine_grained_pat = {
  owner = "root"; # Root needs to read it to generate the specific tokens
};
```

## 4. NixOS Configuration

Add this to your `configuration.nix` (or `modules/monitoring/github-runners.nix`). This config uses the single PAT to automatically register runners for any repo you define.

```nix
{ config, pkgs, lib, ... }:
let
  # --- 1. Common Build Environment ---
  commonBuildInputs = with pkgs; [
    # Core
    git gnumake gcc binutils bzip2 gzip unzip gnutar wget curl rsync patch diffutils findutils gawk file which
    # Libs
    ncurses zlib openssl
    # Languages
    perl python3 python3Packages.setuptools
    # System
    util-linux procps
  ];

  # --- 2. The Auto-Registration Helper ---
  # This function creates a runner service that automatically exchanges the
  # Universal PAT for a Repo-Specific Registration Token at startup.
  mkRunner = { name, repoName }: {
    enable = true;
    name = "nixos-${name}";
    url = "https://github.com/kleinbem/${repoName}";
    replace = true;
    
    # The runner uses this file to authenticate
    tokenFile = "/run/secrets/github-runner-${name}-token";
    
    # Pre-start script: Exchange PAT -> Registration Token
    preStart = ''
      PAT=$(cat ${config.sops.secrets.github_fine_grained_pat.path})
      
      # Call GitHub API to get a short-lived registration token for THIS specific repo
      TOKEN=$(${pkgs.curl}/bin/curl -s -X POST -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $PAT" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        https://api.github.com/repos/kleinbem/${repoName}/actions/runners/registration-token \
        | ${pkgs.jq}/bin/jq -r .token)
        
      if [ "$TOKEN" == "null" ]; then
        echo "Error: Failed to get registration token. Check PAT permissions."
        exit 1
      fi

      echo "$TOKEN" > /run/secrets/github-runner-${name}-token
    '';

    extraPackages = commonBuildInputs ++ [ pkgs.curl pkgs.jq ];
    
    # Security: Prevent runner from reading sensitive host files
    serviceOverrides = {
      ProtectHome = "read-only";
    };
  };
in
{
  # --- 3. Instantiate Runners ---
  
  # Builder for OpenWrt
  services.github-runners.openwrt-builder = mkRunner {
    name = "builder";
    repoName = "openwrt-builder";
  };

  # Config Repo (Example)
  # services.github-runners.openwrt-config = mkRunner {
  #   name = "config";
  #   repoName = "openwrt-config";
  # };
  
  # Secrets Repo (Example)
  # services.github-runners.openwrt-secrets = mkRunner {
  #   name = "secrets";
  #   repoName = "openwrt-secrets";
  # };

  # Create the user
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
  };
  users.groups.github-runner = {};
}
```

## 5. Workflow Usage

Update `.github/workflows/build.yml` in any repo:

```yaml
jobs:
  build:
    runs-on: [self-hosted, nixos]
    steps:
      - uses: actions/checkout@v4
      - run: ./build-source.sh
```
