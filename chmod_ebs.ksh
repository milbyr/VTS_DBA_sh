#!/usr/bin/ksh

##F_SID=${1:-D006}

F_SID=D006
L_SID=$(echo $F_SID | tr "[:upper:]" "[:lower:]" )
export L_SID

for U in ora appl
do
  echo "\nStarting chmod for ${U}${L_SID} - `date`"
  for OFN in `df -g | grep ${U}${L_SID} | awk '{print $7}'`
  do
    echo "\tfind $OFN  \( -type f -o -type d \) -exec chown ${U}${L_SID} {} \; "
    find $OFN  \( -type f -o -type d \) -exec chown ${U}${L_SID} {} \;  &
  done
  echo "Waiting for the chown to ${U}${L_SID} to complete `date`"
  wait
done
echo "The chmod process of ${F_SID} COMPLETE  -  `date`"
