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

REM LET a% = 1 + 1
REM LET b# = 2
REM IF a% = b# THEN PRINT "true"
REM PRAGMA PRINTED "true\n"

REM PRINT a% = b#
REM PRINT a% <> b#
REM PRAGMA PRINTED "-1\n0\n"

REM IF 1 = 1 THEN
REM    PRINT "true/";
REM    IF 1 = 2 THEN
REM       PRINT "fal";
REM       PRINT "se"
REM    ELSE
REM       PRINT "tr";
REM       PRINT "ue"
REM    ENDIF
REM ELSE
REM    PRINT "false/";
REM    IF 1 = 1 THEN
REM       PRINT "tr";
REM       PRINT "ue"
REM    ELSE
REM       PRINT "fal";
REM       PRINT "se"
REM    END IF
REM END IF
REM PRAGMA PRINTED "true/true\n"

REM TODO: combine jump targets and if to stress our linking
