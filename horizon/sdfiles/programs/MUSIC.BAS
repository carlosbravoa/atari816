10 REM MUSIC.BAS - a short tune of our own for Horizon BASIC 2.0: instruments made with
20 REM WAVE, notes played by name with PLAY, kept in time by FRAME (60 a second). The
30 REM graphics window shows the notes as they play. Esc stops.
40 WAVE 0,2,700,250:WAVE 1,1,600,180:WAVE 2,4,50,12:REM lead, bass, a soft tick
50 DIM M$(60),ML(60),B$(20),BL(20):N=0:K=0
60 READ A$:IF A$="*" THEN 80
70 READ L:M$(N)=A$:ML(N)=L:N=N+1:GOTO 60
80 READ A$:IF A$="*" THEN 100
90 READ L:B$(K)=A$:BL(K)=L:K=K+1:GOTO 80
100 SCREEN 320,120:GCLS 17:COLOR 1:TEXT 4,4,"MUSIC.BAS  PLAY with notes"
110 I=0:J=0:TM=0:TB=0:Q=0:F=FRAME
120 REM ---- every 8 frames, a sixteenth note
130 VSYNC:IF ((FRAME-F) AND 65535)<8 THEN 130
140 F=F+8:X=(Q*4) MOD 320:COLOR 17:FRECT (X+40) MOD 320,20,4,100
150 IF TM=0 THEN A$=M$(I):TM=ML(I):I=(I+1) MOD N:IF A$<>"-" THEN PLAY 0,A$,13,-3,0:COLOR 226:FRECT X,86-NOTE(A$)*3,4*TM-1,3
160 IF TB=0 THEN A$=B$(J):TB=BL(J):J=(J+1) MOD K:PLAY 1,A$,12,3,1:COLOR 39:FRECT X,114-(NOTE(A$)+21)*2,4*TB-1,3
170 IF (Q AND 3)=2 THEN PLAY 2,36,4,0,2
180 TM=TM-1:TB=TB-1:Q=Q+1:GOTO 130
1000 REM the tune: a note and its length in sixteenths ("-" a rest), then * ; then the bass
1010 DATA E4,2,G4,2,A4,4,G4,2,E4,2,D4,4,C4,2,D4,2,E4,2,G4,2,A4,4,-,4
1020 DATA A4,2,C5,2,D5,4,C5,2,A4,2,G4,4,E4,2,G4,2,D4,2,E4,2,C4,8
1030 DATA G4,2,A4,2,B4,4,A4,2,G4,2,E4,4,F4,2,E4,2,D4,2,E4,2,G4,4,-,4
1040 DATA C5,2,B4,2,A4,4,G4,2,E4,2,D4,4,E4,2,D4,2,B3,2,D4,2,C4,8,*
1050 DATA C3,8,A2,8,F2,8,G2,8,F2,8,C3,8,G2,8,C3,8
1060 DATA E2,8,A2,8,F2,8,G2,8,F2,8,G2,8,G2,8,C3,8,*
