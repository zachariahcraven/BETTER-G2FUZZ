// g2f_doom: headless Doom WAD fuzz target for G2Fuzz/AFL++ (doom_wad.{afl,cmp,asan}).
//
//   doom_wad <file>   loads <file> as an add-on WAD (PWAD) on top of the base game, plays its first
//                     map for G2F_DOOM_TICS game tics (default 35), drawing every 5th, then exits.
//
// The base game (G2F_DOOM_IWAD, default /targets/freedoom2.wad) is loaded once by doomgeneric's
// normal startup, which also starts the base MAP01 (-warp 1). AFL++'s deferred forkserver starts
// after that, so per input only the add-on is loaded and its map played. The add-on's first map,
// whatever its marker is called (ExMy or MAPxx), is renamed MAP01 so it replaces the base map.
// No window, sound or input; the clock is fake and advances on every read, so runs are
// deterministic and Doom's wait loops can't hang. Doom's own errors (I_Error) exit with status 255.
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "doomgeneric.h"
#include "doomstat.h"
#include "d_main.h"
#include "g_game.h"
#include "w_wad.h"
#include "p_setup.h"

extern int numsectors, numlines;

extern gamestate_t wipegamestate;
void D_Display(void);

static char link_path[64];
static uint32_t fake_ms;

void DG_Init(void) {}
void DG_DrawFrame(void) {}
void DG_SleepMs(uint32_t ms) { fake_ms += ms; }
uint32_t DG_GetTicksMs(void) { return fake_ms += 10; }
int DG_GetKey(int *pressed, unsigned char *key) { (void)pressed; (void)key; return 0; }
void DG_SetWindowTitle(const char *title) { (void)title; }

static void remove_link(void) { if (link_path[0]) unlink(link_path); }

// ExMy or MAPxx (lump names are 8 bytes, NUL-padded)
static int is_map_marker(const char *n) {
    if (n[0] == 'E' && n[1] >= '0' && n[1] <= '9' && n[2] == 'M' && n[3] >= '0' && n[3] <= '9' && n[4] == 0)
        return 1;
    return n[0] == 'M' && n[1] == 'A' && n[2] == 'P' && n[3] >= '0' && n[3] <= '9' && n[4] >= '0' && n[4] <= '9'
        && n[5] == 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <file.wad>\n", argv[0]); return 2; }
    const char *iwad = getenv("G2F_DOOM_IWAD");
    char *dargv[] = { "doom", "-iwad", (char *)(iwad && *iwad ? iwad : "/targets/freedoom2.wad"),
                      "-warp", "1", "-skill", "3", "-nosound", "-nomusic", "-nosfx", "-nogui", NULL };
    doomgeneric_Create(11, dargv);   // full startup with the base game only

#ifdef __AFL_HAVE_MANUAL_CONTROL
    __AFL_INIT();
#endif
    // only now: AFL++ writes the input file after the forkserver handshake
    char input[PATH_MAX];
    if (!realpath(argv[1], input)) return 0;

    // W_AddFile only reads a WAD directory from a file whose name ends in "wad" (AFL++ names its
    // input .cur_input), so the input is linked under such a name first
    snprintf(link_path, sizeof link_path, "/tmp/g2f-doom-%d.wad", (int)getpid());
    unlink(link_path);
    if (symlink(input, link_path) != 0) return 0;
    atexit(remove_link);

    unsigned int first = numlumps;
    if (!W_AddFile(link_path)) exit(0);
    unsigned int map = numlumps;
    for (unsigned int i = first; i < numlumps; i++) {
        char n[9] = {0};
        memcpy(n, lumpinfo[i].name, 8);
        if (is_map_marker(n) && i + 1 < numlumps) { map = i; break; }
    }
    if (map == numlumps) exit(0);   // no map in the add-on: nothing of it would be played
    memcpy(lumpinfo[map].name, "MAP01\0\0\0", 8);
    W_GenerateHashTable();

    int tics = 35;
    const char *t = getenv("G2F_DOOM_TICS");
    if (t && atoi(t) > 0) tics = atoi(t);
    G_InitNew(sk_medium, 1, 1);
    int debug = getenv("G2F_DOOM_DEBUG") != NULL;
    if (debug)
        fprintf(stderr, "g2f: add-on lumps %u-%u, map at %u, gamestate %d, gameaction %d, sectors %d, lines %d, player mo %p\n",
                first, numlumps - 1, map, (int)gamestate, (int)gameaction, numsectors, numlines, (void *)players[consoleplayer].mo);
    for (int i = 0; i < tics; i++) {
        G_Ticker();
        gametic++;
        if (i % 5 == 4) {
            wipegamestate = gamestate;   // no screen wipe between frames
            D_Display();
        }
    }
    if (debug)
        fprintf(stderr, "g2f: after %d tics: gametic %d, leveltime %d, gamestate %d\n", tics, gametic, leveltime, (int)gamestate);
    exit(0);
}
