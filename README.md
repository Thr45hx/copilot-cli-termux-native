# copilot-cli-termux-native
Run GitHub Copilot CLI (copilot) natively on Termux (aarch64) — no proot, no root. Node single-executable-app + patchelf'd interpreter to the Termux glibc loader + an LD_PRELOAD DNS shim (the Claude Code recipe). Pulls @github/copilot-linux-arm64 directly. One-command installer.
