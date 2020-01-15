#!/bin/ksh -x
################################################################################
# vts_housekeep_files.ksh
#################################################################################
#
# manage files  determined by a driver file /export/vtssupp/VTS/etc/housekeep_files.drv
#
################################################################################
#
# Version  Who          When           Why/How/What
# 1.0   R Milby    04/09/09       Initial Creation
# 1.1   R Milby    22/12/14	ported from Solaris (EMSS)
################################################################################

#    This file is used to identify housekeeping duties
# Fields
#   1   flag (Y/N)  what to execute
#   2   Envs (DEV|TST|UAT|NONPRD|PRD|ALL) where to run
#   3   Tier (D |C|I) for the database concurrent or application tiers
#   4   locator (I|E|V) for init.ora, environment variable, variable string
#   5   location value
#   6   file/dir format string
#   7   task (R | P) for rotate or purge
#   8   keep - days to keep online
#   9   level (A | C }  all or Current.  Used for purging
#   10  type (F | D) file or directory.  Used for purging
#
# Examples
#  Y:DEV1:D:V:/u05/oradev1/dev1db/10.2/admin/DEV1_erpdb41/cdump:core*:P:0:A:D
#
# This executes on the database tier server that hosts DEV1 using the variable "/ u05/oradev1/dev1db/10.2/admin/DEV1_erpdb41/cdump"
# to remove all directories matching "core*" and their sub-directories and files which are over 0 days old.
#
#
#  Y:DEV1:D:I:background_dump_dest:alert_DEV1.log:R:3:C:F
#
# This executes on the database tier server that hosts DEV1 using the init*.ora file parameter background_dump_dest to determine
# the path, then copying the contents of the file alert_DEV1.log to a time stamped file.  The history files over 3 days old will
# be removed
#

export DBA=/export/vtssupp/VTS
. $DBA/bin/vts_utils.ksh

export L_VERBOSE="X"
L_DRV_FN=$DBA/etc/housekeep_files.drv

L_LN="=================================================================="
L_LN2="################################################################################"



function fn_error
{
  G_STATUS=1
  FN_Print "$L_LN2\n\tERROR: $1\n$L_LN2"

}  ### end of fn_error


################################################################################
function FN_Usage
################################################################################
{
 FN_Print "Usage ${L_SCRIPT_NAME} -e <ENV>"
 FN_Print " -e : Mandatory parameter."
 FN_Print "      Environment listed in ${L_VOLUMETAB:-velos.cfg} file."
 FN_Print ""
 exit 1
}

################################################################################
function FN_Init
################################################################################
#
# Standard Initialise Function
#  parse -e parameter.
#  source vts_utils.ksh and vts_vol_utils.ksh libraries.
#
################################################################################
{
###
### Debug Mode #
export L_VERBOSE=1
### Debug Mode #
###

 # Default the parameter file. Overridden by -e ENV parameter.
 # L_PARAM_FILE=${L_SCRIPT_BASE:-}_params.ksh

 if ! tty -s
 then
  . $HOME/.profile >/dev/null 2>&1
 fi

 # Source vts_utils.ksh file
 if [ -f ${L_SCRIPT_DIR:-}/vts_utils.ksh ]
 then
  . ${L_SCRIPT_DIR:-}/vts_utils.ksh
  FN_Debug "Sourced the vts_utils functions."
 else
  L_USAGE_ERROR=1
  echo "Cannot find utils file ${L_SCRIPT_BASE:-}/vts_utils.ksh"
 fi

  export  G_DRV_ROW_CNT=0

  #   export Global parameters
  export  G_EXE=""
  export  G_ENV=""
  export  G_TIER=""
  export  G_STR_TYPE=""
  export  G_STR=""
  export  G_PATTERN=""
  export  G_TASK=""
  export  G_KEEP_DAYS=""
  export  G_ACTION_LEVEL=""
  export  G_PURGE_TYPE=""

  export  G_THOSTS=""
  export  G_TUSER=""
  export  G_TPATH=""

 export L_KEEP=${L_KEEP:-3}

 # Usage and more debug information
## [ ${L_USAGE_ERROR:-0} -ne 0 ] && FN_Usage

 FN_Debug "Parameters ... "
 env | grep "^L_" | while read L_ENV
 do
  FN_Debug " $L_ENV"
 done

 export L_CONC_FLAG=$DBA/log/${L_SCRIPT_BASE}.RUNNING

 FN_Print "Ensure that only one copy of this script is running."
 if [ -f $L_CONC_FLAG ]
 then
  FN_Error "ERROR :: Only ONE instance of this script can be running at once."
  FN_Error "\"$L_CONC_FLAG\" flag file exists."
  ps -fu $LOGNAME | grep -v vi | grep -v grep | grep $L_SCRIPT_NAME
  return 1
 fi

 touch $L_CONC_FLAG
 if [ $? -ne 0 ]
 then
  FN_Error "ERROR :: Could not create \"\" flag file."
  return 1
 fi

}

################################################################################
function FN_ENV_Check
################################################################################
{
 FN_Debug "FN_ENV_Check:: Start"
 FN_Debug "Checks appsoratab for $G_ENV environment"
 grep "^$G_ENV:" $L_APPSORATAB |cut -d: -f1
 if [ $? -ne 0 ]; then
  fn_error "FN_ENV_Check: value $G_ENV DOES NOT exist"
 else
  FN_Debug "FN_ENV_Check: value $G_ENV exists"
 fi
 FN_Debug "FN_ENV_Check:: End"
}


################################################################################
function FN_Tier_Check
################################################################################
{
 FN_Debug "FN_Tier_Check:: Start :: $G_TIER"
 case $G_TIER in
  "D")  FN_Debug "\tdatabase tier"
    ;;
  "C")  FN_Debug "\tadmin/concurrent tier"
    ;;
  "I")  FN_Debug "\tIAS tier"
    ;;
  *)  fn_error "\tThe G_TIER $G_TIER is not valid"
  ;;
 esac
 FN_Debug "FN_Tier_Check:: End"
}


################################################################################
function FN_Str_Type_Check
################################################################################
{
 FN_Debug "FN_Str_Type_Check:: Start :: $G_STR_TYPE"
 case $G_STR_TYPE in
  "I") FN_Debug "\tThe string type is looking in init.ora files"
    ;;
  "E") FN_Debug "\tThe string type is an environmetal variable"
    ;;
  "V") FN_Debug "\tThe string type is a variable"
    ;;
  *)  fn_error "\tThe G_STR_TYPE $G_STR_TYPE is NOT allowed"
    ;;
  esac
 FN_Debug "FN_Str_Type_Check:: End"
}


################################################################################
function FN_Task_Check
################################################################################
{
 FN_Debug "FN_Task_Check:: Start :: $G_TASK"
 case $G_TASK in
  "P") FN_Debug "\tThe instruction is to purge"
    ;;
  "R") FN_Debug "\tThe instruction is to rotate"
    ;;
  "Z") FN_Debug "\tThe instruction is to compress"
    ;;
  *) fn_error "\tThe G_TASK $G_TASK is and error"
    ;;
 esac
 FN_Debug "FN_Task_Check:: End"
}


################################################################################
function FN_Action_Level_Check
################################################################################
{
 FN_Debug "FN_Action_Level_Check:: Start :: $G_ACTION_LEVEL"
 case $G_ACTION_LEVEL in
  "A") echo "\tThis is going to purge ALL subdirectories-levels"
    ;;
  "C") echo "\tThis is just going to deal the the current level"
    ;;
  *) fn_error "\tThe G_ACTION_LEVEL $G_ACTION_LEVEL is an error"
    ;;
 esac
 FN_Debug "FN_Action_Level_Check:: End"
}


################################################################################
function FN_PURGE_TYPE_Check
################################################################################
{
 FN_Debug "FN_PURGE_TYPE_Check:: Start $G_PURGE_TYPE"
 case $G_PURGE_TYPE in
  "F") FN_Debug "\tThe purge type is for files"
  ;;
  "D" )  FN_Debug "\tThe purge type is for directories"
  ;;
  *) fn_error "\tThis is an error"
  ;;
 esac

 FN_Debug "FN_PURGE_TYPE_Check:: End"
}


################################################################################
function FN_Host_details_get
################################################################################
{
 FN_Debug "FN_Host_details_get:: Start"
  # a quick fix to address the live and live_dr accounts
  L_LC_ENV=`echo $G_ENV | tr "[:upper:]" "[:lower:]"| sed -e "s/_dr//"`
  FN_Debug "\tThe lower case G_ENV ($G_ENV) is $L_LC_ENV"
  case $G_TIER in
   "D") L_HFIELD=3
        L_USER="ora$L_LC_ENV"
    ;;
   "C") L_HFIELD=5
        L_USER="appl$L_LC_ENV"
    ;;
   "I") L_HFIELD=7
        L_USER="appl$L_LC_ENV"
    ;;
  *) FN_Error "what"
  ;;
esac
  FN_Debug "\tThe user account is $L_USER"
  G_THOSTS=`grep "^${G_ENV}:" $L_APPSORATAB | cut -d: -f$L_HFIELD`
  G_TUSER=$L_USER
  FN_Debug "\tThe host is $G_THOSTS using account $G_TUSER"
 FN_Debug "FN_Host_details_get:: End"
}


################################################################################
function FN_Path_Initora_Get
################################################################################
{
 FN_Debug "FN_Path_Initora_Get:: Start :: $G_TUSER $G_THOSTS $G_STR"

  # for some reason this is stopping the other iterations #
  L_DIR_DEST=$(FN_rexec $G_TUSER $G_THOSTS ". .profile; nawk -F= -v pdir=$G_STR '\$1 ~ pdir {print \$2}' \$ORACLE_HOME/dbs/init\${ORACLE_SID}.ora \$ORACLE_HOME/dbs/\${ORACLE_SID}_${G_THOSTS}_ifile.ora | sed -e \"s/ //g\" 2>/dev/null")

  if [ -z $L_DIR_DEST ]; then
    case $G_STR in
      "audit_file_dest" )
        L_DIR_DEST=$(FN_rexec $G_TUSER $G_THOSTS ". .profile;echo \$ORACLE_HOME/rdbms/audit")
      ;;
    *) FN_Debug "\tG_STR $G_STR not found"
      ;;
    esac
  fi

  G_TPATH=$L_DIR_DEST
  FN_Debug "\tG_TPATH=$G_TPATH"
  FN_Debug "FN_Path_Initora_Get :: End"
}

################################################################################
function FN_Get_Path_envirvar
################################################################################
{
 FN_Debug "FN_Get_Path_envivar:: Start $G_THOSTS $G_TUSER $G_STR"

 ## R.M 20080815 added the floowing to only use the initial host in a multi host string ##
 L_H=`echo $G_THOSTS |awk -F, '{print $1}'`

 L_DIR_DEST=$(FN_rexec $G_TUSER $L_H ". ./.profile; echo \"$G_STR\" ")

 FN_Debug "\tL_DIR_DEST=$L_DIR_DEST"

 if [ -z $L_DIR_DEST ]; then
   FN_Error "L_DIR_DEST is not set"
 fi

 G_TPATH=$L_DIR_DEST
 FN_Debug "\tG_TPATH is now $G_TPATH"
 FN_Debug "FN_Get_Path_envvar :: End"
}


################################################################################
function FN_Path_Get
################################################################################
{
 FN_Debug "FN_Path_Get:: Start"
 if [ "${G_TIER}${G_STR_TYPE}" = "DI" ]; then
  L_VALUE="I"
 else
  if [ "$G_STR_TYPE" = 'I' ]; then
   fn_error "\tonly the database has the init.ora files"
   L_VALUE="ZZZZZ"
  else
   L_VALUE="$G_STR_TYPE"
  fi
 fi

 ### case ${G_TIER}${G_STR_TYPE} in
 case ${L_VALUE} in
  "I") FN_Debug "\tLooking up the init.ora files for $G_STR"
     FN_Path_Initora_Get
  ;;
  "E") FN_Debug "\tLooking up the environment for $G_STR"
    FN_Get_Path_envirvar
  ;;
  "V") FN_Debug "\tUsing the variable $G_STR as the path"
    G_TPATH="$G_STR"
  ;;
  *) fn_error "what"
  ;;
 esac

 FN_Debug "\tThe path is now set to $G_TPATH"
 FN_Debug "FN_Path_Get:: End"
}


################################################################################
function FN_Execute
################################################################################
{
 FN_Debug "FN_Execute:: Start"
 FN_Debug "FN_Execute:: End"
}


################################################################################
function FN_Purge_Files
################################################################################
{
 FN_Debug "FN_Purge_Files :: Start"
 if [ "$G_ACTION_LEVEL" = "A" ]; then
   L_PRUNE=""
 else
   L_PRUNE="-prune"
 fi


 case $G_PURGE_TYPE in
  "F") L_REMOVE="rm"
    FN_Debug "\tThe purge type is for files"
    L_LS="ls -1"
    ;;
  "D" )L_REMOVE="rm -rf"
    L_LS="ls -d"
  ;;
  *) fn_error "\tThis is an error"
    L_REMOVE="ls"
  ;;
 esac


## mutilple strings

  L_NAME_PATTERN=` echo "$G_PATTERN" | sed -e "s/,/\" -o -name \"/g"`
  L_NAME_PATTERN="\( -name \"${L_NAME_PATTERN}\" \)"
  FN_Debug "\tThe l_name_pattern is $L_NAME_PATTERN"

#####
 FN_Debug "\tThe remove command is $L_REMOVE"
 FN_Debug "find $G_TPATH ${L_NAME_PATTERN} $L_PRUNE -mtime +$G_KEEP_DAYS -exec ${L_REMOVE} {} \;"

 #  Check to see if there are multiple hosts in G_THOSTS
 FN_Debug "\tThe G_HOSTS parameter is set to >${G_THOSTS}<"
 for L_H in `echo $G_THOSTS | sed -e "s/,/ /g"`
 do
   FN_Debug "\tNow purging on $L_H as user $G_TUSER"

   FN_rexec $G_TUSER $L_H "
     if [ -d ${G_TPATH} ];  then
       echo Directory ${G_TPATH} exists for $G_STR.
       # aud file do not like *${G_PATTERN}*
       cd $G_TPATH && find $G_TPATH $L_NAME_PATTERN $L_PRUNE -mtime +${G_KEEP_DAYS} -exec $L_LS {} \; | while read l_name
       do
        echo ${L_REMOVE} \$l_name
        ${L_REMOVE} \$l_name
       done
     else
      FN_Error \"ERROR :: The dir ${G_TPATH} does not exist\"
     fi
   "
 done

 FN_Debug "FN_Purge_Files :: End"
}

################################################################################
function FN_Rotate_Files
################################################################################
{
 FN_Debug "FN_Rotate_Files :: Start"

 L_DAY=`date +'%Y%m%d'`
 FN_Debug "\tThe L_DAY value is $L_DAY"

 if [ "$G_ACTION_LEVEL" = "A" ]; then
   L_PRUNE=""
 else
   L_PRUNE="-prune"
 fi


  if ( echo $G_PATTERN | grep "*" )
  then
    FN_Debug  "\tThe G_PATTERN has a wild character as is being localised"
    L_PATTERN=`echo $G_PATTERN | sed -e "s/*/$G_ENV/"`
  else
    FN_Debug "\tThe G_PATTERN has no wild char"
    L_PATTERN="$G_PATTERN"
  fi

  FN_Debug "\tL_PATTERN is currently set to $L_PATTERN"

  #  Check to see if there are multiple hosts in G_THOSTS
  for L_H in `echo $G_THOSTS | sed -e "s/,/ /g"`
  do
   FN_Debug "\tNow rotating $L_PATTERN on $L_H"

   FN_rexec $G_TUSER $L_H "
     if [ -d ${G_TPATH} ];  then
       echo Directory ${G_TPATH} exists for $G_STR.
       cd $G_TPATH
       cp $L_PATTERN ${L_PATTERN}_$L_DAY
       cat /dev/null >  $L_PATTERN
       echo \"\tBefore the cleanup\"
       ls -altr ${L_PATTERN}*
       find . -name \"${L_PATTERN}*\" -mtime +$G_KEEP_DAYS -exec rm {} \;
       echo \"\tAfter the cleanup\"
       ls -altr ${L_PATTERN}*
     else
      FN_Error \"ERROR :: The dir ${G_TPATH} does not exist\"
     fi
   "
  done

 FN_Debug "FN_Rotate_Files :: End"
}

################################################################################
function FN_Compress_Files
################################################################################
{
  FN_Debug "FN_Compress_Files :: Start"

  L_DAY=`date +'%Y%m%d'`
  FN_Debug "\tThe L_DAY value is $L_DAY"

  if [ "$G_ACTION_LEVEL" = "A" ]; then
    L_PRUNE=""
  else
    L_PRUNE="-prune"
  fi

  if ( echo $G_PATTERN | grep "*" )
  then
    FN_Debug  "\tThe G_PATTERN has a wild character as is being localised"
    L_PATTERN="$G_PATTERN"
  else
    FN_Debug "\tThe G_PATTERN has no wild char"
    L_PATTERN="$G_PATTERN"
  fi

  FN_Debug "\tL_PATTERN is currently set to $L_PATTERN"

  #  Check to see if there are multiple hosts in G_THOSTS
  for L_H in `echo $G_THOSTS | sed -e "s/,/ /g"`
  do
   FN_Debug "\tNow compressing $L_PATTERN on $L_H"

   FN_rexec $G_TUSER $L_H "
     if [ -d ${G_TPATH} ];  then
       echo Directory ${G_TPATH} exists for $G_STR.
       cd $G_TPATH
       echo \"\tBefore the compression\"
       ls -altr ${L_PATTERN}*
       #### find . -name \"${L_PATTERN}*\" -mtime +${G_KEEP_DAYS} | -exec gzip {} \;
       find . -name \"${L_PATTERN}*\" -mtime +${G_KEEP_DAYS} | xargs gzip
       echo \"\tAfter the compression\"
       ls -altr ${L_PATTERN}*
     else
      FN_Error \"ERROR :: The dir ${G_TPATH} does not exist\"
     fi
   "
  done

 FN_Debug "FN_Compress_Files :: End"
}


################################################################################
function FN_Process
################################################################################
{
 FN_Debug "$L_LN"
 FN_Debug "FN_Process :: Start :: $G_EXE $G_ENV $G_TIER $G_STR_TYPE $G_STR $G_PATTERN $G_TASK $G_KEEP_DAYS $G_ACTION_LEVEL"
 FN_Debug "$L_LN"

  case $G_TASK in
    "P") FN_Purge_Files
      ;;
    "R") FN_Rotate_Files
     ;;
    "Z") FN_Compress_Files
     ;;
    *) FN_Error "wrong task"
      ;;
  esac

 FN_Debug "$L_LN"
 FN_Debug "FN_Process :: End"
 FN_Debug "$L_LN"
}

################################################################################
function FN_Main
################################################################################
{
set -x
 if FN_Init $*
 then

  FN_Print "$L_LN2"
  FN_Debug "Start"
  FN_Print "$L_LN2"

  FN_Debug "Start"

  FN_Debug "Checking to see if the driver file ( $L_DRV_FN ) exists"
  if [ -f $L_DRV_FN ]; then
    L_ROW_IND=0

    for L_DRV_LN in `grep -v ^# $L_DRV_FN`
     do
       G_EXE=$(echo $L_DRV_LN | awk -F: '{print $1}' )
       G_ENV=$(echo $L_DRV_LN | awk -F: '{print $2}' )
       G_TIER=$(echo $L_DRV_LN | awk -F: '{print $3}' )
       G_STR_TYPE=$(echo $L_DRV_LN | awk -F: '{print $4}' )
       G_STR="$(echo $L_DRV_LN | awk -F: '{print $5}' )"
       G_PATTERN="$(echo $L_DRV_LN | awk -F: '{print $6}' )"
       G_TASK=$(echo $L_DRV_LN | awk -F: '{print $7}' )
       G_KEEP_DAYS=$(echo $L_DRV_LN | awk -F: '{print $8}' )
       G_ACTION_LEVEL=$(echo $L_DRV_LN | awk -F: '{print $9}' )
       G_PURGE_TYPE=$(echo $L_DRV_LN | awk -F: '{print $10}' )

        case $G_EXE in
          "N") FN_Debug "\tThis line has not to be run"
           ;;

          "Y")
             ((L_ROW_IND=L_ROW_IND+1))
             FN_Debug "\t$L_LN\n\t\tFor loop iteration $L_ROW_IND"
             FN_Debug "\t\t$G_EXE $G_ENV $G_TIER $G_STR_TYPE $G_STR $G_PATTERN $G_TASK $G_KEEP_DAYS $G_ACTION_LEVEL\n"

             FN_ENV_Check
             FN_Tier_Check
             FN_Str_Type_Check
             FN_Task_Check
             FN_Action_Level_Check
             FN_PURGE_TYPE_Check
             FN_Host_details_get
             FN_Path_Get
             FN_Process
          ;;

         "G")
           for new_g_env in `grep -v ^#  $L_APPSORATAB | grep $G_ENV | awk -F: '{print $1}'`
           do
             G_ENV=$new_g_env
             echo  "Now processing $G_ENV"

             ((L_ROW_IND=L_ROW_IND+1))
             FN_Debug "\t$L_LN\n\t\tFor loop iteration $L_ROW_IND"
             FN_Debug "\t\t$G_EXE $G_ENV $G_TIER $G_STR_TYPE $G_STR $G_PATTERN $G_TASK $G_KEEP_DAYS $G_ACTION_LEVEL\n"

             FN_ENV_Check
             FN_Tier_Check
             FN_Str_Type_Check
             FN_Task_Check
             FN_Action_Level_Check
             FN_PURGE_TYPE_Check
             FN_Host_details_get
             FN_Path_Get
             FN_Process
           done
           ;;

         *) FN_Debug "Error: $G_EXE is not a valid parameter"
         ;;
       esac
     done

   else
     FN_Error "The driver file $L_DRV_FN Does not exist"
   fi

    FN_Print "Removing \"$L_CONC_FLAG\" flag file."
    rm -f $L_CONC_FLAG
    if [ $? -ne 0 ]
    then
     FN_Error "ERROR :: Could not delete \"$L_CONC_FLAG\" flag file."
     return 1
    fi

 else
  echo "ERROR :: Unexpected error in FN_Init [$*]}"
  return 1
 fi

 FN_Print "$L_LN2"
 FN_Debug "End"
 FN_Print "$L_LN2"
}

###################################  MAIN  #####################################
export DAY=`date +%Y%m%d`
export L_SCRIPT_NAME=housekeep_files
export L_SCRIPT_BASE=housekeep_files.ksh
export L_SCRIPT_DIR=/export/vtssupp/VTS/bin
export L_SCRIPT_DIR=${L_SCRIPT_DIR:-./}
export L_LOG_DIR=${L_LOG_DIR:-$DBA/log}
export L_LOG_FN=${L_LOG_DIR}/${L_SCRIPT_NAME:-unknown}_${DAY}.log

FN_Main $* 2>&1 >$L_LOG_FN
