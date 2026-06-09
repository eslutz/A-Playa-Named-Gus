#!/bin/sh
set -eu

# Xcode Cloud checks out source only; the Xcode project is generated locally.
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "xcodegen is required to generate A Playa Named Gus.xcodeproj" >&2
    exit 69
  fi
fi

xcodegen generate
