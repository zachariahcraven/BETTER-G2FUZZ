#!/bin/bash
# doom_wad and doom_demo: our harnesses g2f_doom.c (fuzzed add-on WAD) and g2f_demo.c (fuzzed demo)
# on doomgeneric (commit dcb7a8db, GPL-2.0), freedoom2.wad as the IWAD
#   -> OUT/doom_{wad,demo}.{afl,cmp,asan}, OUT/freedoom2.wad, OUT/seeds/{doom_wad,doom_demo}/
# Runs inside the g2fuzz image (the Dockerfile calls it). Usage: build.sh OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$1"; OUT=$(cd "$1" && pwd)
TAR="$HERE/doomgeneric-dcb7a8db.tar.gz"
echo "1bd3f7f26220494159a38d71f2847ec81b58d6bbd7c7c8d81b08993018001148  $TAR" | sha256sum -c --quiet - ||
  { echo "doom/build.sh: $TAR has the wrong sha256" >&2; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
tar -xzf "$TAR" -C "$W" --strip-components=1
D=$W/doomgeneric
# the engine, as doomgeneric's Makefile lists it, minus its X11 platform layer (g2f_doom.c is ours)
SRC="dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop d_main d_mode d_net f_finale
  f_wipe g_game hu_lib hu_stuff info i_cdmus i_endoom i_joystick i_scale i_sound i_system i_timer memio
  m_argv m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc m_random p_ceilng p_doors p_enemy
  p_floor p_inter p_lights p_map p_maputl p_mobj p_plats p_pspr p_saveg p_setup p_sight p_spec p_switch
  p_telept p_tick p_user r_bsp r_data r_draw r_main r_plane r_segs r_sky r_things sha1 sounds statdump
  st_lib st_stuff s_sound tables v_video wi_stuff w_checksum w_file w_main w_wad z_zone w_file_stdc
  i_input i_video doomgeneric"
CFLAGS="-O1 -g -fno-omit-frame-pointer -w -DNORMALUNIX -DLINUX -DSNDSERV -D_DEFAULT_SOURCE -I$D"
for v in afl cmp asan; do
  echo "building doom_wad.$v and doom_demo.$v"
  ( unset AFL_LLVM_CMPLOG AFL_USE_ASAN
    if [ $v = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ $v = asan ]; then export AFL_USE_ASAN=1; fi
    mkdir -p "$W/$v"
    for f in $SRC; do echo "afl-clang-fast $CFLAGS -c $D/$f.c -o $W/$v/$f.o"; done |
      xargs -P "$(nproc)" -I{} sh -c '{} || exit 255'
    mkdir -p "$W/$v/harness"
    afl-clang-fast $CFLAGS -c "$HERE/g2f_doom.c" -o "$W/$v/g2f_doom.o"
    afl-clang-fast $CFLAGS -c "$HERE/g2f_demo.c" -o "$W/$v/harness/g2f_demo.o"
    # The engine objects are shared; each harness brings its own main() and platform layer. Link order sets
    # AFL++'s edge ids, so each binary keeps the exact link it had when its campaigns ran: doom_wad as before
    # doom_demo existed (g2f_doom.o sorted among the engine objects), doom_demo = engine objects + g2f_demo.o.
    afl-clang-fast $CFLAGS "$W/$v"/*.o -lm -o "$OUT/doom_wad.$v"
    afl-clang-fast $CFLAGS $(ls "$W/$v"/*.o | grep -v '/g2f_doom\.o$') "$W/$v/harness/g2f_demo.o" -lm -o "$OUT/doom_demo.$v" )
done
cp "$HERE/freedoom2.wad" "$OUT/freedoom2.wad"
mkdir -p "$OUT/seeds/doom_wad" && cp "$HERE"/seeds/* "$OUT/seeds/doom_wad/"
mkdir -p "$OUT/seeds/doom_demo" && cp "$HERE"/demo-seeds/* "$OUT/seeds/doom_demo/"
