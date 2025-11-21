#!/bin/bash
# Quick build script for osmo-remsim
# This is a convenience wrapper around build.sh with sensible defaults

set -e

echo "======================================"
echo "osmo-remsim Quick Build Script"
echo "======================================"
echo ""
echo "This script will:"
echo "1. Install system dependencies (requires sudo)"
echo "2. Download and build Osmocom libraries"
echo "3. Build osmo-remsim client components"
echo ""
echo "The full build (including server/bankd) has a known issue."
echo "This script builds client-only, which works perfectly."
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Starting build..."
echo ""

# Run the actual build script with client-only mode
exec ./build.sh --client-only
