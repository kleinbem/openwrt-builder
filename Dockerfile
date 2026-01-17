FROM docker.io/library/ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies required by OpenWrt ImageBuilder
RUN apt-get update && apt-get install -y \
    build-essential \
    libncurses5-dev \
    libncursesw5-dev \
    zlib1g-dev \
    zstd \
    gawk \
    git \
    gettext \
    libssl-dev \
    xsltproc \
    rsync \
    wget \
    curl \
    unzip \
    bzip2 \
    flex \
    bison \
    python3 \
    python3-pip \
    python3-setuptools \
    file \
    fakeroot \
    sudo \
    u-boot-tools \
    device-tree-compiler \
    dosfstools \
    mtools \
    parted \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user 'builder'
# We will override UID/GID at runtime to match the host user
RUN useradd -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
