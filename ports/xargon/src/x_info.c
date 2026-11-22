// X_INFO.C
//
// Xargon Info
//
// by Allen W. Pilgrim

#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <io.h>
#include "gr.h"
#include "windows.h"
#include "x_obj.h"
#include "xargon.h"

extern char tilefile[];

void init_info (void) {
	int c,d,temp;
	char len;
	int flagsdef=f_notvine|f_notstair|f_notwater;
	int blockfile;

	for (c=0; c<numinfotypes; c++) {
		info [c].sh=0x4500;
		info [c].na="";
		info [c].flags=flagsdef;
		};

	blockfile=open (tilefile,O_BINARY);
	while (read(blockfile,&c,2)>0) {
		read (blockfile,&info[c].sh,2);
		read (blockfile,&temp,2);
		info[c].flags^=temp;
		read (blockfile,&len,1);
#if defined(_HORIZON)
		{								// (the names are the level editor's: not kept)
		char name[256];
		read (blockfile,name,(unsigned char)len);
		};
#else
		info [c].na=malloc (len+1);
		read (blockfile,info[c].na,len);
		info[c].na[len]=0;
#endif
		};

	for (c=0; c<numstates; c++) {
		stateinfo [c]=0;
		};

	stateinfo [st_begin]    |= sti_invincible;
	stateinfo [st_stand]    |= sti_canfire;
	stateinfo [st_still]    |= sti_invincible;
	stateinfo [st_jumping]  |= sti_canfire;
	stateinfo [st_climbing] |= 0;
	stateinfo [st_die]      |= sti_invincible;
	stateinfo [st_transport]|= sti_invincible;
	stateinfo [st_platform] |= sti_canfire;
	};