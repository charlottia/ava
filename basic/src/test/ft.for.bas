FOR i = 1 TO 3
   PRINT i
NEXT i
PRINT i

PRAGMA PRINTED " 1 \n 2 \n 3 \n 4 \n"

FOR i = 1 TO 3 STEP .5
   PRINT i
NEXT i
PRINT i

PRAGMA PRINTED " 1 \n 1.5 \n 2 \n 2.5 \n 3 \n 3.5 \n"
