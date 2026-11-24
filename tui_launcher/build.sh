#!/bin/sh
# Builds the portable launcher in the Ubuntu 22.04 distrobox: static binaries (CGO off) = no glibc or other runtime dependency.
# Usage: ./build.sh   (from anywhere; runs the build on the host's distrobox if started from the VS Code sandbox)
if [ -n "$FLATPAK_ID" ]; then exec flatpak-spawn --host "$(readlink -f "$0")" "$@"; fi
DIR="$(cd "$(dirname "$0")" && pwd)"
distrobox enter luanti-box -- sh -c "cd '$DIR' && export PATH=\$HOME/go/bin:\$PATH GOPATH=\$HOME/gopath CGO_ENABLED=0 &&
  go vet ./... && go test ./... &&
  GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o luanti-launcher-linux-amd64 . &&
  GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o luanti-launcher-linux-arm64 . &&
  ls -la luanti-launcher-*"
