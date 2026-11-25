#!/usr/bin/env bash
# Rebuild the plain-Wine environment that measured 2.4 fps where Proton did
# 0.9: Wine 11.22's server with the view-tree patch, vkd3d-proton + DXVK from
# Proton Experimental, DXC beside the exe.
#
#   bash scripts/setup-wine.sh [target-dir]
#
# Everything lands under the target (default /tmp/opencode). The patch comes
# from yayameowmeow/victory-fork (docs/linux-wine.md); the numbers it buys are
# in findings.md.
set -euo pipefail
work=${1:-/tmp/opencode}
mkdir -p "$work"
cd "$work"

WINE=11.22
[ -f "wine-$WINE.tar.xz" ] || curl -sSL -o "wine-$WINE.tar.xz" "https://dl.winehq.org/wine/source/11.x/wine-$WINE.tar.xz"
[ -d "wine-$WINE" ] || tar xf "wine-$WINE.tar.xz"
[ -f view-tree.patch ] || curl -sSL -o view-tree.patch \
    https://raw.githubusercontent.com/yayameowmeow/victory-fork/linux-wine/contrib/wine/wineserver-view-tree.patch.txt
cd "wine-$WINE"
[ -f .patched ] || { patch -p1 < ../view-tree.patch; touch .patched; }
[ -x server/wineserver ] || {
    ./configure --enable-win64 --without-x --disable-tests >../wine-configure.log 2>&1
    make -j"$(nproc)" server/wineserver >../wine-build.log 2>&1
}
cd "$work"

P="$work/wineprefix"
if [ ! -d "$P/drive_c/windows/system32" ]; then
    WINEPREFIX="$P" wineboot -i >/dev/null 2>&1 || true
fi
S="$P/drive_c/windows/system32"
PROTON="/home/nick/.local/share/Steam/steamapps/common/Proton - Experimental/files/lib/wine"
cp -f "$PROTON/vkd3d-proton/x86_64-windows/d3d12.dll" \
      "$PROTON/vkd3d-proton/x86_64-windows/d3d12core.dll" \
      "$PROTON/dxvk/x86_64-windows/dxgi.dll" \
      "$PROTON/dxvk/x86_64-windows/d3d11.dll" "$S/"

cat > "$work/victory-wine.toml" <<'EOF'
[paths]
game_dir = 'Z:\mnt\xp\GTA6.Xbox.v1.0.2.1-CYBERLEEK'
cache_dir = 'Z:\mnt\ecliptica\victory-data\wine-cache'
data_dir = 'Z:\mnt\ecliptica\victory-data\wine-data'
test_titles = []
EOF

WINEPREFIX="$P" wineserver -k 2>/dev/null || true
sleep 1
WINEPREFIX="$P" nohup "$work/wine-$WINE/server/wineserver" -p30 >"$work/wine-server.log" 2>&1 &
echo "patched wineserver: $work/wine-$WINE/server/wineserver"
echo "prefix: $P"
