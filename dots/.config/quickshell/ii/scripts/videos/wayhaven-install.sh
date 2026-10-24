#!/usr/bin/env bash
# Installs the wayhaven video wallpaper daemon into ~/.local/bin.
# On Arch it normally comes from the illogical-impulse-wayhaven package (./setup install);
# this is the fallback the shell offers when it is missing.
#
# 1. Prebuilt binary from the GitHub release (checksum-verified, smoke-tested)
# 2. Otherwise build that same tag from source with cargo
#
# Usage: wayhaven-install.sh [--quiet]   (exit 0 = installed)

set -uo pipefail

WAYHAVEN_REPO="qvap/wayhaven"
WAYHAVEN_VERSION="v0.1.0" # Keep in sync with sdata/dist-arch/illogical-impulse-wayhaven/PKGBUILD

BIN_DIR="$HOME/.local/bin"
DEST="$BIN_DIR/wayhaven"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wayhaven"
APP_NAME="Wallpaper switcher"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

notify() { # summary body [urgency]
    echo "[wayhaven-install] $1: $2" >&2
    [[ $QUIET == 1 ]] && return 0
    notify-send -a "$APP_NAME" -u "${3:-normal}" "$1" "$2" 2>/dev/null || true
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The binary must at least start: catches a glibc that is too old or a missing libmpv
smoke_test() {
    "$1" --version >/dev/null 2>&1
}

install_bin() {
    mkdir -p "$BIN_DIR"
    # Replace atomically, a running daemon keeps its old inode
    install -m755 "$1" "$DEST.new" && mv -f "$DEST.new" "$DEST"
}

try_prebuilt() {
    [[ "$(uname -m)" == "x86_64" ]] || return 1
    command -v curl >/dev/null || return 1
    local name="wayhaven-$WAYHAVEN_VERSION-x86_64-linux"
    local base="https://github.com/$WAYHAVEN_REPO/releases/download/$WAYHAVEN_VERSION"
    curl -fsSL --retry 2 -o "$WORK/$name.tar.gz" "$base/$name.tar.gz" || return 1
    curl -fsSL --retry 2 -o "$WORK/$name.tar.gz.sha256" "$base/$name.tar.gz.sha256" || return 1
    (cd "$WORK" && sha256sum -c --status "$name.tar.gz.sha256") || {
        notify "wayhaven: checksum mismatch" "The downloaded release is corrupted, building from source instead." critical
        return 1
    }
    tar -C "$WORK" -xzf "$WORK/$name.tar.gz" || return 1
    smoke_test "$WORK/$name/wayhaven" || {
        echo "[wayhaven-install] prebuilt binary does not run here: $("$WORK/$name/wayhaven" --version 2>&1 | head -1)" >&2
        return 1
    }
    install_bin "$WORK/$name/wayhaven"
}

try_source() {
    if ! command -v cargo >/dev/null || ! command -v git >/dev/null; then
        notify "wayhaven: can't build" "No prebuilt binary fits this system and cargo/git are missing. Install rust and mpv (libmpv), then try again." critical
        return 1
    fi
    notify "Building wayhaven" "No prebuilt binary fits this system, compiling from source. This takes a minute or two…"
    local src="$CACHE_DIR/src"
    rm -rf "$src"
    mkdir -p "$CACHE_DIR"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$WAYHAVEN_VERSION" \
        "https://github.com/$WAYHAVEN_REPO.git" "$src" 2>"$CACHE_DIR/build.log" || {
        notify "wayhaven: download failed" "Could not fetch the sources, see $CACHE_DIR/build.log" critical
        return 1
    }
    (cd "$src" && cargo build --release --locked) >>"$CACHE_DIR/build.log" 2>&1 || {
        notify "wayhaven: build failed" "See $CACHE_DIR/build.log (libmpv development files are required)." critical
        return 1
    }
    smoke_test "$src/target/release/wayhaven" || return 1
    install_bin "$src/target/release/wayhaven"
    rm -rf "$src"
}

notify "Installing wayhaven" "Downloading the video wallpaper engine $WAYHAVEN_VERSION from github.com/$WAYHAVEN_REPO…"
if try_prebuilt || try_source; then
    notify "wayhaven installed" "$("$DEST" --version) → $DEST"
    exit 0
fi
notify "wayhaven: installation failed" "Video wallpapers stay unavailable. See github.com/$WAYHAVEN_REPO for manual installation." critical
exit 1
