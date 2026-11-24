# GTA VI (1.0.2.1, Xbox Series) on Linux/Proton — reproduction notes

Date: 2026-11-24. Host: Arch/CachyOS, Ryzen 7 3700X, 32 GB, **RTX 3070 (8 GB, 32-lane waves)**,
NVIDIA driver under Proton Experimental. Title: `game_scarlett_master.exe` 1.0.2.1,
build `b99f876b74d4a77f` (TitleID `7952987a`), Series X profile.

## Result

**The world renders under Linux/Proton.** Opening cutscene, scenery, HUD, pause menu and pad
input all work. Audio runs throughout. This is the first stack in this repository's history
to show the world rather than a black frame.

Frame rate is the remaining problem: **0.05–0.1 fps (10–18 s/frame)** on this machine. The
fork's author reports 2–4 fps on Windows (RTX 4070, 12 GB). The GPU is idle ~96 % of the
frame; the time is host-side copies and waits (see *Speed*).

Known limitations, inherited from the fork: everything in shadow is black (its
ray-traced bounce light and sun/lamp shadows do not run yet), and ray tracing is off.

## The three pieces that made it work

1. **[fxceless/victory-gta6](https://github.com/fxceless/victory-gta6) @ `6a2d9f9`** — a fork of
   upstream VIctory (`ffe310e` + 2 commits, 34,635 insertions over 65 files). It carries the
   world-rendering fixes: meshlet culling reading the right view kind, per-draw descriptor
   tables, light packed by compute read back through empty copies, fog/shadow-mask/hair/skinning
   shaders, named-mip gathers, rectangle lists, depth twins, and the speed/memory work.
2. **The DXC fallback for the indirect-argument clamp** (`patches/dxc-clamp-fallback.patch`
   in this repository). The fork still compiles its clamp with `D3DCompile`; Wine's
   `d3dcompiler_47` cannot compile it (`InterlockedMax` / store to a raw buffer are unsupported),
   so every indirect execution is dropped and the world draws nothing. The fallback compiles the
   same HLSL with DXC as `cs_6_0`.
3. **Microsoft DXC v1.9.2609**, Windows x64 `dxcompiler.dll` + `dxil.dll`, placed beside
   `victory.exe`. This is the same arrangement TuxBox uses on Linux/Proton.

Without (2) and (3) the fork presents black under Proton and then dies at the title's watchdog
(`+0x2215c35`, "GPU Loc Sig"). Its log shows why:

```
dropped 2656/frame  indirect kind 10: not bounded (no clamp, or arguments not 4-byte aligned)
dropped  537/frame  indirect kind 2:  not bounded
dropped  272/frame  indirect kind 1:  not bounded
dropped   68/frame  indirect kind 0:  not bounded
```

With them: `0` "no argument clamp" warnings, and at frame 4096
`draws=22144 drawn=22142 dispatches=4219 dispatched=4210`.

## First-time setup on Linux

1. **Steam, Proton and the runtime.** Install Steam, then from Library → Tools install
   **Proton Experimental** and **Steam Linux Runtime 4.0**. The wrapper below calls
   `SteamLinuxRuntime_4/_v2-entry-point` directly. Check both exist:

   ```sh
   ls "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton"
   ls "$HOME/.local/share/Steam/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point"
   ```

   If Steam is installed elsewhere, change `steam=` in the wrapper.

2. **Cross-compilation toolchain.** Linux builds the Windows executable:

   ```sh
   rustup toolchain install stable
   rustup target add x86_64-pc-windows-msvc
   cargo install cargo-xwin
   # a compiler and linker for the cross build
   sudo pacman -S clang lld        # Arch
   # sudo apt install clang lld    # Debian/Ubuntu
   ```

   `cargo-xwin` downloads the Windows SDK and CRT on the first build (set `XWIN_CACHE_DIR`
   to keep it somewhere specific). Verified with Rust 1.98.1; a newer stable should work.

3. **The game files.** Extract your own dump to a directory. Nothing from the game is
   included in this archive; the path can be read-only.

4. **The Proton prefix and `victory.toml`.** The first launch creates the prefix under
   `$work/compatdata`. To write the config beforehand, create it once:

   ```sh
   mkdir -p "$HOME/.local/share/victory-proton-test"
   ./run.sh cmd /c exit      # or: STEAM_COMPAT_DATA_PATH=... "$runtime" --verb=run -- "$proton" cmd /c exit
   ```

   then write `$HOME/.local/share/victory-proton-test/compatdata/pfx/drive_c/victory.toml`
   with the `[paths]` block below, using `Z:\...` paths for Linux directories.

5. **DXC.** Download the **Windows x64** release from
   <https://github.com/microsoft/DirectXShaderCompiler/releases> and put `dxcompiler.dll`
   and `dxil.dll` beside `victory.exe`. The Linux `dxc` binary is not enough: the runtime
   loads the DLLs inside the game process.

6. **The wrapper.** Copy `run.sh.example` to `run.sh`, edit the four paths at the top,
   `chmod +x run.sh`.

7. **First launch expectations.** The first run is cold: it builds 500–1,300 pipelines and
   the world appears after several minutes. Frame rate starts around 0.05–0.1 fps; later
   runs reuse the pipeline library and are faster. Create the capture directory before
   asking for captures, or every save logs `Path not found`.

## Build

Requirements: Rust with the `x86_64-pc-windows-msvc` target, `cargo-xwin` (plus its Windows SDK
cache), clang/lld. On Linux the whole thing cross-compiles; no Windows machine is needed.

```sh
git clone https://github.com/fxceless/victory-gta6
cd victory-gta6
git checkout 6a2d9f9

# apply the DXC fallback (from this repository's patches/ directory)
git apply /path/to/dxc-clamp-fallback.patch
# and, for runs longer than a few minutes, the title's watchdog hooks
git apply /path/to/watchdog-hooks.patch

cargo xwin build --profile diag --features diagnostics \
    -p victory --target x86_64-pc-windows-msvc --locked
```

Then put the compiler beside the executable:

```sh
# from https://github.com/microsoft/DirectXShaderCompiler/releases (v1.9.2609)
unzip dxc_2026_09_29.zip 'bin\x64\dxcompiler.dll' 'bin\x64\dxil.dll'
cp bin/x64/dxcompiler.dll bin/x64/dxil.dll \
   target/x86_64-pc-windows-msvc/diag/
```

`dxil.dll` is not optional: DXC loads it to validate/sign the DXIL.

## Run

Proton Experimental, a dedicated prefix, and `victory.toml` on `C:`:

```toml
[paths]
game_dir  = 'Z:\path\to\GTA6.Xbox.v1.0.2.1'
cache_dir = 'Z:\path\to\victory-data\cache'
data_dir  = 'Z:\path\to\victory-data\data'
test_titles = []
```

Copy `run.sh.example` to `run.sh`, set `repo`, `game`, `work` and `steam` at the top, and
`chmod +x run.sh`. It exports the four Proton variables that matter — `STEAM_COMPAT_DATA_PATH`,
`STEAM_COMPAT_INSTALL_PATH`, `STEAM_COMPAT_MOUNTS` (so the game and the build are visible in
the prefix) and `WINEDLLOVERRIDES='d3d12,d3d12core,dxgi=n'` — and runs the Windows executable
inside the runtime.

Launch:

```sh
export VICTORY_LOG=info
export VICTORY_NO_WATCHDOG=1
export VICTORY_SHADER_LOOP_LIMIT=4096
export VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains
# the gamepad-only account picker needs Enter presses
export VICTORY_KEYS=$(seq 20 5 300 | awk '{printf "%s:Enter,",$1}' | sed 's/,$//')

./run.sh ./target/x86_64-pc-windows-msvc/diag/victory.exe \
    run 'Z:\path\to\GTA6.Xbox.v1.0.2.1\game_scarlett_master.exe' --execute
```

`VICTORY_KEYS` may need adapting: on a fresh profile Enter alone can loop on the Legal Notices
screen, where Down selects "Next".

### Environment sets

Picture first (this is what produced the visible world):

```sh
VICTORY_LOG=info VICTORY_NO_WATCHDOG=1 VICTORY_SHADER_LOOP_LIMIT=4096
VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains
```

Then the fork's speed switches, off by default:

```sh
VICTORY_TEXTURE_NO_WAIT=1                 # the big one on this host
VICTORY_LATE_WAIT=3 VICTORY_RELAY=2 VICTORY_WIDE_BACK=1
VICTORY_CARD_BUFFERS_MIN_MB=1 VICTORY_CARD_BUFFERS_MB=1024
```

Evidence capture (the directory **must exist**, or every save logs `Path not found`):

```sh
mkdir -p /path/to/capture
VICTORY_CAPTURE=/path/to/capture VICTORY_DUMP_TARGETS=1 \
VICTORY_CAPTURE_FRAMES='3000,3600,4200'
```

## How to tell it worked

```
argument clamp: the system compiler refused it (...); trying DXC
```
must be followed by **no** `no argument clamp: indirect execution dropped` line, and the drop
summary must lose `not bounded`.

```
frame presented ... frame=4096 draws=22144 drawn=22142 dispatches=4219 dispatched=4210
```
`drawn` matching `draws` is the good state. Then the frame levels line should show content
rather than zeros, e.g. `levels=[105,119,118,119,118,0,0,1,0,1,1,128]`.

## Speed: where the time goes

From `VICTORY_LOG=info` frame lines on this host:

```
18,684 ms/frame = 14,069 preparing (copies 8,635 ms / 156 MB, textures 4,242 ms)
                + 686 GPU + 3,773 copy-back
write-watch askings of 1 ms or more: 774 a frame, 8,595 ms a frame
texture refreshes: 4,242 ms, of them 3,810 ms waiting for title memory to hold still
```

`VICTORY_TEXTURE_NO_WAIT=1` targets the 3.8 s remap wait exactly (read through the kernel, a
texture may arrive one frame late). Measured with it plus the relay switches on the same host:

```
texture refreshes   4,242 ms → 267–380 ms   (the remap wait is 0.0 ms)
frame time          10–18 s  → 1.4–8.8 s    (best 0.7 fps, typical 0.15–0.4 fps)
what remains        title copies 1.2–2.5 s, copy-back up to 5.7 s
```

The copy path is the next target; `VICTORY_JOIN_COPIES=1` joins adjacent title copies,
`VICTORY_CARD_BUFFERS_MIN_MB`/`VICTORY_CARD_BUFFERS_MB` move large copies to the card, and
`VICTORY_INPLACE` avoids copies by using title memory in place (first stage only).

Do **not** set `VICTORY_D3D12_DRED` for normal play: measured at ~2.5× cost in the world.

## Traps

- **Fresh data directory for scripted runs.** Once the title writes a save, scripted Enter picks
  "Continue" and it dies in ~40 s at `+0x164a298` (read `0x2c`) — a different failure that looks
  like a crash. Move `data/7952987A/saves` aside, or use a fresh `data_dir`.
- **Capture frames are presented-frame numbers**, which advance even while loading. The world
  starts around frame 4,000: captures at 3,000–4,200 are the loading key art, and frame 4,096
  already had 28,708 draws. Ask for 4,100 and later.
- **The title waits about 2 s for the GPU.** Frames longer than that eventually trip its
  "GPU Loc Sig" watchdog (we saw it at frame 7,232, right after a burst of new world
  pipelines was built). The pipeline library survives, so the next run starts warm and gets
  further — but keeping frames short matters more than any single pass.
- The first run is cold: 500–1,300 pipelines are built (the fork loads ~960 from its library,
  builds the rest). Later runs reuse them.
- The title's crash reporter tries to upload a minidump to `submit.backtrace.io`; the runtime
  blocks it. Run offline if you do not want the attempt at all.

### Keeping a run alive

The title ends its own process when it decides the GPU has stopped making progress: a
deliberate `mov dword [0], imm32` at `+0x23cf683`, called from `+0x2215c35`, about 6–8 minutes
after the world starts. The fork at `6a2d9f9` has **no** `VICTORY_NO_WATCHDOG` support, so the
variable is silently ignored there and every run dies that way.

`patches/watchdog-hooks.patch` adds the loader hooks from this repository: they check the
build's hash (`b99f876b74d4a77f`) and the exact bytes, then jump over the call and NOP the
deliberate fault. Set `VICTORY_NO_WATCHDOG=1` and the run keeps going.

Do **not** patch the watchdog thread's entry point instead. That was tried: it stops the kills,
but the title then never draws (0 shaders translated, 0 frames), because that thread also does
work the title needs at startup.

### Why runs went silent for ten minutes

The pipeline workers ran on Rust's default 2 MiB stack. On the world's largest mesh programs the
translator's recursion overflowed it:

```
thread 'victory-pipelines-2' has overflowed its stack
```

The worker died, the pipeline it was making never appeared, and the title waited for it forever:
the log stopped right after `host pipeline: making shaders=["mesh …"]`, CPU stayed high, and no
frame was presented. This is the stall that the title's own watchdog used to end with a crash.
Fixed in this tree by giving the workers 32 MiB (`pipeline/make.rs`, `stack_size(32 << 20)`).
A pipeline that is slow but succeeds now logs `a host pipeline took a second or more` with its
hashes.

### Driving a run to the end without a person

`scripts/auto-run.sh` is a supervisor: it launches the game, watches the log's mtime, and when a
run goes quiet for 150 s it reads the last `host pipeline: making` line, adds those shader hashes
to `auto-runs/skips.txt`, and starts again with `VICTORY_SKIP_PIPELINES` set from that file. Every
run appends its best frame and fps to `auto-runs/ledger.txt`; three runs without a new skip stop
the loop. Paths come from `REPO`, `EXE`, `GAME`, `WORK` and `RUNNER`.

The same pattern is how the ecosystem news is used: a five-minute watcher reports merged PRs and
open/closed issues across the fork, upstream, XCL, TuxBox and the other compatibility layers, so a
fix published there is visible here without a manual search.

### Measured on the merged stack (2026-11-25)

With the fork's 7 newer commits (`90228a7` lane masks, `d279e69` configurable pipeline
waits, …), the two pipeline-library fixes from `Pablo-Barros/VIctory#1683` (zeroed padding;
stop keeping the mesh pipelines D3D12 refuses to load), `NtReadVirtualMemory` for title reads,
the split-range watch fix and 128 MiB worker stacks:

- world frames: **0.2–0.4 fps**, 2.7–5.8 s/frame; copies 0.8–1.4 s, copy-back up to 1.4 s;
- `copied whole (memory not watched): 0.0 ms/frame` — the split-range fix works;
- the library now says once `refuses a mesh pipeline it just stored: mesh pipelines are
  compiled every run, none kept` and stops polluting itself, but those pipelines are still
  compiled each run (the host refuses to load them);
- **four compute programs still overflow a 128 MiB worker stack** — `55679a0547649d0b`,
  `afeea48bbb9913ad`, `e8c962358d862e3f`, `44a9625f01769f33` — which is unbounded recursion in
  the translator, not depth; they are seeded in `auto-runs/skips.txt`.

### Two test-method traps

- `VICTORY_COPY_MODE=plain` is a **timing mode only**. It `memcpy`s title memory without checking
  and faults on a reserved-but-uncommitted page (`ucrtbase` access violation, `read …: reserved,
  never committed`). It answers "how much of the frame is the copy wrapper" for a few frames; a
  full run must use the kernel path.
- `VICTORY_INPLACE=2` works on this host — the probe opened a 4 MiB window, placed a buffer and the
  GPU read 65536/65536 bytes equal — but the title's buffers are **view memory**, not private
  committed memory, so they are refused and only the probe window is placed. In-place is not the
  lever here until the title's allocation type is handled.

### Warnings that are expected

- `a pipeline creation method that is not implemented ... slot=0x1c8 / slot=0x218` — the title
  is asking for pipeline states it serialized offline at build time
  (`DeserializeGraphicsPipelineStateX` family; the GDK's `HlslCompile` ACO sample shows the
  `.packet.bin` + `.vs/.ps.bin` layout). Those payloads are **native RDNA 2 microcode**, so a
  PC GPU cannot use them. Victory answers `E_NOTIMPL`, the title falls back to building the
  pipeline from its shaders, and that fallback is the path that renders. OpenScarlett returns a
  placeholder PSO instead and skips those draws, which is worse for the picture. A few thousand
  of these lines at world entry are normal.
- `a stage of the ray-tracing structure builder, which is off` — expected while
  `VICTORY_BVH_BUILDER` is unset; this is also why everything in shadow is black.

## What did not work (so you do not repeat it)

- **Upstream/our `r12` branch**: menus and loading art only; the world stayed black because the
  branching/descriptor/shader fixes above were missing. Our own clamp, heap-cap and format fixes
  are correct and worth keeping, but they are not sufficient.
- **The fork without DXC**: black world, all indirect dropped, watchdog after a few minutes.
- **Forcing a single stand-in pixel shader on every draw** (`VICTORY_STAND_IN_ALL=1`, added in
  this repo): useful diagnostic (flat geometry, no text) but it does not fix the picture.
- **`#1020` rectangle geometry stage**: the fork already handles rectangle lists, so this was
  not needed on the working stack.

## References

- Fork: https://github.com/fxceless/victory-gta6 (README documents its fixes and switches).
- Upstream issues that describe the same walls: #841 (2560×1440 scene vs empty 3840×2160),
  #850 (cutscene black with audio), #1020 (rectangle lists), #1107 (WaveSize 64 refused on
  32-lane devices), #1133 (descriptor heap cap).
- XCL issue #662 (same title; the GPU frame-signal write never lands, then the "GPU Loc Sig"
  watchdog) and #1525 (wave-size refusals are a device-capability wall).
- TuxBox: `docs/PROJECTSCARLETT.md` for the DXC-beside-the-executable arrangement, and
  `runtime/d3d12/src/device/rectangle.rs` for the rectangle-list algorithm.

### World cost after the copy fixes (run of 2026-11-25 01:30, RTX 3070)

`VICTORY_WIDE_REFRESH=1` (a submission's refreshes on the worker threads),
512 MiB pipeline stacks, and the memcpy-per-committed-run copy:

- world frames: **0.3-0.5 fps**, 2.1-3.6 s/frame; about 400-3,400 draws;
- copies 1.1-2.1 s (of which guards 250-350 ms, write-watch asks ~0.5 s, the
  rest the small kernel copies: ~9,000 title copies of ~600 bytes a frame,
  where `VirtualQuery` costs ~0.6 ms and the kernel call ~6 us);
- copy-back 0.5-1.3 s for 17-28 MB (still the kernel path: the destination
  is view memory with holes, and a query per piece costs more than the
  write it would save);
- the card was about 7-14 % busy; the CPU is the frame.

Two things did **not** pay off and were reverted: a whole-range `memcpy`
(one `VirtualQuery` per copy made the frame 4 s slower), and capping the
texture cache at 5 GiB to make room for card-memory host copies (still
0 copies made; the 8/10 budget rule is not what starves them).

### Another launcher recipe (from a tester)

Proton-CachyOS Latest through `umu-run`, with `WINEDLLOVERRIDES=d3d12,d3d12core,d3dcompiler_47=n`
and vkd3d-proton built from master beside the exe (Proton's bundled copy
crashes RADV when the world loads), plus Microsoft's `d3dcompiler_47.dll`.
This tree runs Proton Experimental with Proton's bundled vkd3d-proton,
`VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains`, and Microsoft's
`dxcompiler.dll` + `dxil.dll` beside `victory.exe`. The difference is the
vkd3d-proton build and the compiler DLL; neither changes the frame's CPU
copies, which are what limit this host.
