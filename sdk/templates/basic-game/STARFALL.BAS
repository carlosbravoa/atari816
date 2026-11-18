10 REM STARFALL.BAS - a BASIC game template for Horizon BASIC 2.0 (horizon/BASIC.md)
20 REM Catch the falling stars with the basket, let the rocks fall past. The basket and
30 REM everything that falls are sprites (SPRITE, HIT): the program only moves numbers.
40 REM Sounds are made with WAVE and played with PLAY; VSYNC: 60 frames a second. In a
45 REM window a sprite shows only while its whole 16 (or 32) rows are inside: hence 182.
50 REM Arrow keys or joystick 1 move, any key starts; Esc stops the program.
60 SCREEN 320,200:RANDOMIZE:HI=0:DIM SX(7),SY(7),SK(7),SV(7)
70 READ P:IF P>=0 THEN READ H:FOR R=0 TO H-1:READ A$:SHAPE P,R,A$:NEXT:GOTO 70
80 WAVE 0,0,200,50:WAVE 1,4,300,80:WAVE 2,2,700,200
100 REM ---- the title
110 GOSUB 900:COLOR 226:TEXT 100,60,"S T A R F A L L"
120 COLOR 1:TEXT 40,100,"Catch the stars, not the rocks."
130 TEXT 40,116,"Arrows or joystick move."
140 TEXT 40,132,"Any key: start"
150 IF HI>0 THEN TEXT 40,160,"Best: "+STR$(HI)
160 IF INKEY$<>"" THEN 160
170 VSYNC:IF INKEY$="" AND STRIG(0) THEN 170
200 REM ---- a new game
210 SC=0:LV=3:BX=144:T=0:N=3
220 FOR I=1 TO 7:SY(I)=-99:NEXT
230 GOSUB 900:GOSUB 700
300 REM ---- the game loop: one frame
310 S=STICK(0)
320 IF (S AND 4)=0 AND BX>0 THEN BX=BX-4
330 IF (S AND 8)=0 AND BX<288 THEN BX=BX+4
340 SPRITE 0,BX,182,0
350 FOR I=1 TO N
360 IF SY(I)<0 THEN IF RND(30)=0 THEN SX(I)=RND(304):SY(I)=16:SK(I)=1-(RND(4)=0):SV(I)=1+RND(2)+T\1500
370 IF SY(I)>=0 THEN SY(I)=SY(I)+SV(I):IF SY(I)>183 THEN SY(I)=-99:SPRITE I OFF ELSE SPRITE I,SX(I),SY(I),SK(I)
380 NEXT I
390 H=HIT(0):IF H>0 THEN GOSUB 600
400 T=T+1:IF T MOD 600=0 AND N<7 THEN N=N+1
410 IF LV>0 THEN VSYNC:GOTO 310
420 GOTO 1000
600 REM ---- the basket touched thing H: a star scores, a rock costs a life
610 SY(H)=-99:SPRITE H OFF
620 IF SK(H)=1 THEN SC=SC+1:PLAY 0,12+(SC MOD 5)*2,12 ELSE LV=LV-1:PLAY 1,0,15
630 GOSUB 700:RETURN
700 REM ---- the status line
710 COLOR 16:FRECT 0,0,320,14
720 COLOR 1:TEXT 4,1,"SCORE "+STR$(SC)+"   LIVES "+STR$(LV)
730 RETURN
900 REM ---- a sky of tiny stars
910 SPRITE OFF:GCLS 17:FOR I=1 TO 40:COLOR 232+RND(24):PLOT RND(320),16+RND(184):NEXT
920 RETURN
1000 REM ---- game over
1010 SPRITE OFF:PLAY 2,-12,12:IF SC>HI THEN HI=SC
1020 COLOR 1:TEXT 124,84,"GAME OVER":TEXT 112,100,"score "+STR$(SC)
1030 PRINT "Score ";SC;", best ";HI
1040 PAUSE 1000:GOTO 100
2000 REM the pictures: a number, a height, then rows of text art (hex digits are the UI
2010 REM colours: 1 white, 7 dark grey, 8 grey, 9 light grey, C yellow, E orange; . clear)
2020 DATA 0,6,"E..............................E","EE............................EE"
2030 DATA ".EEEEEEEEEEEEEEEEEEEEEEEEEEEEEE.",".E9E9E9E9E9E9E9E9E9E9E9E9E9E9E9.","..EEEEEEEEEEEEEEEEEEEEEEEEEEEE..","...EEEEEEEEEEEEEEEEEEEEEEEEEE..."
2040 DATA 1,9,"....C....","....C....","...CCC...","CCCC1CCCC",".CCC1CCC.","..CCCCC..","..CC.CC..",".CC...CC.","C.......C"
2050 DATA 2,9,"..7777...",".788887..","78889887.","788888887","788898887","78888887.",".7888877.","..77777..","........."
2060 DATA -1
