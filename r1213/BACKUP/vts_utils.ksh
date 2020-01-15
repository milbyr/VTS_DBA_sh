#!/bin/ksh
################################################################################
#
# vit_utils.ksh
#
################################################################################
#
# Library Functions
#
################################################################################
#
# Who      When      Version       What/Why/How?
################################################################################
#
# RM    00000000        v1.0            Initial Version
# MD    20111109        v1.1            Added FN_multiple_var, FN_string_split
# MD    20111114        v1.2            Added FN_random_password
# RM    20120104        v1.3            Added FN_GetDomain distinguish between Newcastle and Edinburgh
# AP    20130411        v1.4            Added FN_GetOBIUser & FN_GetOBIAPPSUser

#
###
### GENERIC VARIABLES
###
export L_APPSORATAB=${DBA:-/export/vtssupp/vts}/etc/appsoratab
export L_VIT_LOGS=${DBA:-/export/vtssupp/vts}/logs

# BASH doesnt have print...and has a different echo to ksh so alias print
# if needed.
type print >/dev/null 2>&1 || alias print="echo"

###
### GENERIC FUNCTIONS
###

################################################################################
function FN_Print
################################################################################
{
 print "$(date "+%d/%m/%y %H:%M:%S") : $*" | tee -a ${L_LOGFILE:-}
}

################################################################################
function FN_ORACLE_HOME
################################################################################
{
  grep ^$1 /var/opt/oracle/oratab | cut -d: -f2
}


################################################################################
function FN_Debug
################################################################################
{
 if [ ${L_VERBOSE:-x} != x ]
 then
  FN_Print "$*"
 fi
}

################################################################################
function FN_Error
################################################################################
{
 print "$(date "+%d/%m/%y %H:%M:%S") : $*" | tee -a ${L_LOGFILE:-}
}


################################################################################
function FN_PASSWORD_GEN
################################################################################
{
  # To generate a password string by
  # embeding string 2 within string 1
  # at a position determined by a date
  # algorithm.

  l_str_1=${1:?"FN_PASSWROD_GEN: Missing string 1"}
  l_str_2=${2:?"FN_PASSWROD_GEN: Missing string 2"}

  echo "${l_str_1}" | nawk -v sid="${l_str_2}" -v d=`date +%e|sed -e "s/ //g"` -v m=`date +%m` '{ind=(d*m)%6;
    W1=substr($0,1,ind);
    W2=substr($0,ind+1,length($0));
    print  W1  sid  W2 }'

}  ### end of FN_PASSWORD_GEN ###


###
### appsoratab FUNCTIONS
###

###############################################################
function FN_ValidENV
###############################################################
{
 if [ $(grep -c "^${1}:" ${L_APPSORATAB}) -ne 1 ]
 then
  FN_Error "Error Environment ${1} not found in $L_APPSORATAB"
  return 1
 else
  return 0
 fi
}

###############################################################
function FN_ListENVs
###############################################################
{
 grep -v "^#" $L_APPSORATAB | cut -d: -f1
}

###############################################################
function FN_GetPortPool
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f2
 fi
}

###############################################################
function FN_GetDBServer
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f3
 fi
}

###############################################################
function FN_GetOracleSid
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
   echo $1 | sed 's/_DR$//g'
 fi
}

###############################################################
function FN_GetLCOracleSid
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
   echo $1 | sed 's/_DR$//g' | tr '[:upper:]' '[:lower:]'
 fi
}

###############################################################
function FN_GetDBHostID
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  FN_GetDBServer $1 | sed 's/ukepu//'
 fi
}

###############################################################
function FN_GetDBMountPoints
###############################################################
# List of all DB Server mount points
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f4 | sed 's/\,/ /g'
 fi
}

###############################################################
function FN_GetDBCodeMountPoint
###############################################################
# DB Code is always the first mount point specified in appsoratab
###############################################################
{
 # $1 ENV
 if FN_ValidENV $1
 then
  FN_GetDBMountPoints $1 | cut -d\  -f1
 fi
}

###############################################################
function FN_GetDBDBFMountPoint
###############################################################
# DBF files can be specified as the second filesystem in appsoratab
###############################################################
{
 # $1 ENV
 if FN_ValidENV $1
 then
  ###FN_GetDBMountPoints $1 | cut -d\  -f$(FN_GetDBMountPoints $1 | wc -w)
  FN_GetDBMountPoints $1 | cut -d\  -f2
 fi
}

###############################################################
function FN_GetDomain
###############################################################
{
  case $(echo `hostname`|awk '{print substr($0,1,3)}') in
  v10 )
    G_DOMAIN="ncl.emss.gov.uk"
##    echo "the domain name has been set to ncl.emss.gov.uk"
    ;;
  v06)
    G_DOMAIN="edi.emss.gov.uk"
##    echo "the domain name has been set to edi.emss.gov.uk"
    ;;
  *) echo "This is an invalid host"
    ;;
  esac
  export G_DOMAIN
  echo $G_DOMAIN
}

###############################################################
function FN_GetDBDomain
###############################################################
{
  case $(echo `hostname`|awk '{print substr($0,1,3)}') in
  v10 )
    G_DB_DOMAIN="ncl.emss.data.net"
    ;;
  v06)
    G_DB_DOMAIN="edi.emss.data.net"
    ;;
  *) echo "This is an invalid host"
    ;;
  esac
  export G_DB_DOMAIN
  echo $G_DB_DOMAIN
}

###############################################################
function FN_GetCPServer
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f5
 fi
}

###############################################################
function FN_GetCPMountPoint
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f6 | sed -e "s/\,/ /g"
 fi
}

###############################################################
function FN_GetiASMountPoint
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f8 | sed 's/\,/ /g'
 fi
}

###############################################################
function FN_GetAPPSPassword
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f9
 fi
}


###############################################################
function FN_GetORAUser
###############################################################
{
 # $1 ENV

 # if FN_IsEBusinessSuite $1
 if [ "$1" != "MGNT" ]
 then
  echo ora$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//' | sed 's/mans/man/'
 else
  echo vit$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//'
 fi
}

###############################################################
function FN_GetAPPLUser
###############################################################
{
 # $1 ENV

 echo appl$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//' | sed 's/mans/man/'
}

###############################################################
function FN_GetOBIUser
###############################################################
{
 # $1 ENV

 # if FN_IsEBusinessSuite $1
 if [ "$1" != "MGNT" ]
 then
  echo ora$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//' | sed 's/mans/man/'
 else
  echo vit$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//'
 fi
}

###############################################################
function FN_GetOBIAPPUser
###############################################################
{
 # $1 ENV

 # if FN_IsEBusinessSuite $1
 if [ "$1" != "MGNT" ]
 then
  echo obi$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//' | sed 's/mans/man/'
 else
  echo vit$(echo $1 | tr '[:upper:]' '[:lower:]') | sed 's/_dr$//'
 fi
}

###############################################################
function FN_GetiASServer
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f7 | sed 's/\,/ /g'
 fi
}

###############################################################
function FN_IsiASServer
###############################################################
{
 # $1 ENV
 # $2 ServerName

 if [ $# -ne 2 ]
 then
  FN_Error "Error Usage : FN_IsiASServer ENV ServerName"
  return 1
 fi

 if FN_ValidENV $1
 then
  return $((1-$(grep "^${1}:" ${L_APPSORATAB} | cut -d: -f7 | grep -c ${2})))
 fi
}

###############################################################
function FN_ListiASServers
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  FN_GetiASServer $1 | tr ' ' '\n'
 fi
}

###############################################################
function FN_ListServers
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  {
   FN_GetDBServer $1
   FN_GetCPServer $1
   FN_ListiASServers $1
  } | sort -u | tr '\n' ' '
 fi
}

###############################################################
function FN_IsEBusinessSuite
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  [ "$(FN_GetiASServer $1)" != "XX" ]
 fi
}

###############################################################
function FN_List_Vars
###############################################################
{
  for l_var in `env |grep ^L_`
  do
    FN_Print "$l_var"
  done
}

###############################################################
#   reads all the appsoratab fields into variables
function FN_Init_Vars
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
    # 2 Port Pool
    export L_PORT=$(FN_GetPortPool $1)
    # 3 DB Host
    export L_DBSRV=$(FN_GetDBServer $1)
    # 4 DB mount points Oracle_home
    export L_DBMNT=$(FN_GetDBMountPoints $1)
    # 5 CP host
    export L_CPSRV=$(FN_GetCPServer $1)
    # 6 CP mount points
    export L_CPMNT=$(FN_GetCPMountPoint $1)
    # 7 iAS host
    export L_IASSRV=$(FN_GetiASServer $1)
    # 8 iAS mount points
    export L_IASMNT=$(FN_GetiASMountPoint $1)
    # 9 apps password
    export L_APPSPWD=$(FN_GetAPPSPassword $1)
    #10 terminal -  application  colour
    export L_COLOUR=$(FN_GetColourScheme $1)
    #11 workflow mail account
    export L_WFACCT=$(FN_GetWorkflowAccount $1)
    #12 filer name
    export L_FILER=$(FN_GetFiler $1)
    #13 filer snapshots to be kept online
    export L_SNKEEP=$(FN_GetSnapKeep $1)

    # for multiple tiers create additional vars
    #if FN_multiple_var ${L_IASSRV}
    #  then
    #    print "FN_ValidENV: Allocating mtier variables"
    #    FN_Init_mVars L_IASSRV
    #fi

    # database data vol is the 2nd mount point of the DB mount point list
    export L_DBDATAV=$(FN_GetDBDBFMountPoint $1)

    export L_ORAUSER=$(FN_GetORAUser $1)
    export L_ORACLESID=$(FN_GetOracleSid $1)
    export L_LCORACLESID=$(FN_GetLCOracleSid $1)
    export L_APPLUSER=$(FN_GetAPPLUser $1)
    export L_ORACLEHOME=$(FN_ORACLE_HOME $1)
    export L_OBIUSER=$(FN_GetOBIUser $1)
    export L_OBIAPPS=$(FN_GetOBIAPPUser $1)

    export L_DBCONTEXT_NAME=${L_ORACLESID}_${L_DBSRV}
    export L_CPCONTEXT_NAME=${L_ORACLESID}_${L_CPSRV}
    export L_IASCONTEXT_NAME=${L_ORACLESID}_${L_IASSRV}
 fi
}

###
### SSH FUNCTIONS
###

###############################################################
function FN_rexec
###############################################################
{
 # $1 USER
 # $2 SERVER
 # $3 CMD
 ssh $1@$2 "$3"

 L_RET_VALUE=$?

 if [ $L_RET_VALUE -ne 0 ]
 then
  FN_Error "ERROR running ssh $1@$2 \"$3\""
 fi

 return $L_RET_VALUE
}

###############################################################
function FN_CopyFile
###############################################################
{
 # 1 - From/Source Server
 # 2 - To/Dest Server
 # 3 - Absolute path to file

 if [ $# -eq 3 ]
 then
  FN_rexec root $1 "tar cf - $3" | FN_rexec root $2 "tar xvf -"
 else
  FN_Error "ERROR :: Invalid parameters <fromserver> <toserver> <abs path to file> [$*]."
  return 1
 fi
}

###############################################################
function FN_CopyFileGZ
###############################################################
# For larger files...gzip/gunzips file on source/dest servers
###############################################################
{
 # 1 - From/Source Server
 # 2 - To/Dest Server
 # 3 - Absolute path to file

 if [ $# -eq 3 ]
 then
  FN_rexec root $1 "tar cf - $3 | gzip -c" | FN_rexec root $2 "gunzip -c | tar xvf -"
 else
  FN_Error "ERROR :: Invalid parameters <fromserver> <toserver> <abs path to file> [$*]."
  return 1
 fi
}

###############################################################
function FN_PMONCheck
###############################################################
{
 # 1 - ENV
 if FN_ValidENV $1
 then
  if [ $(FN_rexec $(FN_GetORAUser $1) $(FN_GetDBServer $1) "ps -fu \$LOGNAME | grep ora_pmon_$1 | grep -v grep | wc -l " | awk '{ print $1 }') -eq 1 ]
  then
   return 0
  else
   return 1
  fi
 fi
}


###############################################################
function FN_GetColourScheme
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f10
 fi
}

###############################################################
function FN_GetWorkflowAccount
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f11
 fi
}

###############################################################
function FN_GetFiler
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f12
 fi
}

###############################################################
function FN_GetSnapKeep
###############################################################
{
 # $1 ENV

 if FN_ValidENV $1
 then
  grep "^${1}:" ${L_APPSORATAB} | cut -d: -f13
 fi
}

###############################################################
function FN_AddDays
###############################################################
{
 # 1 +/- NDays (-6 to 6)
 # '+ %...' date parameter

 if [ ${1:-0} -gt 6 -o ${1:-0} -lt -6 ]
 then
  print "#Days must be in -6 to 6 range."
  exit
 fi

 L_OLD_TZ=${TZ:-}

 ## L_TZ_AMOUNT=$((0-(${1:-0}*24)))
 L_TZ_AMOUNT=$((0-1-(${1:-0}*24)))

 if [ ${L_TZ_AMOUNT:-0} -gt 0 ]
 then
  TZ=${TZ}+$L_TZ_AMOUNT
 else
  TZ=${TZ}$L_TZ_AMOUNT
 fi

 date "${2:-}"

 TZ=$L_OLD_TZ
}

################################################################################
function FN_MailReport
################################################################################
{
# To
# Subject
# Function to gen body
(
echo "From: vit@innospecinc.com"
echo "To: ${1}"
echo "MIME-Version: 1.0"
echo "Content-Type: multipart/mixed;"
echo ' boundary="bbmailboundary"'
echo "Subject: ${2}"
echo ""
echo "This is a MIME-encapsulated message"
echo ""
echo "--bbmailboundary"
echo "Content-Type: text/html"
echo ""
cat <<MAILBODY
<html>
<style>
h1{
font-family         : arial;
font-size           : 12;
border-bottom-style : solid;
border-bottom-width : 1;
border-bottom-color : black;
}
table{
border-bottom-style     : outset;
border-bottom-width     : 2;
border-bottom-color     : grey;
border-right-style      : outset;
border-right-width      : 2;
border-right-color      : grey;
}
p.info{
font-family      : arial;
font-size        : 11;
background-color : beige;
}
body{
left-margin             : 20;
font-family         : arial;
}
th{
text-align       : left;
font-family      : arial;
font-size        : 11;
font-weight      : normal;
color            : white;
background-color : gray;
}
td{
font-family      : arial;
font-size        : 11;
border-bottom-style : solid;
border-bottom-width : 1;
border-bottom-color : grey;
background-color : beige;
}
td.warning{
font-weight      : bold;
}
td.error{
font-weight      : bold;
font-color       : red;
}
</style>
<body>
$(${3})
</body>
</html>
MAILBODY
echo "--bbmailboundary"
) | /usr/lib/sendmail -r ebssupp@innospecinc.com -t
}

################################################################################
function FN_CheckForError
################################################################################
{
 [ $? -ne 0 ] && export L_SCRIPT_ERROR=1
}


################################################################################
function FN_multiple_var
################################################################################
{
typeset myname=FN_multiple_var
#
if [ "${VEND_TRACE:="FALSE"}" = "TRUE" ]
then
 set -x
fi

if [ $# -eq 0 ]
then
  print "Usage : ${myname} <Variable> "
  return 2
fi

if [ $# -eq 1 ]
then
  return 1
else
  return 0
fi
}

################################################################################
function FN_string_split
################################################################################
{
  L_STR=${1:?"ERROR: FN_string_split: missing string"}
  L_SEP=${2:?"ERROR: FN_string_split: missing separator"}
  L_ID=${3:?"ERROR: FN_string_split: missing id"}
  L_RETURN=`echo "$L_STR" |cut -d${L_SEP} -f${L_ID}`

  echo $L_RETURN
}


################################################################################
function FN_random_password
################################################################################
{
typeset myname=FN_random_password
#
if [ "${VEND_TRACE:="FALSE"}" = "TRUE" ]
then
 set -x
fi

if [ $# -ne 1 ]
then
  print "Usage : ${myname} <Length_of_Random_String (INT)> "
  return 2
fi
#
Length=$1
#
set -A RandArray 0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v q x y z
temp_random_password=""
#
while [ $Length -gt 0 ]
do
  temp_random_password="${temp_random_password}${RandArray[$(($RANDOM%${#RandArray[*]}+1))]}"
  ((Length=Length-1))
done

print $temp_random_password
}

#End of File
