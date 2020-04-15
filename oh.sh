#!/usr/bin/bash


## /orad003/global_inventory/ContentsXML/inventory.xml
#
GI=`awk -F= '/^inventory_loc/ {print $2}' /etc/oraInst.loc`
GI_XML=${GI}/ContentsXML/inventory.xml


function get_sids  
{

  awk -F: ' ! /^#/  && ! /^$/  {print tolower($1)}' /export/vtssupp/VTS/etc/appsoratab|sort

} ### end of get_sids ###

function print_header
{
  awk ' BEGIN {
    printf "\n%30s  %30s\n", "Home Name", "Location";
    printf "------------------------------------- ---------------------------------------\n";
  }'

}   ### end of print_header ###



function check_homes
{
  
  grep $1 $GI_XML | awk ' BEGIN {
    NSID="";
    CNT=0;
  }
  
  /HOME NAME/ { 
    split($2,h,"=");
    split($3,l,"=");
    split(l[2],u,"/");
    split($5,i,"=");
    split($6,r,"=");

    OSID=substr(u[2],length(u[2])-3,4);
    gsub(/\"|\"[>]|\"\/>/, "", i[2]);

    printf "%s %-50s %-50s %-10s\n", i[2], h[2], l[2], r[1];

    CNT = CNT + 1;
  }
  END {
    if ( CNT != 9  && CNT > 0 ) {
      print "###\t\t\tThere are some Oracle Homes MISSING (" CNT ")\t\t\t###";
    }
    else
      print "\t\t\t--- This is OK (" CNT ") ---";
  }'

} ### end of check_homes ###


##   - - - - MAIN - - - - ##

  SID=`echo $1 |tr "[:upper:]" "[:lower:]"`

  print_header

  if [ ! "$SID" == "" ]; then
    check_homes $SID
  else
    for l_sid in $(get_sids)
    do
      print "\nProcessing $l_sid"
      check_homes $l_sid
    done
  fi
