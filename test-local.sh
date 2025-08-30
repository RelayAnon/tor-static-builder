#!/bin/bash
# Quick test script to verify the build works locally (without Docker)

set -e

echo "Testing Tor static build locally..."

# Create test directories
TEST_DIR="/tmp/tor-static-test-$$"
mkdir -p "$TEST_DIR/build"
mkdir -p "$TEST_DIR/output"

echo "Test directory: $TEST_DIR"

# Run the build script with test directories
BUILD_DIR="$TEST_DIR/build" OUTPUT_DIR="$TEST_DIR/output" ./build-tor-static.sh

# Check results
echo ""
echo "Checking output files..."
if [ -f "$TEST_DIR/output/lib/libtor.a" ]; then
    echo "✓ libtor.a created successfully"
    ls -lh "$TEST_DIR/output/lib/"
else
    echo "✗ Build failed - libtor.a not found"
    exit 1
fi

echo ""
echo "Test complete! Cleaning up..."
rm -rf "$TEST_DIR"

echo "Success! The build script works correctly."