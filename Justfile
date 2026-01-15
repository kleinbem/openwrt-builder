# Justfile for OpenWrt Builder

set dotenv-load

default:
    @just --list

# Build a firmware image for a specific profile (e.g. bpi-r4)
build profile:
    bash build.sh {{profile}}

# List available profiles
list-profiles:
    @ls profiles/*.conf | xargs -n 1 basename | sed 's/.conf//'

# Clean build artifacts
clean:
    rm -rf openwrt-imagebuilder-* bin/

# Validate scripts
check:
    shellcheck build.sh
