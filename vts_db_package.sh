#!/usr/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Robert Milby     20111025                    Velos-IT         #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
#                                                               #
# Function: called by SAN to enable/disable backup mode         #
# Parameters:                                                   #
#       ORACLE_SID                                              #
#       BACKUP_TYPE  HOT/COLD                                   #
#       PHASE_CODE charater value BIGIN/END                     #
#                                                               #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
# Modifications:                                                #
# YYYYMMDD      Who     Ver     description                     #
# 30130402  milbyr 1.0  Change filesystem from inst to diag     #
# -------- ----------  ----  ---------------------------------  #
#                                                               #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#  setup the environment
.   $HOME/.bash_profile

   ## This assumes that the configuration has already been done.

function FN_Inc
{
  export L_STEP=$(($L_STEP + 1))
}


function FN_Header
{
  printf "\n${LN_BREAK}\n"
  printf "= STEP ${L_STEP} : starting $@ `date`\n"
  printf "${LN_BREAK}\n"

}   ### End of FN_Header ##


function ALF_archived_check {
 CHECK_SEQ=${1:?"Missing the sequence (check_seq)"}

 sqlplus -s / as sysdba <<EOF
   set head off pages 0 verify off feedback off echo off term off
   whenever sqlerror exit FAILURE;

   spool $BKUP_DIR/ALF_ARCHIVED.txt
   select ARCHIVED
   from v\$log
   where sequence# = $CHECK_SEQ
     and thread#=1;

   spool off
EOF
 # the checks will be made in the calling function

}  ### end of ALF_archived_check ###


function  ALF_archived  {
 L_SEQ=${1:?"Missing the seq parameter"}
 L_STATUS=1

  FN_Header ALF_archived

 while ( [ $L_STATUS -ne 0 ] && [ $ALF_check_retries -ne 0 ] )
 do
   ALF_check_retries=`expr $ALF_check_retries \- 1`
   ALF_archived_check $L_SEQ
   grep YES $BKUP_DIR/ALF_ARCHIVED.txt >/dev/null
   if [ $? -eq 0 ]; then
     L_STATUS=0
   else
     echo "\tretry $ALF_check_retries - sleeping $ALF_check_wait"
     sleep $ALF_check_wait
   fi
 done

 if [ $L_STATUS -eq 0 ]; then
   echo "\t\tthe archive log file (sequence#=$SEQ) has been archived"
 else
   echo "\t\tthe archive log file has not been archived within the time required"
   exit 1
 fi

 echo "\n\t${LN_BREAK}"
 echo "\t\tending ALF_archived "`date`
 echo "\t${LN_BREAK}"

}   ### end ALF_archived ###


function process_ALF_list {
   ### This used for log_archive_dest ###

  FN_Header process_ALF_list

 if [ -f $BKUP_DIR/alf_list.txt ]; then
   cat $BKUP_DIR/alf_list.txt | while read L_ALF L_PATH L_OTHER
   do
     #L_PATH=`echo $L_PATH | awk -F= '{print $2}'`
     L_FULL_FN=`ls -1 ${L_PATH}/${L_ALF}`
     L_FN=${L_FULL_FN##/*/}
     SEQ=`echo $L_FN | awk -F_ '{print $2}'`
     echo "\tChecking that the ALF has been written to disk ($SEQ)"

     ALF_archived  $SEQ

     echo "\tgzip <${L_FULL_FN} >$BKUP_DIR/${L_FN}.gz"
     gzip <${L_FULL_FN} >$BKUP_DIR/${L_FN}.gz
   done
 else
   echo "\tERROR the file alf_list.txt does not exist"
   exit 1
 fi

}   ### end of process_ALF_list ###


function process_ALF_list_1 {
 ### This is for using archive_log_dest_1 ###

 FN_Header process_ALF_list_1

  #  added to make sure the ALF has been written to disk
  ## sync; sync
  ## wait 120

 if [ -f $BKUP_DIR/alf_list.txt ]; then
   cat $BKUP_DIR/alf_list.txt | while read L_ALF L_PATH L_OTHER
   do
     L_PATH=`echo $L_PATH | awk -F= '{print $2}'`
     L_FULL_FN=`ls -1 ${L_PATH}/${L_ALF}`
     L_FN=${L_FULL_FN##/*/}
     SEQ=`echo $L_FN | awk -F_ '{print $4}'`
     ##rm 20111025 ##SEQ=`echo $L_FN | awk -F_ '{print $2}'`
     echo "\tChecking that the ALF has been written to disk ($SEQ)"

     ALF_archived  $SEQ

     echo "\tgzip <${L_FULL_FN} >$BKUP_DIR/${L_FN}.gz"
     gzip <${L_FULL_FN} >$BKUP_DIR/${L_FN}.gz
   done
 else
   echo "\tERROR the file alf_list.txt does not exist"
   exit 1
 fi

}   ### end of process_ALF_list_1 ###

function get_ALF_list {

  FN_Header get_ALF_list

 if [ -f $BKUP_DIR/BKUP_START_ALF.txt ]; then
   L_STARTING_ALF=`cat $BKUP_DIR/BKUP_START_ALF.txt`
   echo "\t the starting ALF id is $L_STARTING_ALF"
 else
   echo "\nERROR\tThe starting ALF number or BKUP_START_ALF.txt does not exist"
   exit 1
 fi

 if [ -f $BKUP_DIR/BKUP_END_ALF.txt ]; then
   L_ENDING_ALF=`cat $BKUP_DIR/BKUP_END_ALF.txt`
   echo "\t the end ALF id is $L_ENDING_ALF"
 else
   echo "\nERROR\tThe ending ALF number or BKUP_END_ALF.txt does not exist"
   exit 1
 fi

 sqlplus -s / as sysdba <<EOF
   whenever sqlerror exit FAILURE;
   set head off pages 0 lines 300 trims on feedback off
   set verify off term off

   col ALF new_value ALF_TEMPLATE
   col seq new_value CUR_ALF

--     select sequence# seq
--     from v\$log
--     where status = 'CURRENT'
--       AND THREAD# = 1;

   select p2.value
    ||' '|| p1.value  ALF
   from v\$parameter p2
     , v\$parameter p1
   where p2.name = 'log_archive_format'
     and p1.name = 'log_archive_dest_1';
     -- and p1.name = 'log_archive_dest';

   --  I have not found were %r comes from yet so substituting an *
   spool $BKUP_DIR/alf_list.txt

   select replace(replace( replace( '&ALF_TEMPLATE' , '%t',thread#)
     , '%s', sequence# ),'%r', '*' ) fn
   from v\$log_history
   where  sequence# between $L_STARTING_ALF and $L_ENDING_ALF
     and THREAD# = 1
   order by thread#, sequence#;

   spool off

EOF

 if [ $? -ne 0 ]; then
   echo "\tERROR: The ALF list fuction failed"
   exit 1
 fi

}  ### end of get_ALF_list ###



function copy_db_init_files {
 printf "\n${LN_BREAK}\n"
 printf "\tstarting copy_db_init_files `date`\n"
 printf "${LN_BREAK}\n"

 if [ -f $ORACLE_HOME/dbs/orapw${ORACLE_SID} ]; then
 printf "\tcopying the oracle password file\n"
 cp $ORACLE_HOME/dbs/orapw${ORACLE_SID} $BKUP_DIR
fi

if [ -f $ORACLE_HOME/dbs/spfile${ORACLE_SID}.ora ]; then
 printf "\tcopying the oracle server parameter file\n"
 cp $ORACLE_HOME/dbs/spfile${ORACLE_SID}.ora $BKUP_DIR
fi

if [ -f $ORACLE_HOME/dbs/init${ORACLE_SID}.ora ]; then
 printf "\tcopying the oracle init file(s)\n"
 cp $ORACLE_HOME/dbs/*${ORACLE_SID}*.ora $BKUP_DIR
fi

}   ### end of copy_db_init_files ###


function bkup_db {
#
 L_TYPE=${1:?"Missing the backup type"}
 L_PHASE=${2:?"Missing the backup phase"}

 FN_Header bkup_db

 printf "\tstarting the $L_TYPE backup ($L_PHASE) at `date`\n"
 case $L_TYPE in
   "COLD")
      case $L_PHASE in
        "BEGIN" )
        sqlplus -s / as sysdba  <<EOF
        whenever sqlerror exit FAILURE;
        set echo on feedback on lines 200

        select sequence# , thread#
        from v\$log
        where status = 'CURRENT';

        prompt ### switching the current logfile ###
        -- have to check archivelog mode -- alter system archive log current;

        prompt ### backing up the controlfile to trace ###
        alter database backup controlfile to trace as '$BKUP_DIR/control_${ORACLE_SID}.trc';
        #
        ###   There should be a waiting process to shutdown abort if a timer expires
        #
        prompt ### shutting down the database (immediate) ###
        shutdown immediate;
EOF
        if [ $? -eq 0 ] ; then
          echo "database has been shutdown " `date`
        else
          echo "\tdatabase has FAILED to shutdown " `date`
          exit 1
        fi
        ;;
        "END")
        sqlplus -s / as sysdba  <<EOF
          whenever sqlerror exit FAILURE;
          set echo on feedback on
          startup;
          prompt 'removing the existing control file for $DAY'
          !rm $BKUP_DIR/controlXX_${ORACLE_SID}.ctl.${DAY}*
          prompt 'backing up the controlfile'
          alter database backup controlfile
          to '$BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY';
          prompt '-----> gzip <$BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY >$BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY.gz'
          !gzip <$BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY >$BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY.gz
EOF
        if [ $? -eq 0 ] ; then
          echo "database has been started " `date`
        else
          echo "ERROR: database has FAILED to startup " `date`
          exit 1
        fi
        ;;
      *) echo "This option is not valid "
        exit 1
      ;;
      esac
     ;;
  "HOT")
      case $L_PHASE in
"BEGIN" )
      sqlplus -s / as sysdba  <<EOF
      -- 20200316 milbyr --whenever sqlerror exit FAILURE;
      set echo off feedback off head off pages 0 verify off

      --  make a note of the current archive log file
      prompt '\tcreating the $BKUP_DIR/BKUP_START_ALF.txt file'

      prompt '\tswitching the current logfile'
      -- does not check if the database is archivelog mode -- alter system archive log current;


      spool  $BKUP_DIR/BKUP_START_ALF.txt
      select sequence#
        -- , thread#
      from v\$log
      where status = 'CURRENT';

      spool off

     select sequence# , thread#
     from v\$log
     where status = 'CURRENT';

     --prompt '\tchanging the database to backup mode'
     -- alter database begin backup;

      set serveroutput on
      
      DECLARE 
        DB_STATE varchar2(20);
      BEGIN
        select status into DB_STATE from v\$instance;
        IF( DB_STATE = 'OPEN' ) THEN
          dbms_output.put_line( 'DB_STATE - ' || DB_STATE );
          dbms_output.put_line( 'changing the database to backup mode - alter database begin backup;');
          execute immediate 'alter database begin backup';
        ELSE
         dbms_output.put_line( 'The database is in '||DB_STATE ||' mode' );
        END IF;
      END;
      /

EOF
      if [ $? -eq 0 ] ; then
        printf "\tthe database is now in BACKUP mode `date`\n"
      else
        printf "\tERROR: the database has FAILED BACKUP mode `date`\n"
        exit 1
      fi

      copy_db_init_files

   ;;
"END" )

    sqlplus -s / as sysdba  <<EOF
      whenever sqlerror exit FAILURE;
      set echo off feedback off head off pages 0 verify off
      set serveroutput on

      -- prompt bringing the database out of backup mode
      -- alter database end backup;

      
      DECLARE 
        DB_STATE varchar2(20);
      BEGIN
        select status into DB_STATE from v\$instance;
        IF( DB_STATE = 'OPEN' ) THEN
          dbms_output.put_line( 'DB_STATE - ' || DB_STATE );
          dbms_output.put_line( 'changing the database to backup mode - alter database end backup;');
          execute immediate 'alter database end backup';
        ELSE
         dbms_output.put_line( 'The database is in '||DB_STATE ||' mode' );
        END IF;
      END;
      /

      --  make a note of the current archive log file
      set term off
      prompt Creating the $BKUP_DIR/BKUP_END_ALF.txt file
      spool  $BKUP_DIR/BKUP_END_ALF.txt
      select sequence#
      -- , thread#
      from v\$log
      where status = 'CURRENT';

      spool off
      set term on

      select sequence# , thread#
      from v\$log
      where status = 'CURRENT';

      prompt switching the current logfile
      -- does not wait for ALF to complete -- alter system switch logfile;
      -- alter system archive log current;

      DECLARE
        DB_STATE varchar2(20);
      BEGIN
        select status into DB_STATE from v\$instance;
        IF( DB_STATE = 'OPEN' ) THEN
          execute immediate 'alter system archive log current';
        ELSE
         dbms_output.put_line( 'The database is in '||DB_STATE ||' mode' );
        END IF;
      END;
      /



      prompt '\tremoving the existing control file for $DAY'
      !rm $BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY 2>/dev/null
      prompt '\tbacking up the controlfile'
      alter database backup controlfile
        to '$BKUP_DIR/controlXX_${ORACLE_SID}.ctl.$DAY';

      prompt '\tcreating a trc file from control file'
      alter database backup controlfile to trace as '$BKUP_DIR/control_${ORACLE_SID}.trc';

--      col value new_value dir_param
--      col F new_value trc_fn
--
--      select value
--      from v\$parameter
--      where name = 'user_dump_dest';
--
--      select '&dir_param/' ||lower('$ORACLE_SID')
--        ||'_ora_'||spid||'.trc' F
--      from v\$process
--      where addr in (
--       select paddr from v\$session
--       where username = 'SYS'
--         and logon_time > sysdate - 15/(24*60)
--      );
--
--      prompt '\tCopying the newly created trace file - &trc_fn -'
--      !wait 120
--      prompt 'Checking if the trace file &trc_fn exists'
--      !ls -al &trc_fn
--      !cp &trc_fn $BKUP_DIR

EOF
      if [ $? -eq 0 ] ; then
        printf "\tdatabase is now in normal mode `date`\n"
      else
        printf "\tERROR: the database has FAILED to come out of BACKUP mode `date`\n"
        exit 1
      fi

      ;;
      *) printf "This is not a valid backup type\n"
    ;;
    esac
    ;;

    *) echo "This option is not allowed"
      exit 1
     ;;
esac

#   this was added as on occasions the trace file was 0 size
##sync; sync
##wait 120

}   ### end of bkup_db ###


function setup_bk_dir {
 # function : to create a new backup driectory to keep everything together
 #  line the default destination to the new directory

 FN_Header setup_bk_dir

 if [ "$PHASE_CODE" = "BEGIN" ]; then
   if [ -L $BKUP_DIR ]; then
     printf "\tremoving the symbolic link\n"
     rm -f $BKUP_DIR
   fi

   if [ ! -d $WORKING_DIR ]; then
     printf "\tcreating the working directory $WORKING_DIR\n"
     mkdir -p $WORKING_DIR
     if [ $? -ne  0 ]; then
       printf "\t\tERROR: Could NOT create $WORKING_DIR\n"
       exit 1
     fi
   fi

   printf "\tcreating the symbolic link $WORKING_DIR $BKUP_DIR\n"
   ln -s $WORKING_DIR $BKUP_DIR


#   printf "\tcreating the symbolic link $WORKING_DIR $BKUP_DIR"
#   rm $BKUP_DIR 2>&1 >/dev/null
#   ln -s $WORKING_DIR $BKUP_DIR
#   if [ $? -ne  0 ]; then
#     printf "\t\tERROR: Could NOT link $BKUP_DIR to $WORKING_DIR"
#     exit 1
#   fi

 else
   # the existing directory structure
   printf "\t The backup directory is $WORKING_DIR\n"
 fi

}   ### end of setup_bk_dir ###


function check_parameters {
 L_TYPE=${1:?"Missing the backup type"}
 L_PHASE=${2:?"Missing the backup phase"}

 FN_Header check_parameters

 if [ ! "$ORACLE_SID" = "$SID" ]; then
   printf "\tThe oracle sid ($ORACLE_SID) does not match  sid ($SID)- wrong account\n"
   exit 1
 fi

 if [ "$BKUP_TYPE" = "HOT" ] || [ "$BKUP_TYPE" = "COLD" ]; then
   printf "The backup type is OK ($BKUP_TYPE)\n"
 else
   printf "The backup type is wrong ($BKUP_TYPE)\n"
   exit 1
 fi

 if [ "$PHASE_CODE" = "BEGIN" ] || [ "$PHASE_CODE" = "END" ]; then
   printf "phase code OK ($PHASE_CODE)\n"
 else
   printf "The phase code is wrong ($PHASE_CODE)\n"
   exit 1
 fi
}   ### End of check_parameters ###


function print_restore_instr {
 REC_FN=$BKUP_DIR/README.txt

 FN_Header print_restore_instr

 (cat <<EOF
 copy the orapw$ORACLE_SID file to $ORACLE_HOME/dbs
 copy the spfile or init*.ora files to $ORACLE_HOME/dbs 
 copy the ALFs to the log_archive_dest_1 directory 
 Unzip the ALFs (gunzip) 
 
 If you want an imcomplete recovery then copy the backup control file to the destinations and names dictated in the init*.ora file
 startup the database in mount mode 
    sqlplus / as sysdba 
    startup mount 
 roll the database forward 
    sqlplus / as sysdba 
    set auto on 
    recover database [using backup controlfile] until cancel; 
    alter database open resetlogs 
EOF
 ) >$REC_FN

}   ### end of print_restore_instr ###


function FN_MAIN
{
  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "$PG  Ver $VERSION starting at `date` with $BKUP_TYPE $PHASE_CODE\n"
  printf "${LN_BREAK}${LN_BREAK}\n"

  while  ( [ $L_COMPLETE -eq 1 ] && [ $L_ERROR -eq 0 ] )
  do
    case $L_STEP in
     1)
        check_parameters $BKUP_TYPE $PHASE_CODE
        FN_Inc
        ;;
     2)
        setup_bk_dir
        FN_Inc
        ;;

     3)
        bkup_db $BKUP_TYPE $PHASE_CODE
        FN_Inc
        ;;

     4)
        print_restore_instr
        FN_Inc
        L_COMPLETE=0
        ;;

    *)
        echo "ERROR"
        ;;
    esac
  done

  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "$PG  completing at `date` \n"
  printf "${LN_BREAK}${LN_BREAK}\n"

}   ### End of MAIN ##


#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#

  PG=$(basename $0)
  VERSION=1.0


  if [ $# -lt 3 ]; then
   echo "Missing some paramters"
   echo "\n\nUSE:\n\t$PG  ORACLE_SID HOT|COLD   BEGIN|END\n"
   exit 1
  fi

  export SID=${1:?"Missing the Oracle Sid"}
  export BKUP_TYPE=${2:?"Missing the backup type"}
  export PHASE_CODE=${3:?"Missing the phase code"}
  export L_STEP=${4:-1}

  LC_SID=$(echo $SID | tr "[:upper:]" "[:lower:]" )

  LN_BREAK="================================================================="

  export ADMIN_BASEDIR=/ora${LC_SID}/tech_st/diag/$CONTEXT_NAME
  export ARCHIVE_DIR=${ADMIN_BASEDIR}/backup_archive
  export BKUP_DIR=${ADMIN_BASEDIR}/backup
  export DBA=/export/vtssupp/VTS

  export D=`date +'%Y%m%d'`
  export WORKING_DIR=$ARCHIVE_DIR/backup_$D

  export DAY=`date +'%Y%m%d_%H%M%S'`
  export LOG_FN=$WORKING_DIR/${PG}.log.${DAY}
  export TMP_LOG_FN=$DBA/log/${PG}.log.${DAY}

  export SQLDBA="$ORACLE_HOME/bin/sqlplus -s \/ as sysdba"

  export ALF_check_retries=2
  #  The time in seconds to wait if the archive log is not written to disk
  export ALF_check_wait=300

  export L_COMPLETE=1
  export L_ERROR=0
  export L_VERBOSE=1


  FN_MAIN

# - - - - - - - - - - - - - - - - - - end - - - - - - - - - - - - - - - - - - - -
