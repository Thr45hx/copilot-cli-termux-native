# copilot-cli-termux-native

Run **GitHub Copilot CLI (`copilot`) natively on Termux** (Android · aarch64) — **no proot, no root.**

Copilot CLI ships as a **Node single-executable-app** — a glibc Node runtime bundled with its JS + tree-sitter grammars. `npm install -g @github/copilot` won't pull the arm64 binary on Termux (bionic libc matches neither the glibc nor musl gate), so this installer grabs the `@github/copilot-linux-arm64` package directly and runs it the same way we run Claude Code: patchelf its interpreter to Termux's glibc loader + an `LD_PRELOAD` DNS shim.

> Runtime only — no account data. First `copilot` run does GitHub device login (needs a Copilot subscription).

## How it works

| Piece | Role |
|-------|------|
| **Termux glibc repo** (`glibc`, `patchelf-glibc`, `binutils-glibc`) | glibc runtime + loader + patchelf under `$PREFIX/glibc` |
| **patchelf the interpreter** | The `copilot` Node SEA is `0x10000`-aligned + patchelf-clean, so we just repoint its interpreter to Termux's glibc loader (no align-fix). The launcher re-applies this after `copilot update`. |
| **`fix_resolv.c` → `claude-resolvfix.so`** | `LD_PRELOAD` shim: redirects `/etc/resolv.conf` reads to `$PREFIX/etc/resolv.conf` (Node reads it via libc, so the shim catches it) and scrubs `LD_PRELOAD`/`LD_LIBRARY_PATH` so bionic child tools don't choke on glibc. Shared with [claude-code-termux-native](https://github.com/Thr45hx/claude-code-termux-native). |

No root, no proot, no module — DNS works immediately.

## Requirements
- Termux on **aarch64 / arm64**
- Internet on first run, and a **GitHub Copilot subscription**

## Install
```bash
git clone https://github.com/Thr45hx/copilot-cli-termux-native
cd copilot-cli-termux-native
bash install.sh
```
or one-shot:
```bash
curl -fsSL https://raw.githubusercontent.com/Thr45hx/copilot-cli-termux-native/main/install.sh | bash
```
Then:
```bash
copilot          # first run: GitHub device login
```

## Layout
```
~/agents/copilot/
├── copilot       # Node SEA (interpreter patchelf'd)
├── app.js, *.wasm, …   # runtime assets (loaded from beside the binary)
└── launcher.sh   # ← $PREFIX/bin/copilot symlinks here
$PREFIX/lib/claude-resolvfix.so   # DNS shim (shared)
```

## Files
- `install.sh` — one-command installer (pulls `@github/copilot-linux-arm64` straight from npm)
- `launcher.sh` → `$PREFIX/bin/copilot`
- `fix_resolv.c` — the DNS shim source
- `uninstall.sh`

## Uninstall
```bash
bash uninstall.sh
```

---

Unofficial — not affiliated with GitHub. Requires a GitHub Copilot subscription. Provided as-is, no warranty.
