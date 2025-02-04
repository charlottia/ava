IF 1 = 1 THEN PRINT "true"
PRAGMA PRINTED "true\n"

IF 1 = 2 THEN PRINT "false"
PRAGMA PRINTED ""

PRINT "ok"
PRAGMA PRINTED "ok\n"

IF 1 = 2 THEN PRINT "false" ELSE PRINT "true"
IF 1 = 1 THEN PRINT "true" ELSE PRINT "false"
PRAGMA PRINTED "true\ntrue\n"

IF 1 = 2 THEN
   PRINT "fal";
   PRINT "se"
ELSE
   PRINT "tr";
   PRINT "ue"
END IF
PRAGMA PRINTED "true\n"

LET a% = 1 + 1
LET b# = 2
IF a% = b# THEN PRINT "true"
PRAGMA PRINTED "true\n"

PRINT a% = b#
PRINT a% <> b#
PRAGMA PRINTED "-1\n0\n"

GOTO skip

frango:
PRINT "yippee!"
GOTO endd

skip:

IF 1 = 1 THEN
   PRINT "true/";
   IF 1 = 2 THEN
      PRINT "fal";
      PRINT "se"
   ELSE
      PRINT "tr";
      PRINT "ue"
      GOTO frango
   ENDIF
ELSE
   PRINT "false/";
   IF 1 = 1 THEN
      PRINT "tr";
      PRINT "ue"
   ELSE
      PRINT "fal";
      PRINT "se"
   END IF
END IF

endd:
PRAGMA PRINTED "true/true\nyippee!\n"
