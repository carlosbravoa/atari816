10 REM SCROLLER.BAS - Horizon BASIC 2.0 full screen: 320 x 180 (SCREEN 1) over a world of
20 REM 640 x 360 (a ring: it wraps around; here only sideways) (SCROLL), a fixed panel at the top (PANEL),
30 REM colour bands from the raster table (RASTER), a house drawn once and copied by the
40 REM blitter (GET, PUT), a sprite. Arrows or joystick 1 fly, Space stops; Esc ends.
50 SCREEN 1,640,360:RANDOMIZE 3
60 GCLS 20:REM the sky is colour 20: RASTER gives it a new colour every few lines
70 FOR I=1 TO 250:COLOR 236+RND(20):PLOT RND(640),RND(250):NEXT
80 FOR Y=-14 TO 14:W=SQR(196-Y*Y):COLOR 230:LINE 470-W,70+Y,470+W,70+Y:NEXT:REM the moon
90 REM hills all around: a ring, the last one meets the first
100 X0=0:Y0=270:FOR X=40 TO 640 STEP 40:Y=230+RND(60):IF X=640 THEN Y=270
110 COLOR 22:FOR XX=X0 TO X-1:LINE XX,Y0+(Y-Y0)*(XX-X0)\40,XX,359:NEXT XX:X0=X:Y0=Y:NEXT X
120 REM a house, drawn once, copied with PUT (colour 0 left out: the hills show through)
130 COLOR 0:FRECT 0,0,24,24:COLOR 94:FRECT 2,10,20,14:COLOR 160:FOR I=0 TO 9:LINE 12-I,I,12+I,I:NEXT
140 COLOR 226:FRECT 6,14,4,4:FRECT 14,14,4,4:GET 0,0,0,24,24:COLOR 20:FRECT 0,0,24,24
150 FOR I=0 TO 11:PUT 0,I*53+8,300+RND(30),0:NEXT
160 COLOR 16:FRECT 0,360,320,16:COLOR 12:TEXT 4,362,"SCROLLER":COLOR 1:TEXT 92,362,"arrows fly, Esc ends"
170 PANEL -16:REM the top 16 rows show the panel (rows 360-375 of the world), not scrolled
180 PALETTE 20,0,0,60:FOR I=1 TO 15:RASTER 16+I*10,20,I*6,I*4,60+I*8:NEXT:REM the sky: 16 bands
190 FOR P=0 TO 1:FOR R=0 TO 6:READ A$:SHAPE P,R,A$:NEXT R,P
200 SX=0:SY=110:VX=2:VY=0
210 REM ---- each frame: the controls, the camera, the ship
220 S=STICK(0)
230 IF (S AND 4)=0 AND VX>-6 THEN VX=VX-1
240 IF (S AND 8)=0 AND VX<6 THEN VX=VX+1
250 IF (S AND 1)=0 AND VY>-4 THEN VY=VY-1
260 IF (S AND 2)=0 AND VY<4 THEN VY=VY+1
270 IF STRIG(0)=0 THEN VX=0:VY=0
280 SX=SX+VX:SY=MAX(0,MIN(196,SY+VY)):SCROLL SX,SY
290 SPRITE 0,144,92,(FRAME AND 4)\4,4-(VX<0)
300 VSYNC:GOTO 220
1000 REM the ship, 16 x 7, two pictures (the flame flickers); hex digits are colours
1010 DATA ".......999......","....9999AA99....","EC99999999999999","CE9999999999999.","EC9999999999999.","....99999999....","......9999......"
1020 DATA ".......999......","....9999AA99....","CE99999999999999","EC9999999999999.","CE9999999999999.","....99999999....","......9999......"
