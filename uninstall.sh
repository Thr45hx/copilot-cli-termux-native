#!/data/data/com.termux/files/usr/bin/bash
#
# uninstall.sh — remove the native Copilot launcher + install dir.
# Leaves glibc, the shared DNS shim, and your Copilot config/auth.
#
set -euo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
say(){ printf '\033[1;34m[copilot-native]\033[0m %s\n' "$*"; }

say "Removing launcher symlink…"; rm -f "$PREFIX/bin/copilot"
say "Removing install dir ($HOME_DIR/agents/copilot)…"; rm -rf "$HOME_DIR/agents/copilot"
say "Left intact: glibc, the shared DNS shim, and your Copilot config/auth."
say "To remove config too:  rm -rf ~/.config/copilot ~/.copilot"
