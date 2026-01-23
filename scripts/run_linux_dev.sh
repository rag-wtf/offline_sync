#!/bin/bash

# Flutter development runner for Linux
# This script builds and runs the app without requiring sudo

echo "Building Flutter app..."
flutter build linux --debug --target lib/main_development.dart

if [ $? -eq 0 ]; then
    echo "Build successful! Running app..."
    ./build/linux/x64/debug/bundle/offline_sync
else
    echo "Build failed!"
    exit 1
fi
