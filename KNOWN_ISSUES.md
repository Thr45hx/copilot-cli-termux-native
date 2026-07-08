## Voice mode (`/voice`) does not work on Termux/aarch64

**Symptom:**

```
Voice mode is not supported on linux-arm64. Supported platforms: win32-x64, win32-arm64, linux-x64, darwin-arm64.
```

**Root cause (confirmed by reading the unpacked source, not just the error message):**

The error string interpolates `${process.platform}-${process.arch}` directly — on Termux/Android,
Node reports `platform=linux`, `arch=arm64`, so it always prints "linux-arm64". This is real
environment info, not a special exclusion category.

The actual gate is a hardcoded 4-entry platform remap table baked into
`voice-installer.worker.js` / `voice-engine.worker.js` / `voice-server.js` (used to build the
download URL for Foundry Local's voice model artifacts):

```js
{"win32-x64":"win-x64","win32-arm64":"win-arm64","linux-x64":"linux-x64","darwin-arm64":"osx-arm64"}
```

`linux-arm64` simply isn't a key. Microsoft/GitHub's CI targets for Foundry Local's voice
artifacts are Windows/Mac/x64-Linux, not ARM Linux hosts — this looks like an unpublished
combination, not an architectural block.

**What's NOT missing:** the lower-level native N-API binding already ships a linux-arm64
prebuild — `foundry-local-sdk/prebuilds/linux-arm64/foundry_local_napi.node` is present in
`node_modules` out of the box. So the JS↔native bridge is already arm64-Linux-capable; only the
downloadable voice model/runtime artifact bundle is missing for that key.

**Possible future patch (not started):**

1. Check whether Microsoft ever published a linux-arm64 (or arch-agnostic) Foundry Local voice
   artifact bundle anywhere, even unlisted, and just point the installer's URL table at it.
2. If not, swap the model source entirely — patch `voice-installer.worker.js`'s manifest to fetch
   an open-source STT model (whisper.cpp / faster-whisper, quantized for ORT or GGML) instead of
   Foundry Local's. The native NAPI binding stays; only the artifact + the request/response shaping
   in the `/voice` glue code would need to match Foundry Local's expected session/transcript shape,
   or be re-wired to a different backend entirely.
3. This project already has a working from-source ONNX Runtime build for this exact
   Termux/aarch64 target (`~/agents/build/ort-src/onnxruntime`) plus a custom NPU execution
   provider (`onnx-ep-tensor-g4`) — the hard part (ORT running natively here) is solved territory,
   so option 2 is a real, scoped patch, not new R&D.

**Status:** documented only. Not attempted yet — Pixel-Cli already covers voice
(mic → transcribe → Gemma → Qwen3-TTS) for this device, so this isn't urgent.
