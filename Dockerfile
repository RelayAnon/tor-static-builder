# Dockerfile for building static Tor libraries for Go embedding
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
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
    libssl-dev \
    libevent-dev \
    zlib1g-dev \
    libcap-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy build script
COPY build-tor-static.sh /build/

# Make script executable
RUN chmod +x /build/build-tor-static.sh

# Set environment variables for build
ENV BUILD_DIR=/build
ENV OUTPUT_DIR=/output

# Create output directory
RUN mkdir -p /output

# Default command runs the build script
CMD ["/build/build-tor-static.sh"]