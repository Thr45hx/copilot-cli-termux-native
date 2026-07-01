#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — GitHub Copilot CLI, native on Termux (aarch64). No proot, no root.
#
# Copilot CLI is a Node single-executable-app (glibc Node runtime + JS + tree-
# sitter .wasm). `npm i -g @github/copilot` won't pull the arm64 binary on Termux
# (bionic libc matches neither the glibc nor musl gate), so we fetch the
# @github/copilot-linux-arm64 package directly, patchelf its interpreter to
# Termux's glibc loader, and use an LD_PRELOAD DNS shim. Same recipe as Claude.
#
set -euo pipefail
say(){ printf '\033[1;34m[copilot-native]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[copilot-native] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
GL="$PREFIX/glibc"; GLD="$GL/lib/ld-linux-aarch64.so.1"
SHIM="$PREFIX/lib/claude-resolvfix.so"; RESOLV="$PREFIX/etc/resolv.conf"
DIR="$HOME_DIR/agents/copilot"
PKG="@github/copilot-linux-arm64"
RAW="https://raw.githubusercontent.com/Thr45hx/copilot-cli-termux-native/main"

[ -d "$PREFIX" ] || die "Not a Termux environment."
case "$(uname -m)" in aarch64|arm64) ;; *) die "arm64/aarch64 only (found $(uname -m)).";; esac

SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
need=0; for f in launcher.sh fix_resolv.c; do [ -f "$SRC/$f" ] || need=1; done
if [ "$need" = 1 ]; then
  command -v curl >/dev/null || die "curl required to fetch sources."
  SRC="$(mktemp -d)"; say "Fetching source files…"
  for f in launcher.sh fix_resolv.c; do curl -fsSL "$RAW/$f" -o "$SRC/$f" || die "fetch $f failed"; done
fi

say "Installing base packages (clang curl tar ca-certificates)…"
pkg update -y >/dev/null 2>&1 || true
pkg install -y clang curl tar ca-certificates >/dev/null || die "pkg install failed."

if [ ! -f "$GLD" ] || [ ! -x "$GL/bin/patchelf" ] || [ ! -x "$GL/bin/ld" ]; then
  say "Enabling the Termux glibc repo + runtime…"
  pkg install -y glibc-repo >/dev/null || die "glibc-repo failed."
  pkg update -y >/dev/null 2>&1 || true
  pkg install -y glibc patchelf-glibc binutils-glibc >/dev/null || die "glibc install failed."
fi
[ -f "$GLD" ] || die "glibc loader missing: $GLD"

if [ ! -f "$SHIM" ]; then
  say "Building DNS shim (claude-resolvfix.so)…"
  b="$(mktemp -d)"; cp "$SRC/fix_resolv.c" "$b/"
  ( cd "$b"
    clang --target=aarch64-linux-gnu -fPIC -O2 -fno-stack-protector -c fix_resolv.c -o fix_resolv.o
    "$GL/bin/ld" -shared -o libclaude-resolvfix.so fix_resolv.o -L"$GL/lib" -l:libc.so.6 -l:libdl.so.2
  ) || { rm -rf "$b"; die "shim build failed."; }
  install -m644 "$b/libclaude-resolvfix.so" "$SHIM"; rm -rf "$b"
fi
if [ ! -s "$RESOLV" ] || ! grep -q '^nameserver' "$RESOLV" 2>/dev/null; then
  mkdir -p "$(dirname "$RESOLV")"; printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$RESOLV"
fi

say "Resolving latest $PKG from npm…"
url="$(curl -fsSL "https://registry.npmjs.org/$PKG/latest" | grep -o '"tarball":"[^"]*"' | head -1 | sed 's/"tarball":"//; s/"$//')"
[ -n "$url" ] || die "could not resolve package tarball."
say "Downloading $url…"
t="$(mktemp -d)"
curl -fsSL "$url" -o "$t/pkg.tgz" || { rm -rf "$t"; die "download failed."; }
tar xzf "$t/pkg.tgz" -C "$t" || { rm -rf "$t"; die "extract failed."; }
[ -f "$t/package/copilot" ] || { rm -rf "$t"; die "copilot binary not in package."; }
mkdir -p "$DIR"
cp -a "$t/package/." "$DIR/"; rm -rf "$t"

"$GL/bin/patchelf" --set-interpreter "$GLD" "$DIR/copilot"
install -m755 "$SRC/launcher.sh" "$DIR/launcher.sh"
ln -sf "$DIR/launcher.sh" "$PREFIX/bin/copilot"

say "Verifying…"
if copilot --version >/dev/null 2>&1; then say "Installed $(copilot --version 2>/dev/null | head -1) — native, no proot."; else say "Installed; run 'copilot'."; fi
echo
say "Auth:  copilot   (first run does GitHub device login; needs a Copilot subscription)."
