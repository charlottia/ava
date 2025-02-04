10 PRINT "hi"
20 GOTO 40
30 PRINT "yo"
40 PRINT "no"
50 GOTO 8
   PRINT "woah"
 8 PRAGMA PRINTED "hi\nno\n"

' Force a jump over.
LET a% = 0
LET b% = 0

GOTO skip
LET a% = 1 + 2#

above:
LET b% = 2 + 3#
' XXX: The test mentioned in Compiler.compileBinopOperands:
' LET b% = 2 + SomeFn#(3)  ' where SomeFn#(x#) returns x#
GOTO endd

skip:
GOTO above

endd:
PRINT a%; b%
PRAGMA PRINTED " 0  5 \n"
