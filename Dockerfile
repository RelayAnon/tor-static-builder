# Dockerfile for building static Tor libraries for Go embedding
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
# Note: We build all libraries from source, but keep some -dev packages
# as they may be needed during the build process
RUN apt-get update && apt-get install -y \
    build-essential \
    automake \
    autoconf \
    libtool \
    pkg-config \
    git \
    wget \
    curl \
    python3 \
    python3-dev \
    ca-certificates \
    # Cross-compilation tools for ARM64
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy build script
COPY build-tor-static.sh /build/

# Make script executable
RUN chmod +x /build/build-tor-static.sh

# Set environment variables for build
# Note: The build script will append /$ARCH to these paths automatically
# (e.g., /build/amd64 or /build/arm64)
ENV BUILD_DIR=/build
ENV OUTPUT_DIR=/output
ENV ARCH=amd64

# Create output directory
RUN mkdir -p /output

# Default command runs the build script
CMD ["/build/build-tor-static.sh"]