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

## Build

Requirements: Rust with the `x86_64-pc-windows-msvc` target, `cargo-xwin` (plus its Windows SDK
cache), clang/lld. On Linux the whole thing cross-compiles; no Windows machine is needed.

```sh
git clone https://github.com/fxceless/victory-gta6
cd victory-gta6
git checkout 6a2d9f9

# apply the DXC fallback (from this repository's patches/ directory)
git apply /path/to/dxc-clamp-fallback.patch

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
game_dir  = 'Z:\mnt\xp\GTA6.Xbox.v1.0.2.1-CYBERLEEK'
cache_dir = 'Z:\mnt\ecliptica\victory-data\cache'
data_dir  = 'Z:\mnt\ecliptica\victory-data\data'
test_titles = []
```

A minimal wrapper (this is what was used):

```sh
#!/usr/bin/env bash
set -euo pipefail
repo=/path/to/victory-gta6
game=/mnt/xp/GTA6.Xbox.v1.0.2.1-CYBERLEEK
work=$HOME/.local/share/victory-proton-test
steam=$HOME/.local/share/Steam
runtime="$steam/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point"
proton="$steam/steamapps/common/Proton - Experimental/proton"

unset WINEPREFIX VICTORY_GAME_DIR VICTORY_CACHE_DIR VICTORY_DATA_DIR VICTORY_TEST_TITLES
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam"
export STEAM_COMPAT_DATA_PATH="$work/compatdata"
export STEAM_COMPAT_INSTALL_PATH="$repo"
export STEAM_COMPAT_MOUNTS="$repo:$game:$work"
export WINEDLLOVERRIDES='d3d12,d3d12core,dxgi=n'
export VICTORY_CONFIG='C:\victory.toml'      # work/compatdata/pfx/drive_c/victory.toml

cd "$work"
exec "$runtime" --verb=run -- "$proton" runinprefix "$@"
```

Launch:

```sh
export VICTORY_LOG=info
export VICTORY_NO_WATCHDOG=1
export VICTORY_SHADER_LOOP_LIMIT=4096
export VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains
# the gamepad-only account picker needs Enter presses
export VICTORY_KEYS=$(seq 20 5 300 | awk '{printf "%s:Enter,",$1}' | sed 's/,$//')

./run.sh ./target/x86_64-pc-windows-msvc/diag/victory.exe \
    run 'Z:\mnt\xp\GTA6.Xbox.v1.0.2.1-CYBERLEEK\game_scarlett_master.exe' --execute
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
texture may arrive one frame late). The copy path and the write-watch asks are the next
targets; the fork's `VICTORY_JOIN_COPIES` and `VICTORY_INPLACE` are the candidates.

Do **not** set `VICTORY_D3D12_DRED` for normal play: measured at ~2.5× cost in the world.

## Traps

- **Fresh data directory for scripted runs.** Once the title writes a save, scripted Enter picks
  "Continue" and it dies in ~40 s at `+0x164a298` (read `0x2c`) — a different failure that looks
  like a crash. Move `data/7952987A/saves` aside, or use a fresh `data_dir`.
- **Capture frames are presented-frame numbers**, which advance even while loading. The world
  starts around frame 3,000–4,300 depending on how fast pipelines build.
- The first run is cold: 500–1,300 pipelines are built (the fork loads ~960 from its library,
  builds the rest). Later runs reuse them.
- The title's crash reporter tries to upload a minidump to `submit.backtrace.io`; the runtime
  blocks it. Run offline if you do not want the attempt at all.

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
