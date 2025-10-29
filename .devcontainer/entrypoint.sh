#!/bin/bash
set -e

echo "Installing Python packages..."
pip install --quiet --upgrade pip
pip install --quiet -e .
pip install --quiet -r requirements.txt
echo "✅ Packages installed"

echo "Starting container..."
exec "$@"
