/* hooks.c - the port's part of the engine, the same in every build (the Atari816 and the
 * PC's headless twins): upstream's globals and functions from the files the port does not
 * take (sim.c, w_sim.c, w_stubs.c, w_tk.c, w_editor.c, w_resrc.c, w_keys.c), the strings,
 * one tick of the simulation and the checksum of its state.
 *
 * Copyright (C) 2026 the Atari816 project. GPL-3 with Electronic Arts' additional terms,
 * as the engine (engine/COPYING, engine/README). Parts after upstream's sim.c, w_stubs.c,
 * w_tk.c and w_resrc.c (Copyright (C) 1989 - 2007 Electronic Arts Inc.).
 */
#include "sim.h"
#include "hooks.h"

/* ---------------------------------------------------------------- upstream's globals */

Sim *sim = NULL;
int sim_skips = 0;
int sim_skip = 0;
int sim_paused = 0;
int sim_paused_speed = 3;
int heat_steps = 0;
int DoAnimation = 1;
int DoMessages = 1;
int DoNotices = 1;
char *CityFileName = NULL;
char *StartupName = NULL;
char *CityName = NULL;
char *HomeDir = NULL;
char *ResourceDir = NULL;
QUAD TotalFunds;
short autoBulldoze, autoBudget;
QUAD LastMesTime;
short GameLevel;
short InitSimLoad;
short ScenarioID;
short SimSpeed;
short SimMetaSpeed;
short UserSoundOn;
short NoDisasters;
short MesNum;
short EvalChanged;
int UpdateDelayed = 0;
int TilesAnimated = 0;

static Sim the_sim;

const unsigned short port_bit[16] = {
    1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000,
    0x4000, 0x8000
};

/* ---------------------------------------------------------------- upstream's stubs */

void SetFunds(QUAD dollars)
{
    TotalFunds = dollars;
    UpdateFunds();
}

void Spend(QUAD dollars)
{
    SetFunds(TotalFunds - dollars);
}

void Kick(void) { }
void InvalidateMaps(void) { port_ui.maps = 1; }
void InvalidateEditors(void) { port_ui.editors = 1; }
void ResetLastKeys(void) { }
void StopMicropolisTimer(void) { }
void StartMicropolisTimer(void) { }
void EventuallyRedrawView(SimView *view) { (void)view; }
void CancelRedrawView(SimView *view) { (void)view; }
void UpdateFlush(void) { }

void sim_exit(int val)
{
    exit(val);
}

/* upstream's Tcl drops a fire bomb at once and three more 300, 600 and 900 ms later
 * (micropolis.tcl, DropFireBombs): here all four in the tick that asks (the same in every
 * build: no clock) */
void DropFireBombs(void)
{
    FireBomb();
    FireBomb();
    FireBomb();
    FireBomb();
}

/* w_tk.c: the sound, the Tcl hook, and the shaking of the views (the front end stops it) */
void DoEarthQuake(void)
{
    MakeSound("city", "Explosion-Low");
    Eval("UIEarthQuake");
    ShakeNow++;
}

/* the Mac's clock, 60 ticks a second: the front end's (messages time out by it) */
QUAD TickCount(void)
{
    return port_ticks();
}

/* ---------------------------------------------------------------- the strings */

struct stri_table { int id; int n; const char *const *s; };
extern const struct stri_table stri_tables[];

void GetIndString(char *str, int id, short num)
{
    const struct stri_table *t;

    for (t = stri_tables; t->id; t++)
        if (t->id == id)
            break;
    if (!t->id || num < 1 || num > t->n) {
        strcpy(str, "Well I'll be a monkey's uncle!");
        return;
    }
    strcpy(str, t->s[num - 1]);
}

/* ---------------------------------------------------------------- the front end */

struct port_ui port_ui;

int Eval(char *buf)
{
    port_eval(buf);
    return 0;
}

void MakeSound(char *channel, char *sound)
{
    port_sound(channel, sound);
}

/* ---------------------------------------------------------------- start, tick, state */

static SimView tool_view;

void port_init(void)
{
    if (sim)
        return;
    memset(&the_sim, 0, sizeof the_sim);
    sim = &the_sim;
    port_rand_init();
    initMapArrays();
    initGraphs();
    InitFundingLevel();
    StartingYear = 1900;
    tool_view.tool_state = dozeState;
    /* upstream's start (sim.c, sim_init): an empty city, funds of the easy level */
    InitGame_port();
}

/* sim.c's sim_init after the window system */
void InitGame_port(void)
{
    sim_skips = sim_skip = sim_paused = 0;
    sim_paused_speed = 3;
    SetFunds(5000);
    SetGameLevelFunds(0);
    CityTax = 7;                /* (upstream's Tcl sets the rate it starts with) */
    setSpeed(0);
    setSkips(0);
}

SimView *port_view(void)
{
    return &tool_view;
}

/* animateTiles (g_ani.c) a quarter of the map at a time: columns 0-29 in one tick, 30-59
 * in the next, ... (every tile every fourth tick; the whole map each tick was 60 ms of the
 * Atari816's, a third of a tick; upstream animates when its editors are drawn, which at
 * its higher speeds is every 20th tick or less often) */
unsigned char port_band;

void port_animate_band(void)
{
    unsigned x0 = (unsigned)port_band * (WORLD_X / 4);
#if defined(__CC816__)
    port_animate((unsigned short MAPFAR *)&Map[x0][0], (WORLD_X / 4) * WORLD_Y, aniTile);
#else
    unsigned short *p = (unsigned short *)&Map[x0][0];
    unsigned i;
    for (i = 0; i < (WORLD_X / 4) * WORLD_Y; i++, p++)
        if (*p & ANIMBIT)
            *p = (unsigned short)((*p & ALLBITS) | aniTile[*p & LOMASK]);
#endif
    port_band = (unsigned char)((port_band + 1) & 3);
}

/* One tick: what upstream's sim_loop does once with the simulator running (sim.c):
 * SimFrame (a sixteenth of a pass at the fast speed, less at the slower ones), the moving
 * things, and sim_update's parts that change the city (the editors' animateTiles, once,
 * and DoUpdateHeads, which keeps the funds from going below 0) or its windows' values
 * (the graphs, the budget, the evaluation: their Tcl calls go to the front end). */
void port_tick(void)
{
    SimFrame();
    MoveObjects();
    if (SimSpeed && !heat_steps)
        TilesAnimated = 0;
    if (DoAnimation && SimSpeed && !heat_steps && !TilesAnimated) {
        TilesAnimated = 1;
        port_animate_band();
    }
    DoUpdateHeads();
    graphDoer();
    UpdateBudgetWindow();
    scoreDoer();
}

/* ---------------------------------------------------------------- the state's checksum */

static unsigned long crc;
static unsigned long crctab[256];

static void crc_byte(unsigned c)
{
    crc = crctab[(unsigned char)(crc ^ c)] ^ (crc >> 8);
}

static void crc_init(void)
{
    unsigned i, k;
    unsigned long c;
    for (i = 0; i < 256; i++) {
        c = i;
        for (k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xEDB88320UL & (0UL - (c & 1)));
        crctab[i] = c;
    }
}

static void crc_word(unsigned short w)
{
    crc_byte(w);
    crc_byte(w >> 8);
}

static void crc_long(unsigned long l)
{
    crc_word((unsigned short)l);
    crc_word((unsigned short)(l >> 16));
}

static void crc_float(float f)
{
    unsigned long l;
    memcpy(&l, &f, 4);
    crc_long(l);
}

static void crc_near(const void *p, unsigned n)
{
    const unsigned char *b = (const unsigned char *)p;
    while (n--)
        crc_byte(*b++);
}

static void crc_bytes(const Byte MAPFAR *p, unsigned n)
{
    while (n--)
        crc_byte(*p++);
}

static void crc_shorts(const short MAPFAR *p, unsigned n)
{
    while (n--)
        crc_word((unsigned short)*p++);
}

extern float EMarket;
extern short CashFlow, AvCityTax, CrimeRamp, PolluteRamp, Scycle, Fcycle, Spdcycle;
extern short NewPower;
extern QUAD MaxPower, NumPower;
extern int PowerStackNum;
extern short CityYes, CityNo, CityClass, CityScore, deltaCityScore;
extern QUAD CityPop, deltaCityPop, CityAssValue;
extern short ProblemVotes[], ProblemOrder[];
extern QUAD RoadFund, PoliceFund, FireFund, TaxFund, RoadSpend, PoliceSpend, FireSpend;
extern QUAD fireValue, policeValue, roadValue;
unsigned QUAD sim_rand_state(void);

/* The whole state of the simulation: the maps (the city, the 2 x 2, 4 x 4 and 8 x 8
 * ones), the histories, the power map, the moving things, the counters, funds, budget,
 * evaluation, the random numbers' state and the floats as their bits. */
unsigned long port_checksum(void)
{
    short x;
    SimSprite *s;

    if (!crctab[1])
        crc_init();
    crc = 0xFFFFFFFFUL;
    for (x = 0; x < WORLD_X; x++) {
        short y;
        for (y = 0; y < WORLD_Y; y++)
            crc_word((unsigned short)Map[x][y]);
    }
    for (x = 0; x < HWLDX; x++) {
        crc_bytes(PopDensity[x], HWLDY);
        crc_bytes(TrfDensity[x], HWLDY);
        crc_bytes(PollutionMem[x], HWLDY);
        crc_bytes(LandValueMem[x], HWLDY);
        crc_bytes(CrimeMem[x], HWLDY);
    }
    for (x = 0; x < QWX; x++)
        crc_bytes(TerrainMem[x], QWY);
    crc_shorts(&RateOGMem[0][0], SmX * SmY);
    crc_shorts(&FireStMap[0][0], SmX * SmY);
    crc_shorts(&PoliceMap[0][0], SmX * SmY);
    crc_shorts(&PoliceMapEffect[0][0], SmX * SmY);
    crc_shorts(&ComRate[0][0], SmX * SmY);
    crc_shorts(&FireRate[0][0], SmX * SmY);
    crc_shorts(ResHis, HISTLEN / 2);
    crc_shorts(ComHis, HISTLEN / 2);
    crc_shorts(IndHis, HISTLEN / 2);
    crc_shorts(MoneyHis, HISTLEN / 2);
    crc_shorts(PollutionHis, HISTLEN / 2);
    crc_shorts(CrimeHis, HISTLEN / 2);
    crc_shorts(MiscHis, MISCHISTLEN / 2);
    crc_shorts(PowerMap, POWERMAPLEN / 2);
    for (s = sim->sprite; s; s = s->next) {
        crc_word(s->type); crc_word(s->frame);
        crc_word(s->x); crc_word(s->y);
        crc_word(s->dest_x); crc_word(s->dest_y);
        crc_word(s->count); crc_word(s->dir); crc_word(s->new_dir);
        crc_word(s->step); crc_word(s->flag); crc_word(s->control);
        crc_word(s->turn); crc_word(s->accel); crc_word(s->speed);
    }
    crc_long(TotalFunds);
    crc_long(CityTime);
    crc_long(CityPop);
    crc_long(deltaCityPop);
    crc_long(CityAssValue);
    crc_word(CityScore); crc_word(deltaCityScore);
    crc_word(CityYes); crc_word(CityNo); crc_word(CityClass);
    crc_shorts(ProblemVotes, PROBNUM);
    crc_shorts(ProblemOrder, 4);
    crc_word(ResPop); crc_word(ComPop); crc_word(IndPop); crc_word(TotalPop);
    crc_word(ResZPop); crc_word(ComZPop); crc_word(IndZPop);
    crc_word(RValve); crc_word(CValve); crc_word(IValve);
    crc_word(ResCap); crc_word(ComCap); crc_word(IndCap);
    crc_word(CrimeAverage); crc_word(PolluteAverage); crc_word(LVAverage);
    crc_word(TrafficAverage);
    crc_word(RoadEffect); crc_word(PoliceEffect); crc_word(FireEffect);
    crc_word(CityTax); crc_word(AvCityTax); crc_word(CashFlow);
    crc_word(Scycle); crc_word(Fcycle); crc_word(Spdcycle);
    crc_word(PwrdZCnt); crc_word(unPwrdZCnt);
    crc_long(RoadFund); crc_long(PoliceFund); crc_long(FireFund); crc_long(TaxFund);
    crc_long(RoadSpend); crc_long(PoliceSpend); crc_long(FireSpend);
    crc_long(roadValue); crc_long(policeValue); crc_long(fireValue);
    crc_float(roadPercent); crc_float(policePercent); crc_float(firePercent);
    crc_float(EMarket);
    crc_word(DisasterEvent); crc_word(DisasterWait);
    crc_word(MesNum); crc_word(MessagePort);
    crc_long(sim_rand_state());
    crc_byte(port_band);
    return crc ^ 0xFFFFFFFFUL;
}

/* one line of the state's main values (the tests compare it between the builds) */
void port_state_line(char *buf)
{
    sprintf(buf, "crc %08" PRIQX " time %" PRIQ " funds %" PRIQ " pop %" PRIQ " r %d c %d i %d "
            "score %d valves %d %d %d", (unsigned long)port_checksum(), CityTime,
            TotalFunds, CityPop, ResPop, ComPop, IndPop, CityScore, RValve, CValve,
            IValve);
}

/* the whole state, as text, for finding where two builds part (simtest's dump) */
void port_dump(FILE *f)
{
    short x, y;
    fprintf(f, "time %" PRIQ " funds %" PRIQ " rand %08" PRIQX "\n", CityTime, TotalFunds,
            (unsigned long)sim_rand_state());
    for (y = 0; y < WORLD_Y; y++) {
        for (x = 0; x < WORLD_X; x++)
            fprintf(f, "%04x", (unsigned short)Map[x][y]);
        fputc('\n', f);
    }
    for (y = 0; y < HWLDY; y++) {
        for (x = 0; x < HWLDX; x++)
            fprintf(f, "%02x%02x%02x%02x%02x ", PopDensity[x][y], TrfDensity[x][y],
                    PollutionMem[x][y], LandValueMem[x][y], CrimeMem[x][y]);
        fputc('\n', f);
    }
    for (y = 0; y < SmY; y++) {
        for (x = 0; x < SmX; x++)
            fprintf(f, "%d/%d/%d/%d/%d/%d ", RateOGMem[x][y], FireStMap[x][y],
                    PoliceMap[x][y], PoliceMapEffect[x][y], ComRate[x][y],
                    FireRate[x][y]);
        fputc('\n', f);
    }
    for (x = 0; x < HISTLEN / 2; x++)
        fprintf(f, "%d %d %d %d %d %d\n", ResHis[x], ComHis[x], IndHis[x], MoneyHis[x],
                PollutionHis[x], CrimeHis[x]);
    for (x = 0; x < MISCHISTLEN / 2; x++)
        fprintf(f, "%d ", MiscHis[x]);
    fputc('\n', f);
    {
        SimSprite *s;
        for (s = sim->sprite; s; s = s->next)
            fprintf(f, "sprite %d %d %d %d %d %d\n", s->type, s->frame, s->x, s->y,
                    s->count, s->dir);
    }
    fprintf(f, "valves %d %d %d caps %d %d %d avg %d %d %d %d\n", RValve, CValve, IValve,
            ResCap, ComCap, IndCap, CrimeAverage, PolluteAverage, LVAverage,
            TrafficAverage);
    fprintf(f, "eval %" PRIQ " %" PRIQ " %" PRIQ " %d %d %d %d %d\n", CityPop, deltaCityPop,
            CityAssValue, CityScore, deltaCityScore, CityYes, CityNo, CityClass);
}
