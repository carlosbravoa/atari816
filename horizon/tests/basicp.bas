REM tests/basicp.bas: (Horizon 0.23) LPRINT and LLIST, run by make test as "basic -t" (as
REM tests/basic.bas). Each print job appears in /Printouts on the card copy; make test
REM compares them with tests/basicp-1.txt .. basicp-7.txt, the output with tests/basicp.txt.
10 REM a run: one job
20 LPRINT "Hello";" ";"printer"
30 LPRINT 1;-2;3.5;1E+10;" ";0.25
40 LPRINT "A","B","C"
50 LPRINT "TAB";TAB(12);"X";SPC(3);"Y"
60 LPRINT "no end";
70 LPRINT " - joined"
80 FOR I=1 TO 3:LPRINT "line ";I:NEXT
90 LPRINT
100 LLIST 20-40
110 PRINT "to the screen"
120 LPRINT "the end"
PRINT "-- LLIST in direct mode: a job of its own"
LLIST
RUN
PRINT "-- an error in a run: the job closed"
NEW
10 LPRINT "before the error"
20 LPRINT "half";1/0
30 LPRINT "never"
RUN
PRINT "-- STOP closes the job, CONT starts a new one"
NEW
10 LPRINT "before STOP"
20 STOP
30 LPRINT "after CONT"
RUN
CONT
PRINT "-- direct LPRINT: a job of its own"
LPRINT "direct";1;2:LPRINT "two lines"
PRINT "-- a break (Esc) closes the job"
NEW
10 LPRINT "before the break";
20 PAUSE 100:GOTO 20
RUN
PRINT "-- reserved: LPRINT, LLIST"
LPRINT=1
LLISTS=2:PRINT LLISTS
DIR "/Printouts"
