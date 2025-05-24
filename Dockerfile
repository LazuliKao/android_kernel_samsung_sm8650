FROM ubuntu:24.04

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Set up timezone to avoid hanging on tzdata install
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ >/etc/timezone

# Update and install general build dependencies
RUN apt-get update && apt-get install -y \
    wget curl git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
    default-jdk gnupg flex bison gperf build-essential zip curl libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
    python3 make sudo gcc g++ bc grep tofrodos python3-markdown libxml2-utils xsltproc zlib1g-dev python-is-python3 libc6-dev libtinfo6 \
    make repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd --fix-missing && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create build user and group and setup sudo without password
RUN groupadd -r build && useradd -r -g build -m -d /home/build build
RUN mkdir -p /workspace && chown -R build:build /workspace
RUN echo "build ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/build

# Create workspace directory
WORKDIR /workspace

# Download and install Neutron-Clang Toolchain
USER build

# Switch back to root user for copying files
USER root

# Copy the build scripts
RUN chown -R build:build /workspace/

# Switch to build user for the rest of operations
USER build

# Set working directory
WORKDIR /workspace

# Set default command
CMD ["/bin/bash"]
