# VIctory on Linux — one guide

This tree runs **Grand Theft Auto VI (Xbox Series dump, 1.0.2.1)** under
**Linux + Proton** with **VIctory**, the compatibility layer that plays the
console build from files you supply. It is a fork of
[Marvisak/VIctory](https://github.com/Marvisak/VIctory) with Linux/Proton and
speed fixes.

**It contains no game files.** You need your own dump.
Not affiliated with Rockstar Games or Take-Two.

**This is the canonical repository for the work**: branches, the guide,
`findings.md`, the supervisor and the watcher all live here
(`github.com/meeyao/VIctory`, branch `linux-findings`). The fork
`meeyao/victory-gta6` is kept only as a mirror for the pull request to the
upstream fork.

---

## Where it stands (2026-11-25)

| | |
|---|---|
| Boot, menus, loading art | works, ~30 fps |
| The world | **renders**: Lucia, scenery, low-poly geometry, textures |
| World frame rate on this PC | **0.3–0.5 fps** (2–6 s a frame), RTX 3070, Ryzen 7 3700X |
| 30 fps | **not reached, and not reachable with the current design** |
| What limits it | the CPU, not the GPU (7–14 % busy): ~9,000 small copies from title memory, ~9 GB of write-watch scans, and a 20–50 MB copy-back every frame |

That last row is the honest answer to "why is it so slow". The console shares
one memory between CPU and GPU; on a PC every GPU-visible buffer is copied.
Making the hot buffers GPU-resident (or opening title memory as a D3D12 heap)
is the only route to 30 fps — see `findings.md`, "What upstream has that this
tree does not".

---

## What you need

- A Linux PC with an NVIDIA or AMD GPU (tested: RTX 3070, driver 595+, Mesa/RADV)
- Steam + **Proton Experimental** installed
- Rust with `cargo-xwin`: `cargo install cargo-xwin`, plus Rust 1.98+
- Your game dump at a path like `/mnt/xp/GTA6.Xbox.v1.0.2.1-CYBERLEEK/`
- Microsoft **`dxcompiler.dll` + `dxil.dll`** next to `victory.exe`. Without
  them the indirect-argument clamp and the card compare cannot compile and
  the world stays black (Wine's `d3dcompiler_47` cannot compile them).

## Build

```bash
export XWIN_ARCH=x86_64 XWIN_CACHE_DIR="$HOME/.cache/victory-xwin-x64"
CARGO_TARGET_DIR="$PWD/target-fork" \
  cargo +1.98.1 xwin build --profile diag --features diagnostics \
  -p victory --target x86_64-pc-windows-msvc --locked
```

The exe lands in `target-fork/x86_64-pc-windows-msvc/diag/victory.exe`.

## Configure once

Write this beside your Proton prefix (the launcher below uses
`~/.local/share/victory-proton-test`):

`~/.local/share/victory-proton-test/compatdata/pfx/drive_c/victory.toml`

```toml
game  = 'Z:\mnt\xp\GTA6.Xbox.v1.0.2.1-CYBERLEEK\game_scarlett_master.exe'
cache = 'C:\victory-cache'
data  = 'C:\victory-data'
```

## Run once

```bash
VICTORY_LOG=info \
VICTORY_NO_WATCHDOG=1 \
VICTORY_SHADER_LOOP_LIMIT=256 \
VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains \
VICTORY_TEXTURE_NO_WAIT=1 \
VICTORY_LATE_WAIT=3 VICTORY_RELAY=2 \
VICTORY_WIDE_BACK=1 VICTORY_JOIN_COPIES=1 \
VICTORY_CARD_BUFFERS_MIN_MB=1 VICTORY_CARD_BUFFERS_MB=1024 \
VKD3D_SHADER_CACHE_PATH="$HOME/.cache/victory-vkd3d" \
VKD3D_CONFIG=ignore_shared_fence \
proton runinprefix <path-to-victory.exe> run \
  'Z:\mnt\xp\GTA6.Xbox.v1.0.2.1-CYBERLEEK\game_scarlett_master.exe' --execute
```

The world starts around frame 3,500–4,000; the picture on screen stays on the
loading art until ~6,500. Add `VICTORY_CAPTURE_FRAMES='6500,7200'` to save
screenshots of the first world frame.

### Never kill it by name

`pkill -f game_scarlett_master.exe` also matches the launcher's own command
line and kills the launcher. Kill the process-group id instead.

---

## The autonomous loop

Three pieces, all already running on this machine:

1. **`scripts/auto-run.sh`** (the "supervisor") — starts a run, watches the
   log, and when it stalls records the last pipeline it was compiling in
   `auto/skips.txt` and restarts. Each run writes one line to
   `auto/ledger.txt` with the build, the frame, the fps and the skips.
2. **`scripts/auto-upkeep.sh`** — every 15 minutes: restart the supervisor if
   it stopped, keep the four newest run folders, cap the log at 50 MB.
3. **The repo watcher** — every 5 minutes it reads the GitHub projects this
   work depends on (upstream VIctory, XCL, TuxBox, Xbox2Windows, five-star,
   OpenScarlett, palmetto, the Linux fork) and reports only changes that
   could move *this* run: copies, watches, pipelines, mesh, Proton/vkd3d,
   device loss.

Check it:

```bash
tail -5 auto/ledger.txt          # one line per run
grep 'fps,' auto/run-1.log | tail -3
```

Add a run by hand: `bash scripts/auto-run.sh`. Stop the loop by killing the
`bash /tmp/opencode/victory-loop.sh` process (not the game by name).

### What the loop has already proved

- The pipeline library now keeps **mesh** pipelines (they need a
  `PRIMITIVE_TOPOLOGY` subobject). Before: 565 recompiled every boot and
  `dropped 1098` draws; after: `made=0` on the next boot.
- Card-memory host copies are made (97 copies, 941 MB) once the compare is
  compiled with DXC instead of Wine's `d3dcompiler_47`.
- The copy fast path uses `memcpy` for every committed run of pages and the
  kernel only for holes.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Black world | `dxcompiler.dll` + `dxil.dll` beside the exe; check `VICTORY_LOG=info` for "no host pipeline" |
| Hangs ~30 s after the first frame, kill at `+0x23cf683` | `VKD3D_CONFIG=ignore_shared_fence` (vkd3d-proton + shared fences) |
| Every boot recompiles the same shaders | keep one `victory.exe`; the shader cache is keyed to the build's hash |
| A run ends in 3 minutes with exit code 3 | a shader that RADV rejects; the log names it ("does not translate") |
| Stalls after `host pipeline: making` | that shader is now skipped; the supervisor records its hash automatically |

---

## Where the details live

- **`findings.md`** — measured results, what was tried and rejected, and the
  upstream work this tree does not have yet.
- Upstream: [Marvisak/VIctory](https://github.com/Marvisak/VIctory).
- The Linux fork this started from:
  [fxceless/victory-fork](https://github.com/fxceless/victory-fork).
- Linux/Proton report with two world GPU-fault fixes:
  [VIctory #844](https://github.com/Marvisak/VIctory/issues/844).
