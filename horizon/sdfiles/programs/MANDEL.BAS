10 REM MANDEL.BAS - the Mandelbrot set in 256 colours (floating point: under two minutes)
20 W=160:H=120:M=32:SCREEN W,H:GCLS 0
30 REM colours 192-223 for the escape counts: dark blue, violet, then yellow
40 FOR K=0 TO M-1:T=K/(M-1):R=255*SQR(T):G=255*T*T:B=60+195*SIN(T*PI)
50 PALETTE 192+K,R,G,B:NEXT
60 X0=-2.2:DX=3/W:DY=2.4/(H-1):Y0=-DY*(H-1)/2
70 T=TIME:FOR PY=0 TO (H-1)/2:Y=Y0+PY*DY:Y2=Y*Y
80 FOR PX=0 TO W-1:X=X0+PX*DX
90 REM inside the main cardioid or the bulb on its left: no need to iterate
100 Q=(X-0.25)^2+Y2:IF Q*(Q+X-0.25)<=Y2/4 OR (X+1)^2+Y2<=0.0625 THEN K=M:GOTO 140
110 A=0:B=0:K=0
120 A2=A*A:B2=B*B:IF A2+B2<4 AND K<M THEN B=2*A*B+Y:A=A2-B2+X:K=K+1:GOTO 120
140 IF K<M THEN COLOR 192+K ELSE COLOR 0
150 PLOT PX,PY:PLOT PX,H-1-PY:NEXT PX,PY
160 PRINT "Done in ";INT((TIME-T)/1000);" s. Press a key"
170 K$="":WHILE K$="":K$=INKEY$:WEND
