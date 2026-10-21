// g2f_demo: headless Doom demo fuzz target for G2Fuzz/AFL++ (doom_demo.{afl,cmp,asan}).
//
//   doom_demo <file>   plays <file> as a Doom v1.9 demo (.lmp: a 13-byte header, then 4 bytes per
//                      player per tic) on the base game for at most G2F_DOOM_TICS game tics
//                      (default 105 = 3 s, chosen in the pilot), drawing every 5th tic, then exits.
//
// The base game (G2F_DOOM_IWAD, default /targets/freedoom2.wad) is loaded once by doomgeneric's
// normal startup, as in g2f_doom.c; AFL++'s deferred forkserver starts after that, so per input
// only the demo's map is loaded and played. Only the base game's maps are used: the input is the
// player's input stream, not level data.
//
// Header (as G_DoPlayDemo reads it): version, skill, episode, map, deathmatch, respawn, fast,
// nomonsters, consoleplayer, playeringame[4]. The version byte is ignored and the other fields are
// clamped to values the engine accepts (skill 0-4, map 1-32, deathmatch 0-2, consoleplayer 0-3 and
// in the game), so that inputs explore gameplay instead of out-of-range array indexes in the
// header handling. The same clamping applies to every input.
//
// Playback stops before Doom's own end-of-demo handling (G_CheckDemoStatus would switch to the
// title demos) and never reads past the input: a tic is played only when all of its player
// commands are present and none starts with the 0x80 end marker.
// No window, sound or input; the clock is fake and advances on every read, so runs are
// deterministic and Doom's wait loops can't hang. Doom's own errors (I_Error) exit with status 255.
// G2F_DOOM_DEBUG=1 prints what was played (tics, map, position, kills, sectors visited, exit).
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "doomgeneric.h"
#include "doomstat.h"
#include "d_main.h"
#include "g_game.h"
#include "p_local.h"
#include "r_state.h"

extern byte *demobuffer, *demo_p;
extern boolean netdemo, usergame;
extern gamestate_t wipegamestate;
void D_Display(void);

#define HEADER 13
#define DEMOMARKER 0x80
#define MAX_INPUT (4 << 20)

static uint32_t fake_ms;

void DG_Init(void) {}
void DG_DrawFrame(void) {}
void DG_SleepMs(uint32_t ms) { fake_ms += ms; }
uint32_t DG_GetTicksMs(void) { return fake_ms += 10; }
int DG_GetKey(int *pressed, unsigned char *key) { (void)pressed; (void)key; return 0; }
void DG_SetWindowTitle(const char *title) { (void)title; }

static int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <demo.lmp>\n", argv[0]); return 2; }
    const char *iwad = getenv("G2F_DOOM_IWAD");
    char *dargv[] = { "doom", "-iwad", (char *)(iwad && *iwad ? iwad : "/targets/freedoom2.wad"),
                      "-warp", "1", "-skill", "3", "-nosound", "-nomusic", "-nosfx", "-nogui", NULL };
    doomgeneric_Create(11, dargv);   // full startup with the base game only

#ifdef __AFL_HAVE_MANUAL_CONTROL
    __AFL_INIT();
#endif
    // only now: AFL++ writes the input file after the forkserver handshake
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 0;
    byte *buf = malloc(MAX_INPUT + 1);
    if (!buf) return 0;
    size_t len = fread(buf, 1, MAX_INPUT, f);
    fclose(f);
    if (len < HEADER) exit(0);
    buf[len] = DEMOMARKER;   // guard: the stream always ends with a marker

    // header, as G_DoPlayDemo reads it (version byte ignored), clamped to accepted values
    skill_t skill = (skill_t)clamp(buf[1], sk_baby, sk_nightmare);
    int map = clamp(buf[3], 1, 32);
    deathmatch = clamp(buf[4], 0, 2);
    respawnparm = buf[5] != 0;
    fastparm = buf[6] != 0;
    nomonsters = buf[7] != 0;
    consoleplayer = clamp(buf[8], 0, MAXPLAYERS - 1);
    int players_in = 0;
    for (int i = 0; i < MAXPLAYERS; i++) {
        playeringame[i] = buf[9 + i] != 0;
        players_in += playeringame[i];
    }
    if (!playeringame[consoleplayer]) { playeringame[consoleplayer] = true; players_in++; }
    if (players_in > 1) { netgame = true; netdemo = true; }

    precache = false;   // as G_DoPlayDemo: don't spend time caching graphics for the level
    G_InitNew(skill, 1, map);
    precache = true;
    usergame = false;
    demobuffer = buf;
    demo_p = buf + HEADER;
    demoplayback = true;

    int tics = 105;
    const char *t = getenv("G2F_DOOM_TICS");
    if (t && atoi(t) > 0) tics = atoi(t);
    int debug = getenv("G2F_DOOM_DEBUG") != NULL;
    unsigned char *seen = NULL;
    int seen_n = 0, seen_map = -1, visited = 0, exited = 0, played = 0, startmap = gamemap;
    for (int i = 0; i < tics; i++) {
        // one 4-byte command per player in the game this tic; stop at the marker or the end
        size_t left = (size_t)(buf + len - demo_p);
        if (left < (size_t)(4 * players_in)) break;
        int ends = 0;
        for (int p = 0; p < players_in; p++)
            if (demo_p[4 * p] == DEMOMARKER) ends = 1;
        if (ends) break;
        G_Ticker();
        gametic++;
        played++;
        if (i % 5 == 4) {
            wipegamestate = gamestate;   // no screen wipe between frames
            D_Display();
        }
        if (debug) {
            if (gamestate != GS_LEVEL || gameaction == ga_completed) exited = 1;
            if (seen_map != gamemap || seen_n != numsectors) {   // new level: restart the count
                free(seen);
                seen_map = gamemap;
                seen = calloc(numsectors > 0 ? numsectors : 1, 1);
                seen_n = numsectors;
                visited = 0;
            }
            mobj_t *mo = players[consoleplayer].mo;
            if (gamestate == GS_LEVEL && mo && mo->subsector && seen) {
                int s = (int)(mo->subsector->sector - sectors);
                if (s >= 0 && s < seen_n && !seen[s]) { seen[s] = 1; visited++; }
            }
        }
    }
    if (debug) {
        player_t *pl = &players[consoleplayer];
        mobj_t *mo = pl->mo;
        fprintf(stderr, "g2f_demo: tics %d of %d, map %d->%d, skill %d, players %d, gamestate %d, "
                "pos %d,%d, health %d, kills %d/%d, items %d, secrets %d, sectors %d/%d, exited %d\n",
                played, tics, startmap, gamemap, (int)skill, players_in, (int)gamestate,
                mo ? mo->x >> FRACBITS : 0, mo ? mo->y >> FRACBITS : 0, pl->health,
                pl->killcount, totalkills, pl->itemcount, pl->secretcount, visited, numsectors, exited);
    }
    exit(0);
}
