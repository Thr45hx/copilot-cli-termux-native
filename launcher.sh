#!/data/data/com.termux/files/usr/bin/bash
# copilot — native Termux launcher (GitHub Copilot CLI, glibc Node SEA). No proot.
#
# Copilot CLI is a Node single-executable-app (glibc). Like Claude/OpenCode's Bun
# binaries: patchelf its interpreter to Termux's glibc loader and run it in place
# (it loads app.js + tree-sitter .wasm from beside itself, so keep the whole dir).
# The claude-resolvfix.so shim redirects /etc/resolv.conf for DNS and scrubs
# LD_PRELOAD/LD_LIBRARY_PATH so bionic child tools don't choke on glibc.
# Re-patchelfs after a self-update (which restores the /lib/ld-linux interpreter).
PREFIX="/data/data/com.termux/files/usr"
DIR="$HOME/agents/copilot"
BIN="$DIR/copilot"
GLD="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
PE="$PREFIX/glibc/bin/patchelf"
SHIM="$PREFIX/lib/claude-resolvfix.so"

[ -f "$BIN" ] || { echo "[copilot] binary not found at $BIN — reinstall." >&2; exit 1; }
[ "$(LD_PRELOAD= "$PE" --print-interpreter "$BIN" 2>/dev/null)" = "$GLD" ] || \
  LD_PRELOAD= "$PE" --set-interpreter "$GLD" "$BIN" 2>/dev/null
exec env LD_PRELOAD="$SHIM" LD_LIBRARY_PATH="$PREFIX/glibc/lib" \
     SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem" "$BIN" "$@"
