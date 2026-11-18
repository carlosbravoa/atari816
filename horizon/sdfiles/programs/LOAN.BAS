10 REM LOAN.BAS - a loan: the monthly payment and a table year by year (decimal floats)
20 PRINT "Loan calculator (Enter takes the value in brackets)"
30 INPUT "Amount (10000)";A$:P=VAL(A$):IF A$="" THEN P=10000
40 INPUT "Interest per year, % (5.5)";A$:R=VAL(A$):IF A$="" THEN R=5.5
50 INPUT "Years (10)";A$:N=INT(VAL(A$)):IF A$="" THEN N=10
60 I=R/1200:M=N*12
70 IF I=0 THEN Q=P/M ELSE Q=P*I/(1-(1+I)^-M)
80 Q=ROUND(Q,2):PRINT "Monthly payment:";:V=Q:GOSUB 300:PRINT
90 PRINT "Year    Interest   Repayment     Balance"
100 B=P:TI=0
110 FOR Y=1 TO N:YI=0:YP=0
120 FOR K=1 TO 12:IF B<=0 THEN 150
130 J=ROUND(B*I,2):Z=Q-J:IF Z>B OR (Y=N AND K=12) THEN Z=B
140 B=B-Z:YI=YI+J:YP=YP+Z
150 NEXT K:TI=TI+YI
160 PRINT Y;TAB(4);:V=YI:GOSUB 300:V=YP:GOSUB 300:V=B:GOSUB 300:PRINT
170 NEXT Y
180 PRINT "Total interest: ";:V=TI:GOSUB 300:PRINT
190 END
300 REM V with two decimals, right-aligned in 12 columns
310 S$=STR$(ROUND(V,2)):D=INSTR(S$,"."):IF D=0 THEN S$=S$+".00" ELSE IF LEN(S$)-D=1 THEN S$=S$+"0"
320 PRINT SPC(12-LEN(S$));S$;:RETURN
