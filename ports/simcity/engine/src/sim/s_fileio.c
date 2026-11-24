/* s_fileio.c
 *
 * Micropolis, Unix Version.  This game was released for the Unix platform
 * in or about 1990 and has been modified for inclusion in the One Laptop
 * Per Child program.  Copyright (C) 1989 - 2007 Electronic Arts Inc.  If
 * you need assistance with this program, you may contact:
 *   http://wiki.laptop.org/go/Micropolis  or email  micropolis@laptop.org.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.  You should have received a
 * copy of the GNU General Public License along with this program.  If
 * not, see <http://www.gnu.org/licenses/>.
 * 
 *             ADDITIONAL TERMS per GNU GPL Section 7
 * 
 * No trademark or publicity rights are granted.  This license does NOT
 * give you any right, title or interest in the trademark SimCity or any
 * other Electronic Arts trademark.  You may not distribute any
 * modification of this program using the trademark SimCity or claim any
 * affliation or association with Electronic Arts Inc. or its employees.
 * 
 * Any propagation or conveyance of this program must include this
 * copyright notice and these terms.
 * 
 * If you convey this program (or any modifications of it) and assume
 * contractual liability for the program to recipients of it, you agree
 * to indemnify Electronic Arts for any liability that those contractual
 * assumptions impose on Electronic Arts.
 * 
 * You may not misrepresent the origins of this program; modified
 * versions of the program must be marked as such and not identified as
 * the original program.
 * 
 * This disclaimer supplements the one included in the General Public
 * License.  TO THE FULLEST EXTENT PERMISSIBLE UNDER APPLICABLE LAW, THIS
 * PROGRAM IS PROVIDED TO YOU "AS IS," WITH ALL FAULTS, WITHOUT WARRANTY
 * OF ANY KIND, AND YOUR USE IS AT YOUR SOLE RISK.  THE ENTIRE RISK OF
 * SATISFACTORY QUALITY AND PERFORMANCE RESIDES WITH YOU.  ELECTRONIC ARTS
 * DISCLAIMS ANY AND ALL EXPRESS, IMPLIED OR STATUTORY WARRANTIES,
 * INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, SATISFACTORY QUALITY,
 * FITNESS FOR A PARTICULAR PURPOSE, NONINFRINGEMENT OF THIRD PARTY
 * RIGHTS, AND WARRANTIES (IF ANY) ARISING FROM A COURSE OF DEALING,
 * USAGE, OR TRADE PRACTICE.  ELECTRONIC ARTS DOES NOT WARRANT AGAINST
 * INTERFERENCE WITH YOUR ENJOYMENT OF THE PROGRAM; THAT THE PROGRAM WILL
 * MEET YOUR REQUIREMENTS; THAT OPERATION OF THE PROGRAM WILL BE
 * UNINTERRUPTED OR ERROR-FREE, OR THAT THE PROGRAM WILL BE COMPATIBLE
 * WITH THIRD PARTY SOFTWARE OR THAT ANY ERRORS IN THE PROGRAM WILL BE
 * CORRECTED.  NO ORAL OR WRITTEN ADVICE PROVIDED BY ELECTRONIC ARTS OR
 * ANY AUTHORIZED REPRESENTATIVE SHALL CREATE A WARRANTY.  SOME
 * JURISDICTIONS DO NOT ALLOW THE EXCLUSION OF OR LIMITATIONS ON IMPLIED
 * WARRANTIES OR THE LIMITATIONS ON THE APPLICABLE STATUTORY RIGHTS OF A
 * CONSUMER, SO SOME OR ALL OF THE ABOVE EXCLUSIONS AND LIMITATIONS MAY
 * NOT APPLY TO YOU.
 */
#include "sim.h"


#if defined(MICROPOLIS_PORT)
/* The port's reading and writing of upstream's .cty format (27,120 bytes, every value a
 * big-endian 16-bit word: the six histories of 240 words, MiscHis's 120, the map's
 * 12,000 by columns), the same files as upstream's on any machine:
 *   - upstream reads the file's words into its arrays, swaps their bytes on a
 *     little-endian machine and then reads 32-bit values (funds, the time, the budget's
 *     percents) as `*(QUAD *)(MiscHis + n)`, which needs QUAD to be 32 bits and an
 *     aligned 4-byte read; here each such value is two words, high one first;
 *   - the map is in far memory on the Atari816 (Map, s_alloc.c): read and written
 *     through a small buffer. */

static unsigned char fbuf[512];

static int
_load_words(short MAPFAR *buf, int len, FILE *f)
{
  int n, i;

  while (len > 0) {
    n = len > 256 ? 256 : len;
    if (fread(fbuf, 1, 2 * n, f) != (size_t)(2 * n))
      return 0;
    for (i = 0; i < n; i++)
      buf[i] = (short)((fbuf[2 * i] << 8) | fbuf[2 * i + 1]);
    buf += n;
    len -= n;
  }
  return 1;
}

static int
_save_words(short MAPFAR *buf, int len, FILE *f)
{
  int n, i;

  while (len > 0) {
    n = len > 256 ? 256 : len;
    for (i = 0; i < n; i++) {
      fbuf[2 * i] = (unsigned char)((unsigned short)buf[i] >> 8);
      fbuf[2 * i + 1] = (unsigned char)buf[i];
    }
    if (fwrite(fbuf, 1, 2 * n, f) != (size_t)(2 * n))
      return 0;
    buf += n;
    len -= n;
  }
  return 1;
}

/* MiscHis[n] (high) and MiscHis[n + 1] (low) as one 32-bit value, and back */
static QUAD
_misc_long(int n)
{
  return (QUAD)(((unsigned QUAD)(unsigned short)MiscHis[n] << 16) |
                (unsigned short)MiscHis[n + 1]);
}

static void
_set_misc_long(int n, QUAD l)
{
  MiscHis[n] = (short)((unsigned QUAD)l >> 16);
  MiscHis[n + 1] = (short)l;
}

static
int
_load_file(char *filename, char *dir)
{
  FILE *f;
  char path[160];
  QUAD size;

  if (dir != NULL) {
    sprintf(path, "%s/%s", dir, filename);
    filename = path;
  }
  if ((f = fopen(filename, "rb")) == NULL) {
    return (0);
  }

  fseek(f, 0L, SEEK_END);
  size = ftell(f);
  fseek(f, 0L, SEEK_SET);

  if (size != 27120) {          /* a normal city (upstream's 2 x 2 and 3 x 3 cities
                                   are for its MEGA build) */
    fclose(f);
    return (0);
  }

  if ((_load_words(ResHis, HISTLEN / 2, f) == 0) ||
      (_load_words(ComHis, HISTLEN / 2, f) == 0) ||
      (_load_words(IndHis, HISTLEN / 2, f) == 0) ||
      (_load_words(CrimeHis, HISTLEN / 2, f) == 0) ||
      (_load_words(PollutionHis, HISTLEN / 2, f) == 0) ||
      (_load_words(MoneyHis, HISTLEN / 2, f) == 0) ||
      (_load_words(MiscHis, MISCHISTLEN / 2, f) == 0) ||
      (_load_words((&Map[0][0]), WORLD_X * WORLD_Y, f) == 0)) {
    fclose(f);
    return(0);
  }

  fclose(f);
  return(1);
}


int loadFile(char *filename)
{
  QUAD l;

  if (_load_file(filename, NULL) == 0)
    return(0);

  SetFunds(_misc_long(50));
  CityTime = _misc_long(8);

  autoBulldoze = MiscHis[52];	/* flag for autoBulldoze */
  autoBudget = MiscHis[53];	/* flag for autoBudget */
  autoGo = MiscHis[54];		/* flag for autoGo */
  UserSoundOn = MiscHis[55];	/* flag for the sound on/off */
  CityTax = MiscHis[56];
  SimSpeed = MiscHis[57];
  ChangeCensus();
  MustUpdateOptions = 1;

  /* (upstream then reads the three percents a second time, unswapped: harmless, since
     InitFundingLevel below sets them to 100 % anyway) */
  l = _misc_long(58);
  policePercent = l / 65536.0;
  l = _misc_long(60);
  firePercent = l / 65536.0;
  l = _misc_long(62);
  roadPercent = l / 65536.0;

  if (CityTime < 0)
    CityTime = 0;
  if ((CityTax > 20) || (CityTax < 0))
    CityTax = 7;
  if ((SimSpeed < 0) || (SimSpeed > 3))
    SimSpeed = 3;

  setSpeed(SimSpeed);
  setSkips(0);

  InitFundingLevel();

  /* set the scenario id to 0 */
  InitWillStuff();
  ScenarioID = 0;
  InitSimLoad = 1;
  DoInitialEval = 0;
  DoSimInit();
  InvalidateEditors();
  InvalidateMaps();

  return (1);
}


int saveFile(char *filename)
{
  FILE *f;

  if ((f = fopen(filename, "wb")) == NULL) {
    return(0);
  }

  _set_misc_long(50, TotalFunds);
  _set_misc_long(8, CityTime);

  MiscHis[52] = autoBulldoze;	/* flag for autoBulldoze */
  MiscHis[53] = autoBudget;	/* flag for autoBudget */
  MiscHis[54] = autoGo;		/* flag for autoGo */
  MiscHis[55] = UserSoundOn;	/* flag for the sound on/off */
  MiscHis[57] = SimSpeed;
  MiscHis[56] = CityTax;	/* post release */

  /* upstream: (int)(percent * 65536), 32 bits */
  _set_misc_long(58, (QUAD)(policePercent * 65536));
  _set_misc_long(60, (QUAD)(firePercent * 65536));
  _set_misc_long(62, (QUAD)(roadPercent * 65536));

  if ((_save_words(ResHis, HISTLEN / 2, f) == 0) ||
      (_save_words(ComHis, HISTLEN / 2, f) == 0) ||
      (_save_words(IndHis, HISTLEN / 2, f) == 0) ||
      (_save_words(CrimeHis, HISTLEN / 2, f) == 0) ||
      (_save_words(PollutionHis, HISTLEN / 2, f) == 0) ||
      (_save_words(MoneyHis, HISTLEN / 2, f) == 0) ||
      (_save_words(MiscHis, MISCHISTLEN / 2, f) == 0) ||
      (_save_words((&Map[0][0]), WORLD_X * WORLD_Y, f) == 0)) {
    fclose(f);
    return(0);
  }

  if (fclose(f) != 0)
    return(0);
  return(1);
}


#else
#define SWAP_SHORTS(a,b)	_swap_shorts(a,b)
#define SWAP_LONGS(a,b)		_swap_longs(a,b)
#define HALF_SWAP_LONGS(a,b)	_half_swap_longs(a,b)

#define NOOP_ON_BE	{ int test = 1; if (!(*(unsigned char*) (&test))) return; }

static void
_swap_shorts(short *buf, int len)
{
  int i;

  NOOP_ON_BE;

  /* Flip bytes in each short! */
  for (i = 0; i < len; i++) {	
    *buf = ((*buf & 0xFF) <<8) | ((*buf &0xFF00) >>8);
    buf++;
  }
}

static void
_swap_longs(long *buf, int len)
{
  int i;

  NOOP_ON_BE;

  /* Flip bytes in each long! */
  for (i = 0; i < len; i++) {	
    long l = *buf;
    *buf =
      ((l & 0x000000ff) << 24) |
      ((l & 0x0000ff00) << 8) |
      ((l & 0x00ff0000) >> 8) |
      ((l & 0xff000000) >> 24);
    buf++;
  }
}

static void
_half_swap_longs(long *buf, int len)
{
  int i;

  NOOP_ON_BE;

  /* Flip bytes in each long! */
  for (i = 0; i < len; i++) {	
    long l = *buf;
    *buf =
      ((l & 0x0000ffff) << 16) |
      ((l & 0xffff0000) >> 16);
    buf++;
  }
}


static int
_load_short(short *buf, int len, FILE *f)
{
  if (fread(buf, sizeof(short), len, f) != len)
     return 0;

  SWAP_SHORTS(buf, len);	/* to intel */

  return 1;
}


static int
_load_long(long *buf, int len, FILE *f)
{
  if (fread(buf, sizeof(long), len, f) != len)
     return 0;

  SWAP_LONGS(buf, len);	/* to intel */

  return 1;
}


static int
_save_short(short *buf, int len, FILE *f)
{

  SWAP_SHORTS(buf, len);	/* to MAC */

  if (fwrite(buf, sizeof(short), len, f) != len)
     return 0;

  SWAP_SHORTS(buf, len);	/* back to intel */

  return 1;
}


static int
_save_long(long *buf, int len, FILE *f)
{

  SWAP_LONGS(buf, len);	/* to MAC */

  if (fwrite(buf, sizeof(long), len, f) != len)
     return 0;

  SWAP_LONGS(buf, len);	/* back to intel */

  return 1;
}


static
int 
_load_file(char *filename, char *dir)
{
  FILE *f;
  char path[512];
  QUAD size;

#ifdef MSDOS
  if (dir != NULL) {
    sprintf(path, "%s\\%s", dir, filename);
    filename = path;
  }
  if ((f = fopen(filename, "rb")) == NULL) {
    return 0;
  }
#else
  if (dir != NULL) {
    sprintf(path, "%s/%s", dir, filename);
    filename = path;
  }
  if ((f = fopen(filename, "r")) == NULL) {
    return (0);
  }
#endif

  fseek(f, 0L, SEEK_END);
  size = ftell(f);
  fseek(f, 0L, SEEK_SET);

  switch (size) {
  case 27120: /* Normal city */
    break;

  case 99120: /* 2x2 city */
    break;

  case 219120: /* 3x3 city */
    break;

  default:
    return (0);
  }

  if ((_load_short(ResHis, HISTLEN / 2, f) == 0) ||
      (_load_short(ComHis, HISTLEN / 2, f) == 0) ||
      (_load_short(IndHis, HISTLEN / 2, f) == 0) ||
      (_load_short(CrimeHis, HISTLEN / 2, f) == 0) ||
      (_load_short(PollutionHis, HISTLEN / 2, f) == 0) ||
      (_load_short(MoneyHis, HISTLEN / 2, f) == 0) ||
      (_load_short(MiscHis, MISCHISTLEN / 2, f) == 0) ||
      (_load_short((&Map[0][0]), WORLD_X * WORLD_Y, f) < 0)) {

    /* TODO:  report error */
    fclose(f);
    return(0);
  }

  fclose(f);
  return(1);
}


int loadFile(char *filename)
{
  long l;

  if (_load_file(filename, NULL) == 0)
    return(0);

  /* total funds is a long.....    MiscHis is array of shorts */
  /* total funds is being put in the 50th & 51th word of MiscHis */
  /* find the address, cast the ptr to a lontPtr, take contents */

  l = *(QUAD *)(MiscHis + 50);
  HALF_SWAP_LONGS(&l, 1);
  SetFunds(l);

  l = *(QUAD *)(MiscHis + 8);
  HALF_SWAP_LONGS(&l, 1);
  CityTime = l;

  autoBulldoze = MiscHis[52];	/* flag for autoBulldoze */
  autoBudget = MiscHis[53];	/* flag for autoBudget */
  autoGo = MiscHis[54];		/* flag for autoGo */
  UserSoundOn = MiscHis[55];	/* flag for the sound on/off */
  CityTax = MiscHis[56];
  SimSpeed = MiscHis[57];
  //  sim_skips = sim_skip = 0;
  ChangeCensus();
  MustUpdateOptions = 1;

  /* yayaya */

  l = *(QUAD *)(MiscHis + 58);
  HALF_SWAP_LONGS(&l, 1);
  policePercent = l / 65536.0;

  l = *(QUAD *)(MiscHis + 60);
  HALF_SWAP_LONGS(&l, 1);
  firePercent = l / 65536.0;

  l = *(QUAD *)(MiscHis + 62);
  HALF_SWAP_LONGS(&l, 1);
  roadPercent = l / 65536.0;

  policePercent = (*(QUAD*)(MiscHis + 58)) / 65536.0;	/* and 59 */
  firePercent = (*(QUAD*)(MiscHis + 60)) / 65536.0;	/* and 61 */
  roadPercent =(*(QUAD*)(MiscHis + 62)) / 65536.0;	/* and 63 */

  if (CityTime < 0)
    CityTime = 0;
  if ((CityTax > 20) || (CityTax < 0))
    CityTax = 7;
  if ((SimSpeed < 0) || (SimSpeed > 3))
    SimSpeed = 3;

  setSpeed(SimSpeed);
  setSkips(0);

  InitFundingLevel();

  /* set the scenario id to 0 */
  InitWillStuff();
  ScenarioID = 0;
  InitSimLoad = 1;
  DoInitialEval = 0;
  DoSimInit();
  InvalidateEditors();
  InvalidateMaps();

  return (1);
}


int saveFile(char *filename)
{
  long l;
  FILE *f;

#ifdef MSDOS
  if ((f = fopen(filename, "wb")) == NULL) {
#else
  if ((f = fopen(filename, "w")) == NULL) {
#endif
    /* TODO: report error */
    return(0);
  }

  /* total funds is a long.....    MiscHis is array of ints */
  /* total funds is bien put in the 50th & 51th word of MiscHis */
  /* find the address, cast the ptr to a lontPtr, take contents */

  l = TotalFunds;
  HALF_SWAP_LONGS(&l, 1);
  (*(QUAD *)(MiscHis + 50)) = l;

  l = CityTime;
  HALF_SWAP_LONGS(&l, 1);
  (*(QUAD *)(MiscHis + 8)) = l;

  MiscHis[52] = autoBulldoze;	/* flag for autoBulldoze */
  MiscHis[53] = autoBudget;	/* flag for autoBudget */
  MiscHis[54] = autoGo;		/* flag for autoGo */
  MiscHis[55] = UserSoundOn;	/* flag for the sound on/off */
  MiscHis[57] = SimSpeed;
  MiscHis[56] = CityTax;	/* post release */

  /* yayaya */

  l = (int)(policePercent * 65536);
  HALF_SWAP_LONGS(&l, 1);
  (*(QUAD *)(MiscHis + 58)) = l;

  l = (int)(firePercent * 65536);
  HALF_SWAP_LONGS(&l, 1);
  (*(QUAD *)(MiscHis + 60)) = l;

  l = (int)(roadPercent * 65536);
  HALF_SWAP_LONGS(&l, 1);
  (*(QUAD *)(MiscHis + 62)) = l;

  if ((_save_short(ResHis, HISTLEN / 2, f) == 0) ||
      (_save_short(ComHis, HISTLEN / 2, f) == 0) ||
      (_save_short(IndHis, HISTLEN / 2, f) == 0) ||
      (_save_short(CrimeHis, HISTLEN / 2, f) == 0) ||
      (_save_short(PollutionHis, HISTLEN / 2, f) == 0) ||
      (_save_short(MoneyHis, HISTLEN / 2, f) == 0) ||
      (_save_short(MiscHis, MISCHISTLEN / 2, f) == 0) ||
      (_save_short((&Map[0][0]), WORLD_X * WORLD_Y, f) < 0)) {

    /* TODO:  report error */
    fclose(f);
    return(0);
  }

  fclose(f);
  return(1);
}


#endif


void
LoadScenario(short s)
{
  char *name, *fname;

  if (CityFileName != NULL) {
    ckfree(CityFileName);
    CityFileName = NULL;
  }

  SetGameLevel(0);

  if ((s < 1) || (s > 8)) s = 1;

  switch (s) {
  case 1:
    name = "Dullsville";
    fname = "snro.111";
    ScenarioID = 1;
    CityTime = ((1900 - 1900) * 48) + 2;
    SetFunds(5000);
    break;
  case 2:
    name = "San Francisco";
    fname = "snro.222";
    ScenarioID = 2;
    CityTime = ((1906 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  case 3:
    name = "Hamburg";
    fname = "snro.333";
    ScenarioID = 3;
    CityTime = ((1944 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  case 4:
    name = "Bern";
    fname = "snro.444";
    ScenarioID = 4;
    CityTime = ((1965 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  case 5:
    name = "Tokyo";
    fname = "snro.555";
    ScenarioID = 5;
    CityTime = ((1957 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  case 6:
    name = "Detroit";
    fname = "snro.666";
    ScenarioID = 6;
    CityTime = ((1972 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  case 7:
    name = "Boston";
    fname = "snro.777";
    ScenarioID = 7;
    CityTime = ((2010 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  case 8:
    name = "Rio de Janeiro";
    fname = "snro.888";
    ScenarioID = 8;
    CityTime = ((2047 - 1900) * 48) + 2;
    SetFunds(20000);
    break;
  }

  setAnyCityName(name);
  //  sim_skips = sim_skip = 0;
  InvalidateMaps();
  InvalidateEditors();
  setSpeed(3);
  CityTax = 7;
#if !defined(MICROPOLIS_PORT)
  gettimeofday(&start_time, NULL);
#endif

  _load_file(fname, ResourceDir);

  InitWillStuff();
  InitFundingLevel();
  UpdateFunds();
  InvalidateEditors();
  InvalidateMaps();
  InitSimLoad = 1;
  DoInitialEval = 0;
  DoSimInit();
  DidLoadScenario();
  Kick();
}


void
DidLoadScenario()
{
  Eval("UIDidLoadScenario");
}


int LoadCity(char *filename)
{
  char *cp;
  char msg[256];

  if (loadFile(filename)) {
    if (CityFileName != NULL)
      ckfree(CityFileName);
    CityFileName = (char *)ckalloc(strlen(filename) + 1);
    strcpy(CityFileName, filename);

    if (cp = (char *)rindex(filename, '.'))
      *cp = 0;
#ifdef MSDOS
    if (cp = (char *)rindex(filename, '\\'))
#else
    if (cp = (char *)rindex(filename, '/'))
#endif
      cp++;
    else
      cp = filename;
    filename = (char *)ckalloc(strlen(cp) + 1);
    strcpy(filename, cp);
    setCityName(filename);
#if !defined(MICROPOLIS_PORT)
    gettimeofday(&start_time, NULL);
#endif

    InvalidateMaps();
    InvalidateEditors();
    DidLoadCity();
    return (1);
  } else {
    sprintf(msg, "Unable to load a city from the file named \"%s\". %s",
	    filename ? filename : "(null)",
	    errno ? strerror(errno) : "");
    DidntLoadCity(msg);
    return (0);
  }
}


void
DidLoadCity()
{
  Eval("UIDidLoadCity");
}


void
DidntLoadCity(char *msg)
{
  char buf[1024];
  sprintf(buf, "UIDidntLoadCity {%s}", msg);
  Eval(buf);
}


void
SaveCity()
{
  char msg[256];

  if (CityFileName == NULL) {
    DoSaveCityAs();
  } else {
    if (saveFile(CityFileName))
      DidSaveCity();
    else {
      sprintf(msg, "Unable to save the city to the file named \"%s\". %s",
	      CityFileName ? CityFileName : "(null)",
	      errno ? strerror(errno) : "");
      DidntSaveCity(msg);
    }
  }
}


void
DoSaveCityAs()
{
  Eval("UISaveCityAs");
}


void
DidSaveCity()
{
  Eval("UIDidSaveCity");
}


void
DidntSaveCity(char *msg)
{
  char buf[1024];
  sprintf(buf, "UIDidntSaveCity {%s}", msg);
  Eval(buf);
}


void
SaveCityAs(char *filename)
{
  char msg[256];
  char *cp;

  if (CityFileName != NULL)
    ckfree(CityFileName);
  CityFileName = (char *)ckalloc(strlen(filename) + 1);
  strcpy(CityFileName, filename);

  if (saveFile(CityFileName)) {
    if (cp = (char *)rindex(filename, '.'))
      *cp = 0;
#ifdef MSDOS
    if (cp = (char *)rindex(filename, '\\'))
#else
    if (cp = (char *)rindex(filename, '/'))
#endif
      cp++;
    else
      cp = filename;
    filename = (char *)ckalloc(strlen(cp) + 1);
    strcpy(filename, cp);
    setCityName(cp);
    DidSaveCity();
  } else {
    sprintf(msg, "Unable to save the city to the file named \"%s\". %s",
	    CityFileName ? CityFileName : "(null)",
	    errno ? strerror(errno) : "");
    DidntSaveCity(msg);
  }
}


