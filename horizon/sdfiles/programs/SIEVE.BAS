10 REM SIEVE.BAS - the prime sieve benchmark (BYTE magazine, 1981): 10 passes over 8191 flags
20 S=8190:DIM F(8190)
30 PRINT "Sieve of Eratosthenes, 10 passes, flags 0 to ";S
40 T=TIME
50 FOR N=1 TO 10
60 C=0:FOR I=0 TO S:F(I)=1:NEXT I
70 FOR I=0 TO S
80 IF F(I)=0 THEN 120
90 P=I+I+3:K=I+P
100 WHILE K<=S:F(K)=0:K=K+P:WEND
110 C=C+1
120 NEXT I
130 NEXT N
140 T=TIME-T
150 PRINT C;" primes, 10 passes in ";T;" ms (";T/10;" ms a pass)"
