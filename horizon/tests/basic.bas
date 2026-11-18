REM tests/basic.bas: run by make test as "basic -t" (a script: numbered lines are stored,
REM the others run as if typed; INPUT reads the next line). The output is compared with
REM tests/basic.txt.
RUN "/programs/TESTS.BAS"
NEW
PRINT "-- errors in direct mode"
PRINT 1/0
PRINT 2147483647+1
PRINT "a"+1
PRINT LEFT$("abc")
X=
GOTO 999
RETURN
NEXT
WEND
CONT
PRINT CHR$(256)
DIM D(3):D(4)=1
DIM D(5)
PRINT ASC("")
A$="x":FOR I=1 TO 8:A$=A$+A$:NEXT
PRINT 99999999999
PRINT -32768*65536, -32768*65537
PRINT "-- floats: errors and limits"
PRINT SQR(-1)
PRINT LOG(0)
PRINT 1/0.0
PRINT 1E99*10
PRINT EXP(1000)
PRINT (-8)^(1/3)
PRINT SIN(1E10)
PRINT 0^-1
A%=1E10
DIM H(9000):H(1)=1:H(2)=0.5
PRINT 1E-99/10, -1E-50*1E-50, 9.99999999999E99, 2147483647*2147483647
PRINT 1E10, 1E9, 123456789.123, 0.0001, 0.00001234, -1/7
PRINT "-- errors in a program, LIST"
10 REM a program with an error in a subroutine
20 PRINT "start"
30 GOSUB 100
40 PRINT "not reached"
100 FOR I=1 TO 3:PRINT I;:NEXT:PRINT
110 X=A(11)
120 RETURN
LIST
RUN
LIST 20-30
LIST -20
LIST 110-
NEW
10 GOSUB 10
RUN
10 WHILE 1:READ X:PRINT X;:WEND
20 DATA 1,2,3
RUN
NEW
10 PRINT "stop and cont"
20 STOP
30 PRINT "continued"
RUN
CONT
CONT
NEW
10 INPUT "name";N$:INPUT "two numbers";A,B:PRINT "hello ";N$;", ";A+B
20 INPUT X$,Y:PRINT X$;Y
RUN
Ada
3.5, 4E1
"quoted, text",5
RUN
Bob
x
1,2
plain,  7
NEW
PRINT "-- LIST keeps the program readable"
10 for i=1 to 10 step 2:if i mod 3=0 then print i;" ";else print "-";
20 next i:a$="say "+chr$(34)+"hi"+chr$(34):print a$:? left$(a$, 3), $ff, &h10
30 data 1, "two, three" ,four:rem done
40 on x gosub 100,200:while not (a<>b and c>=d or e<=f xor g):wend
50 print tab(5);"x";spc(2);-abs(-3)^2 mod 7:' comment
60 x=.5e-3+1.25:y%=x*1e6:z=1e-20:deg:print x;" ";y%;" ";2/3;" ";-z;" ";7\2;sin(30):rad
LIST
RUN
PRINT "-- SAVE, NEW, LOAD"
SAVE "/T1.BAS"
NEW
LIST
LOAD "/T1"
LIST 10
LOAD "/NOSUCH.BAS"
LIST 10
PRINT "-- file names without quotes"
SAVE /T2
NEW
LOAD /t2
LIST 10
NEW
10 PRINT "run by name"
20 RUN /T1:REM a stored line keeps its name
LIST
SAVE /T3.BAS
NEW
RUN /t3.bas
NEW
RUN /NOSUCH
LIST
A$="/T3":LOAD A$
LIST 10
RUN 5
RUN X
PRINT "-- direct loops"
FOR I=1 TO 3:PRINT I*I;:NEXT:PRINT
I=0:WHILE I<3:I=I+1:PRINT "w";I;:WEND:PRINT
PRINT "-- benchmarks (emulated time)"
NEW
10 T=TIME:FOR I=1 TO 100000:NEXT I:T=TIME-T
20 PRINT "empty FOR loop, 100000 times: ";T;" ms"
30 DIM A(1000):T=TIME:FOR I=1 TO 100000:A(I MOD 1000)=I*3+7:NEXT I:T=TIME-T
40 PRINT "arithmetic and an array store, 100000 times: ";T;" ms"
50 T=TIME:FOR I=1 TO 10000:Y=SIN(I):NEXT:T=TIME-T:PRINT "10000 x SIN: ";T;" ms"
60 T=TIME:FOR I=1 TO 10000:Y=SQR(I):NEXT:T=TIME-T:PRINT "10000 x SQR: ";T;" ms"
70 T=TIME:S=0:X=1.5:FOR I=1 TO 10000:S=S*0.5+X*1.25:NEXT:T=TIME-T
80 PRINT "float multiply-add, 10000 times: ";T;" ms"
90 T=TIME:N=0:FOR Y=-1 TO 1 STEP 0.1:FOR X=-2 TO 0.5 STEP 0.1:A=0:B=0:K=0
100 IF K<30 AND A*A+B*B<4 THEN C=A*A-B*B+X:B=2*A*B+Y:A=C:K=K+1:N=N+1:GOTO 100
110 NEXT X,Y:T=TIME-T:PRINT "Mandelbrot, 546 points, ";N;" iterations: ";T;" ms"
RUN
PRINT "-- the end"
