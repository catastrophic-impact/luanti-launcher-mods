#!/bin/sh
# install.sh - set up the build environment and build the Luanti Launcher + a portable release folder.
#
#   ./install.sh               everything: box, tools, npm install, tests, AppImage, release/ folder
#   ./install.sh setup         only the distrobox + Node + npm install
#   ./install.sh build         only tests + AppImage (box must exist)
#   ./install.sh release       only assemble release/ from the last build
#
# What it does:
#   1. creates the distrobox "luanti-box" (Ubuntu 22.04) with its OWN home folder ~/boxes/luanti-box (nothing is written to your real home)
#   2. installs the build tools in the box (apt packages, Node 20.18.1 into the box home) and runs `npm install` in launcher/
#   3. runs the launcher tests and `npm run dist` (-> launcher/dist/LuantiLauncher-<version>-x86_64.AppImage)
#   4. collects release/: the AppImage, mods/ (each mod in its own folder), LICENSE, CREDITS.md, README.txt
# Safe to run again: an existing box is reused, finished steps are skipped or repeated harmlessly.
# Needs on the host: distrobox + podman (or docker). Override with LUANTI_BOX=<name> and LUANTI_BOX_HOME=<dir>.
set -eu

# From a flatpak sandbox (VS Code) run on the host instead.
if [ -n "${FLATPAK_ID:-}" ] && [ -z "${INSTALL_ON_HOST:-}" ]; then
  exec flatpak-spawn --host env INSTALL_ON_HOST=1 "$0" "$@"
fi

ROOT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BOX=${LUANTI_BOX:-luanti-box}
BOX_HOME=${LUANTI_BOX_HOME:-$HOME/boxes/$BOX}
IMAGE=docker.io/library/ubuntu:22.04
NODE_VER=20.18.1
NODE_DIR=node-v$NODE_VER-linux-x64
STEP=${1:-all}

say() { printf '\n== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
inbox() { distrobox enter "$BOX" -- sh -c "$1"; }

setup() {
  command -v distrobox >/dev/null 2>&1 || die "distrobox is not installed (https://distrobox.it)."
  command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || die "podman (or docker) is not installed."

  say "Distrobox '$BOX' with its own home $BOX_HOME"
  if distrobox list 2>/dev/null | awk -F'|' 'NR>1 {gsub(/ /,"",$2); print $2}' | grep -qx "$BOX"; then
    echo "already exists, reusing it"
  else
    mkdir -p "$BOX_HOME"
    distrobox create --name "$BOX" --image "$IMAGE" --home "$BOX_HOME" --yes
  fi

  say "System packages (inside the box)"
  inbox "sudo apt-get update -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils unzip rsync git \
    libgtk-3-0 libnss3 libatk-bridge2.0-0 libcups2 libdrm2 libgbm1 libasound2 libxss1 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxkbcommon0 libpango-1.0-0 libcairo2"

  say "Node $NODE_VER (inside the box home)"
  inbox "set -e; cd \"\$HOME\"
    if [ -x $NODE_DIR/bin/node ]; then echo 'already installed'; else
      curl -fsSLO https://nodejs.org/dist/v$NODE_VER/$NODE_DIR.tar.xz
      curl -fsSLO https://nodejs.org/dist/v$NODE_VER/SHASUMS256.txt
      grep \" $NODE_DIR.tar.xz\$\" SHASUMS256.txt | sha256sum -c -
      tar xf $NODE_DIR.tar.xz && rm -f $NODE_DIR.tar.xz SHASUMS256.txt
    fi"

  say "npm install (launcher/)"
  inbox "export PATH=\$HOME/$NODE_DIR/bin:\$PATH; cd '$ROOT/launcher' && npm install"
}

build() {
  say "Launcher tests"
  inbox "export PATH=\$HOME/$NODE_DIR/bin:\$PATH; cd '$ROOT/launcher' && npm test"
  say "AppImage (npm run dist)"
  inbox "export PATH=\$HOME/$NODE_DIR/bin:\$PATH; cd '$ROOT/launcher' && npm run dist"
}

release() {
  say "release/ folder"
  APP=$(ls "$ROOT"/launcher/dist/LuantiLauncher-*-x86_64.AppImage 2>/dev/null | sort | tail -n 1 || true)
  [ -n "$APP" ] || die "no AppImage in launcher/dist/ - run ./install.sh build first."
  rm -rf "$ROOT/release"
  mkdir -p "$ROOT/release/mods"
  cp "$APP" "$ROOT/release/"
  for m in "$ROOT"/mods/*/; do cp -r "${m%/}" "$ROOT/release/mods/"; done
  cp "$ROOT/LICENSE" "$ROOT/CREDITS.md" "$ROOT/release/"
  cat > "$ROOT/release/README.txt" <<'TXT'
Luanti Launcher (portable)

1. Start the AppImage (it may need to be made executable: chmod +x LuantiLauncher-*.AppImage).
   On systems that are not SteamOS it needs libfuse2.
2. The launcher keeps its settings next to itself (launcher-data/). Nothing is written to your home folder.
3. mods/ holds the mods, each in its own folder. The launcher's Updates tab installs and updates them for Luanti.
   To add your own mods use "Open mods folder" in the launcher.
Licenses: LICENSE and CREDITS.md.
TXT
  chmod +x "$ROOT/release/$(basename "$APP")"
  echo "release/:"; ls -1 "$ROOT/release" | sed 's/^/  /'; echo "  mods/: $(ls -1 "$ROOT/release/mods" | wc -l) mods"
}

case "$STEP" in
  all) setup; build; release ;;
  setup) setup ;;
  build) build ;;
  release) release ;;
  *) sed -n 2,13p "$0"; exit 2 ;;
esac
say "done"
