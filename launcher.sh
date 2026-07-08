#!/data/data/com.termux/files/usr/bin/bash
# copilot — native Termux launcher (GitHub Copilot CLI, glibc Node SEA). No proot.
#
# Copilot CLI is a Node single-executable-app (glibc). Like Claude/OpenCode's Bun
# binaries: patchelf its interpreter to Termux's glibc loader and run it in place
# (it loads app.js + tree-sitter .wasm from beside itself, so keep the whole dir).
# The claude-resolvfix.so shim redirects /etc/resolv.conf for DNS and scrubs
# LD_PRELOAD/LD_LIBRARY_PATH so bionic child tools don't choke on glibc.
# Re-patchelfs after a self-update (which restores the /lib/ld-linux interpreter).
#
# copilot-sea-exec.so fixes the in-app `/update`: after updating, Copilot renames
# the fresh binary over process.execPath (stock /lib/ld-linux interpreter, missing
# in Termux) and auto-respawns it raw — bypassing the patchelf above, so the kernel
# reports "spawn <...>/copilot ENOENT". This shim interposes exec/posix_spawn and
# redirects the copilot self-exec through Termux's glibc loader, re-injecting the
# loader env the DNS shim scrubs. Config is passed via the COPILOT_SEA_* vars below.
PREFIX="/data/data/com.termux/files/usr"
DIR="$HOME/agents/copilot"
BIN="$DIR/copilot"
GLD="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
PE="$PREFIX/glibc/bin/patchelf"
SHIM="$PREFIX/lib/claude-resolvfix.so"
EXECSHIM="$PREFIX/lib/copilot-sea-exec.so"
[ -f "$EXECSHIM" ] && PRELOAD="$EXECSHIM:$SHIM" || PRELOAD="$SHIM"

[ -f "$BIN" ] || { echo "[copilot] binary not found at $BIN — reinstall." >&2; exit 1; }
[ "$(LD_PRELOAD= "$PE" --print-interpreter "$BIN" 2>/dev/null)" = "$GLD" ] || \
  LD_PRELOAD= "$PE" --set-interpreter "$GLD" "$BIN" 2>/dev/null
exec env LD_PRELOAD="$PRELOAD" LD_LIBRARY_PATH="$PREFIX/glibc/lib" \
     SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem" \
     COPILOT_SEA_BIN="$BIN" COPILOT_SEA_LOADER="$GLD" \
     COPILOT_SEA_LIBPATH="$PREFIX/glibc/lib" COPILOT_SEA_PRELOAD="$PRELOAD" \
     COPILOT_SEA_SSL="$PREFIX/etc/tls/cert.pem" "$BIN" "$@"
