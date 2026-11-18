10 REM SPRITES.BAS - bouncing balls for Horizon BASIC 2.0: pictures drawn as text (SHAPE),
20 REM moved by the hardware (SPRITE), a sound at every bounce (WAVE, PLAY), one step a
30 REM frame (VSYNC). Positions are kept in eighths of a pixel. Esc stops.
40 SCREEN 320,200:GCLS 17:COLOR 59:FRECT 0,186,320,14:RANDOMIZE
50 FOR P=0 TO 2:FOR R=0 TO 11:READ A$:SHAPE P,R,A$:NEXT R,P
60 WAVE 0,2,300,60:WAVE 1,0,90,20:REM a triangle bounce, a short sine tick
70 N=9:DIM X(N),Y(N),U(N),V(N)
80 FOR I=0 TO N-1:X(I)=RND(290)*8:Y(I)=RND(120)*8:U(I)=RND(25)-12:V(I)=0:NEXT
90 COLOR 1:TEXT 4,4,"SPRITE, HIT, PLAY: Esc stops"
100 REM ---- each frame: fall, bounce off the floor and the walls, show
110 FOR I=0 TO N-1
120 V(I)=V(I)+3:Y(I)=Y(I)+V(I):X(I)=X(I)+U(I)
130 IF Y(I)>1392 THEN Y(I)=1392:V(I)=-V(I)*7\8:PLAY 0,-V(I)\10,MIN(15,-V(I)\6),X(I)\160-9
140 IF X(I)<0 OR X(I)>2464 THEN U(I)=-U(I):X(I)=X(I)+U(I):PLAY 1,12,8,SGN(U(I))*-12
150 IF V(I)>-24 AND Y(I)=1392 THEN V(I)=-80-RND(40)
160 SPRITE I,X(I)\8,Y(I)\8,I MOD 3,(I=0)*-4
170 NEXT I
180 VSYNC:GOTO 110
1000 REM three balls, 12 x 12: the hex digits are colours (B red, A blue, C yellow, 1 white)
1010 DATA "....BBBB....","..BBBBBBBB..",".BB11BBBBBB.",".B111BBBBBB.","BBB1BBBBBBBB","BBBBBBBBBBBB"
1020 DATA "BBBBBBBBBBBB","BBBBBBBBBBBB",".BBBBBBBBBB.",".BBBBBBBBBB.","..BBBBBBBB..","....BBBB...."
1030 DATA "....AAAA....","..AAAAAAAA..",".AA11AAAAAA.",".A111AAAAAA.","AAA1AAAAAAAA","AAAAAAAAAAAA"
1040 DATA "AAAAAAAAAAAA","AAAAAAAAAAAA",".AAAAAAAAAA.",".AAAAAAAAAA.","..AAAAAAAA..","....AAAA...."
1050 DATA "....CCCC....","..CCCCCCCC..",".CC11CCCCCC.",".C111CCCCCC.","CCC1CCCCCCCC","CCCCCCCCCCCC"
1060 DATA "CCCCCCCCCCCC","CCCCCCCCCCCC",".CCCCCCCCCC.",".CCCCCCCCCC.","..CCCCCCCC..","....CCCC...."
