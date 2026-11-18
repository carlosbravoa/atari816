REM tests/basicpe.bas: (Horizon 0.23) a print job that cannot be made (make test puts a file
REM named Printouts on the card copy): "File error $XX", in a run and in direct mode.
10 PRINT "first"
20 LPRINT "to the printer"
30 PRINT "never"
RUN
LPRINT "direct"
LLIST
PRINT "BASIC goes on"
