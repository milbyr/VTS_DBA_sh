#!/usr/bin/ksh
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# R. Milby      20141205                                                                          #
#                                                                                                 #
# To recover a hot backup and clone                                                               #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# History                                                                                         #
# converted to EMSS R12.2                                                                         #
#                                                                                                 #
#       When            Who     What                                                              #
#       =====================================================================                     #
#                                                                                                 #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
#
export DBA=/export/vtssupp/vts
export L_VERBOSE=1
export G_ENV=1

if [ -f $DBA/bin/vts_utils.ksh ]; then
.   $DBA/bin/vts_utils.ksh
else
  echo "$DBA/bin/vts_utils.ksh is missing"
fi


function FN_Inc
{
  export L_STEP=`expr $L_STEP \+ 1`
}


function FN_InitOra_old
{
  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )

( cat <<EOF

db_name = $L_ORACLESID
control_files  = /ora${L_LCORACLESID}/data01/cntrl01.dbf,/ora${L_LCORACLESID}/data02/cntrl02.dbf,/ora${L_LCORACLESID}/fra/cntrl03.dbf
db_files                        = 500         # Max. no. of database files
undo_management=AUTO                   # Required 11i setting
undo_tablespace=APPS_UNDOTS1     # Required 11i setting
memory_max_target               = 3g
memory_target                   = 3g
db_block_size                   = 8192
compatible                      = 11.2.0
diagnostic_dest                 = /ora${L_LCORACLESID}
EOF
) > $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora

}   ### End of FN_InitOra_old ###


function FN_InitOra
{
  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )

  mv $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora.autoconfig
  cat $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora.autoconfig | sed -e "s/utl_file_dir = \/usr\/tmp,/utl_file_dir = /" > $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora
  echo "utl_file_dir = /appl${L_LCORACLESID}/csf/temp, /appl${L_LCORACLESID}/csf/log, /appl${L_LCORACLESID}/csf/out, /usr/tmp" >> $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora

} ### End of FN_InitOra ###


function FN_orapwd
{
  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )
  export ORACLE_HOME=${L_ORACLE_HOME}

  l_password=${1:?"FN_orapwd: Missing the system password"}
  FN_Debug "$L_ORACLE_HOME/bin/orapwd password=$l_password entries=10 file=$L_ORACLE_HOME/dbs/orapw$L_ORACLESID"

 $L_ORACLE_HOME/bin/orapwd password=$l_password entries=10 file=$L_ORACLE_HOME/dbs/orapw$L_ORACLESID
  if [ $? -ne 0 ] ; then
    FN_Error "FN_orapwd FAILED"
  fi
}


function FN_Sym_Links
{

  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  #  move the existing admin directory
  FN_Debug "Moving the database admin directory"

  rm $(FN_ORACLE_HOME ${L_ORACLESID})/admin/${L_S_SID}_${L_DBSRV}
  rm  $(FN_ORACLE_HOME ${L_ORACLESID})/admin/${L_ORACLESID}_${L_DBSRV}
  mkdir  $(FN_ORACLE_HOME ${L_ORACLESID})/admin/${L_ORACLESID}_${L_DBSRV}


##  find /ora$L_LCORACLESID/db/tech_st -type l -ls 2>/dev/null| grep "/ora${LC_S_SID}/" |awk '{print $11" "$13}'|while read L_LINK L_FN
##  do
##    N_FN=`echo $L_FN | sed -e "s/ora${LC_S_SID}/ora$L_LCORACLESID/"`
##    if [ -f $N_FN ]; then
##      FN_Debug "rm $L_LINK"
##      rm -f $L_LINK
##      ln -s $N_FN $L_LINK
##    else
##      FN_Debug "ERROR: file $N_FN does not exist or local link"
##    fi
##  done
}


function FN_ora_env
{

  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )
  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`
  LC_T_SID=`echo "$L_ORACLESID" | tr "[:upper:]" "[:lower:]"`

  cat $L_ORACLE_HOME/${L_S_SID}_${L_DBSRV}.env | sed "s/${L_S_SID}/${L_ORACLESID}/g" | sed "s/ora${LC_S_SID}/ora${LC_T_SID}/g" > $L_ORACLE_HOME/${L_ORACLESID}_${L_DBSRV}.env

}


function FN_backup_dir
{
 if [ -d /ora${L_LCORACLESID}/diag/PRD3_${L_DBSRV}/backup_archive ]; then
  l_dir=`ls -1dtr /ora${L_LCORACLESID}/diag/PRD3_${L_DBSRV}/backup_archive/backup_*|tail -1`
  #FN_Debug "FN_backup_dir: l_dir is $l_dir"
  echo "$l_dir"
 else
  echo "FN_backup_dir: /ora${L_LCORACLESID}/diag/${L_ORACLESID}_${L_DBSRV}/backup_archive does NOT exist"
 fi
}


function FN_ALF
{
 export L_BKUP_DIR=$(FN_backup_dir)

  for l_fn in `ls -1tr $L_BKUP_DIR/*arc.gz`
  do
    if [ -e ${l_fn} ]; then
      l_fn2=${l_fn%%.gz}
      gzip -cd <$l_fn >$l_fn2
      echo "$l_fn2"
    else
     FN_Debug "FN_ALF: failed"
    fi
 done
}


function FN_CR_CTL_Script
{
 export L_BKUP_DIR=$(FN_backup_dir)

 export LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  FN=`ls -1tr $L_BKUP_DIR/*trc | tail -1`
  S_LN=`egrep -n  "CREATE CONTROLFILE" $FN| head -1 | awk -F: '{print $1}'`
  E_LN=`egrep -n  "CHARACTER" $FN|head -1 | awk -F: '{print $1}'`
  ROWS=`expr $E_LN \- $S_LN \+ 2`

  echo "--The file $FN will be split between $S_LN and $E_LN ($ROWS)"
set -x
  tail +$S_LN $FN | head -n $ROWS| grep -v "^$" | grep -v "^--" | sed "s/\/ora${LC_S_SID}\//\/ora${L_LCORACLESID}\//" | sed -e "s/\"//g"| sed "s/\/$L_S_SID\//\/${L_ORACLESID}\//g" | sed "s/DATABASE $L_S_SID NORESETLOGS FORCE LOGGING [N]*[O]*ARCHIVELOG/set DATABASE ${L_ORACLESID} RESETLOGS FORCE LOGGING NOARCHIVELOG/" >$L_BKUP_DIR/cr_ctl.sql
set +x
}


function FN_CR_TMP_Script
{
  export L_BKUP_DIR=$(FN_backup_dir)
 ( cat <<EOF

ALTER TABLESPACE TEMP
ADD TEMPFILE '/ora${L_LCORACLESID}/db/apps_st/data01/temp01.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 4000M;

EOF
 ) >$L_BKUP_DIR/cr_tmp.sql 2>&1

}


function FN_ORACLE_ENV
{
  export ORACLE_HOME=$L_ORACLEHOME

# todo - check G_ENV to see if the env file has already been run #

  if [ $G_ENV -eq 1 ]; then
    if [ -f  $ORACLE_HOME/${L_DBCONTEXT_NAME}.env ]; then
      . $ORACLE_HOME/${L_DBCONTEXT_NAME}.env
      export G_ENV=0
    else
      FN_Error "FN_ORACLE_ENV: the environment file $ORACLE_HOME/${L_DBCONTEXT_NAME}.env DOES NOT EXIST"
      export ORACLE_SID=${L_ORACLESID}
      export LD_LIBRARY_PATH=${ORACLE_HOME}/lib,${ORACLE_HOME}/ctx/lib
      export PATH=$ORACLE_HOME/bin:/usr/ccs/bin:/usr/bin
      export TNS_ADMIN=$ORACLE_HOME/network/admin/${L_ORACLESID}_${L_DBSRV}
    fi
  else
    FN_Debug "FN_ORACLE_ENV: G_ENV=$G_ENV :- ${L_DBCONTEXT_NAME}.env already run"
  fi
}


function FN_DB_CTL
{
  FN_ORACLE_ENV

case $1 in

 start | START )
    L_COMMAND="startup;"
    ;;
 stop | STOP )
    L_COMMAND="shutdown immediate;"
    ;;
 abort | ABORT )
    L_COMMAND="shutdown abort;"
    ;;
 force | FORCE )
    L_COMMAND="startup force;"
    ;;
  *) echo "FN_DB_CTL: this is an error"
    ;;
esac

    sqlplus  -s / as sysdba <<EOF
      whenever sqlerror exit FAILURE;
      ${L_COMMAND}
EOF
  export L_ERROR=$?
}


function FN_CR_CTL
{

  export L_BKUP_DIR=$(FN_backup_dir)
  l_sql=$L_BKUP_DIR/cr_ctl.sql

 if [ -f $l_sql ]; then
  sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit FAILURE;
    startup nomount
    @$l_sql
EOF
  export L_ERROR=$?
 else
   echo "FN_CR_CTL: The file $l_sql does NOT exist"
   export L_ERROR=1
 fi

}


function FN_Recover_DB
{
    function fn_db_ans
    {
       print -u9 "$*"
       sleep 5
    } ### end of fn_db_ans ###


    function fn_db_response
    {
      # recover the database
      fn_db_ans "recover database using backup controlfile until cancel;"

      # supply the ALF
      ## 20130718 milbyr ## fn_db_ans "$L_ALF"
      for a in $L_ALF
      do
        fn_db_ans "$a"
      done

      # supply cancel
      fn_db_ans "cancel"

      fn_db_ans "exit"

    }

# set -x

  export L_BKUP_DIR=$(FN_backup_dir)

  L_ALF=`ls -1 $L_BKUP_DIR/*arc| sort`
  if  ! [ -f $L_ALF ]; then
    echo "FN_Recover_DB : no ALF exists"
    export L_ERROR=1
    exit 1
  else
    FN_Debug "FN_Main: using archive log file $L_ALF for recovery"

  (  sqlplus -s / as sysdba ) |&

    sleep 10

    exec 8<&p
    exec 9>&p

    fn_db_response &
    l_response_pid=$!

    # it is compulsary to utilise the 8 stream
    while read -u8 ME_TXT
    do
      FN_Print "8: $ME_TXT"
    done

    kill -9 $l_response_pid

  fi
}


function FN_Open_DB
{
  export L_BKUP_DIR=$(FN_backup_dir)
  L_MANAGER=$(FN_PASSWORD_GEN "Manager" $L_ORACLESID)

  sqlplus -s / as sysdba <<EOF
    whenever sqlerror exit FAILURE;
    alter database open resetlogs;
    @$L_BKUP_DIR/cr_tmp.sql
    alter user system identified by $L_MANAGER;
    alter user sys identified by $L_MANAGER;
EOF
  export L_ERROR=$?
}


function FN_dbTechStack
{


    function fn_db_ans
     {
       print -u9 "$*"
       sleep 5
     } ### end of fn_db_ans ###

    function fn_db_response
     {
            ##                      Copyright (c) 2002 Oracle Corporation
            ##                         Redwood Shores, California, USA
            ##
            ##                         Oracle Applications Rapid Clone
            ##
            ##                                  Version 12.0.0
            ##
            ##                       adcfgclone Version 120.20.12000000.12
            ##
            ## Enter the APPS password :
              fn_db_ans "$(FN_GetAPPSPassword $L_S_SID)"
            ## Running:
            ## /oradev4/db/tech_st/10.2.0/appsutil/clone/bin/../jre/bin/java -Xmx600M -cp /oradev4/db/tech_st/10.2.0/appsutil/clone/jlib/java:/oradev4/db/tech_st/10.2.0/appsutil/clone/jlib/xmlparserv2.jar:/oradev4/db/tech_st/10.2.0/appsutil/clone/jlib/ojdbc14.jar oracle.apps.ad.context.CloneContext -e /oradev4/db/tech_st/10.2.0/appsutil/clone/bin/../context/db/CTXORIG.xml -validate -pairsfile /tmp/adpairsfile_25456.lst -stage /oradev4/db/tech_st/10.2.0/appsutil/clone -dbTechStack 2> /tmp/adcfgclone_25456.err; echo $? > /tmp/adcfgclone_25456.res
            ##
            ## Log file located at /oradev4/db/tech_st/10.2.0/appsutil/clone/bin/CloneContext_1019163646.log
            ##
            ## Provide the values required for creation of the new Database Context file.
            ##
            ## Target System Hostname (virtual or normal) [v06ss102] : v06ss102
              fn_db_ans "${L_DBSRV}"
            ## Target Instance is RAC (y/n) [n] : n
              fn_db_ans "n"
            ## Target System Database SID : DEV4
              fn_db_ans "${L_ORACLESID}"
            ## Target System Base Directory : /oradev4
              fn_db_ans "/${L_ORAUSER}"
            ## Oracle OS User [oradev4] : oradev4
              fn_db_ans "${L_ORAUSER}"
            ## Target System utl_file_dir Directory List : /appldev4/csf/temp,/appldev4/csf/log,/appldev4/csf/out
              ##  NCC go-live fn_db_ans "/${L_APPLUSER}/csf/temp,/${L_APPLUSER}/csf/out,/${L_APPLUSER}/csf/log"
              fn_db_ans "/${L_APPLUSER}/csf/temp,/${L_APPLUSER}/csf/out,/${L_APPLUSER}/csf/log"
            ## Number of DATA_TOP's on the Target System [3] : 2
              fn_db_ans "2"
            ## Target System DATA_TOP Directory 1 : /oradev4/db/apps_st/data02
              fn_db_ans "/${L_ORAUSER}/db/apps_st/data02"
            ## Target System DATA_TOP Directory 2 : /oradev4/db/apps_st/data03
              fn_db_ans "/${L_ORAUSER}/db/apps_st/data03"
            ## Target System RDBMS ORACLE_HOME Directory [/oradev4/db/tech_st/10.2.0] : /oradev4/db/tech_st/10.2.0
              fn_db_ans "$(FN_ORACLE_HOME $L_ORACLESID )"
            ## Do you want to preserve the Display [v06ss102:1] (y/n) ? : n
              fn_db_ans "n"
            ## Target System Display [v06ss102:0.0] : v06ss102:1.0
              fn_db_ans "${L_DBSRV}:1.0"
            ## Do you want the the target system to have the same port values as the source system (y/n) [y] ?
              fn_db_ans "n"
            ## Target System Port Pool [0-99] : 4
              fn_db_ans "${L_PORT}"
#################################
     } ### end of fn_db_response ###

#  this need to listen to parameters on other stream #
 cd ${L_ORACLEHOME}/appsutil/clone/bin
 FN_Debug "FN_dbTechStack: perl adcfgclone.pl dbTechStack"
 ( perl adcfgclone.pl dbTechStack ) |&

   sleep 5

   exec 8<&p
   exec 9>&p

   fn_db_response &
   l_response_pid=$!

  # it is compulsary to utilise the 8 stream
  while read -u8 ME_TXT
  do
     FN_Print "read -u8 $ME_TXT"
  done

  kill -9 $l_response_pid
}


function FN_clone_lib
{

  if [ -d $ORACLE_HOME/appsutil/install/${L_DBCONTEXT_NAME} ]; then
    cd $ORACLE_HOME/appsutil/install/${L_DBCONTEXT_NAME}
    sqlplus -s / as sysdba <<EOF
      whenever sqlerror exit FAILURE;
      @adupdlib.sql so
EOF
  else
    FN_Error "FN_clone_lib: $L_ORACLEHOME/appsutil/install/${L_DBCONTEXT_NAME} MISSING"
  fi
}


function FN_autocfg
{
     L_PASSWD=$(FN_GetAPPSPassword $L_S_SID)

  if [ -d $ORACLE_HOME/appsutil/scripts/${L_DBCONTEXT_NAME} ]; then
    sqlplus -s /nolog <<EOF
      connect apps/${L_PASSWD}
      whenever sqlerror exit FAILURE;
      exec fnd_conc_clone.setup_clean;
EOF
    $ORACLE_HOME/appsutil/scripts/${L_DBCONTEXT_NAME}/adautocfg.sh appspass=${L_PASSWD}
  else
    FN_Error "FN_autocfg: $L_ORACLEHOME/appsutil/scripts/${L_DBCONTEXT_NAME} MISSING"
  fi
}   ### end of FN_autocfg ###


function FN_dbconfig
{

        function fn_db_ans
         {
           print -u9 "$*"
           sleep 5
         } ### end of fn_db_ans ###

        function fn_db_response
         {
             ## Enter the APPS password [APPS]:
             fn_db_ans "$(FN_GetAPPSPassword $L_S_SID)"
         } ### end of fn_db_response ###

  cd  $L_ORACLEHOME/appsutil/clone/bin

  # run the RapidClone script into a pipe
  FN_Debug "perl adcfgclone.pl dbconfig $L_ORACLEHOME/appsutil/${L_DBCONTEXT_NAME}.xml"

  (perl adcfgclone.pl dbconfig $ORACLE_HOME/appsutil/${L_DBCONTEXT_NAME}.xml) |&

   sleep 5

   exec 8<&p
   exec 9>&p

   fn_db_response &
   l_response_pid=$!

  # it is compulsary to utilise the 8 stream
  while read -u8 ME_TXT
  do
     FN_Print "read -u8 $ME_TXT"
  done

  kill -9 $l_response_pid

}  ### end of FN_dbconfig ###


function FN_tns_ifile
{
  ##FN_ORACLE_ENV

  echo "ifile=/export/ops/emss/GLOBAL/tnsnames_LCC.ora" > ${L_ORACLEHOME}/network/admin/${L_DBCONTEXT_NAME}/${L_DBCONTEXT_NAME}_ifile.ora
}


function FN_lsnr_ifile
{

  export L_TNS_PORT=`expr 1621 \+ $L_PORT`

 #L_DOMAIN=`awk '/domain/ {print $2}' /etc/resolv.conf`
 #HOST_STR=$(hostname).${L_DOMAIN}

 if [ $(hostname) = "vedi1sx001" ]; then
  HOST_STR="vedi1sx001.edi.ladbrokes.com"
 else
  HOST_STR="v06emzs100.edi.emss.gov.uk"
 fi

( cat <<EOFCAT
${L_ORACLESID}_PUBLIC =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${HOST_STR})(PORT = ${L_TNS_PORT}))
    )
  )

  )

SID_LIST_${L_ORACLESID}_PUBLIC =
  (SID_LIST =
    (SID_DESC =
      (ORACLE_HOME= $(FN_ORACLE_HOME $L_ORACLESID ))
      (SID_NAME = ${L_ORACLESID})
    )
  )

STARTUP_WAIT_TIME_${L_ORACLESID}_PUBLIC = 0
CONNECT_TIMEOUT_${L_ORACLESID}_PUBLIC = 10
TRACE_LEVEL_${L_ORACLESID}_PUBLIC = OFF

LOG_DIRECTORY_${L_ORACLESID}_PUBLIC = ${L_ORACLEHOME}/network/admin/log
LOG_FILE_${L_ORACLESID}_PUBLIC = listener
TRACE_DIRECTORY_${L_ORACLESID}_PUBLIC = ${L_ORACLEHOME}/network/admin/trace
TRACE_FILE_${L_ORACLESID}_PUBLIC = listener
ADMIN_RESTRICTIONS_${L_ORACLESID}_PUBLIC = OFF
SUBSCRIBE_FOR_NODE_DOWN_EVENT_${L_ORACLESID}_PUBLIC = OFF
EOFCAT
) >> ${L_ORACLEHOME}/network/admin/${L_DBCONTEXT_NAME}/listener_ifile.ora

# start the public listener
${L_ORACLEHOME}/bin/lsnrctl start ${L_ORACLESID}_PUBLIC

#  check the status of the public listener

${L_ORACLEHOME}/bin/lsnrctl status ${L_ORACLESID}_PUBLIC

}


function sql_dir_txt
{
  ## called by FN_db_dirs ##

  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  sqlplus -s / as sysdba  <<SQLEND
    set pages 200 lines 5000 trims on head off
    set echo on feedback off

    select 'create or replace directory '|| DIRECTORY_NAME || '  as ''' || replace(DIRECTORY_PATH,'${LC_S_SID}','${L_LCORACLESID}')||''';'
    from dba_directories
    where directory_path like '%${LC_S_SID}%';
SQLEND

} ### end of sql_dir_txt ###


function FN_db_dirs
{
  ##FN_ORACLE_ENV
 LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  sqlplus  -s / as sysdba <<EOF
    whenever sqlerror exit FAILURE;

    set pages 0 lines 500 trims on echo on verify on
    -- select 'create or replace directory '||DIRECTORY_NAME||' as ''' ||DIRECTORY_PATH ||''';'
    --from dba_directories;

    --create or replace directory ORACLE_OCM_CONFIG_DIR as '/d25/prd3/db/tech_st/10.2.0/ccr/state';

    --removed as per Nr-13001012
    --prompt 'create or replace directory XXLCC_REC_CSV_INV_DIR as /${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/irs_inv/extract/temp;';
    --create or replace directory XXLCC_REC_CSV_INV_DIR as '/${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/irs_inv/extract/temp';

    prompt 'create or replace directory XXLCC_PAY_XML_INV_DIR_1496_X as /${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/xml/supplier_invoice/1496/no_po;'
    create or replace directory XXLCC_PAY_XML_INV_DIR_1496_X as '/${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/xml/supplier_invoice/1496/no_po';

    prompt 'create or replace directory XXLCC_PAY_XML_INV_DIR_1496 as /${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/xml/supplier_invoice/1496;'
    create or replace directory XXLCC_PAY_XML_INV_DIR_1496 as '/${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/xml/supplier_invoice/1496';

    prompt 'create or replace directory XXLCC_PAY_XML_INV_DIR as /${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/xml/supplier_invoice/temp;'
    create or replace directory XXLCC_PAY_XML_INV_DIR as '/${L_APPLUSER}/apps/apps_st/custom/xxlcc/12.0.0/xml/supplier_invoice/temp';

    prompt 'create or replace directory PSLDIR095019 as /${L_APPLUSER}/csf/out;'
    create or replace directory PSLDIR095019 as '/${L_APPLUSER}/csf/out';

    prompt 'create or replace directory PSLDIR154530 as /${L_APPLUSER}/csf/out;'
    create or replace directory PSLDIR154530 as '/${L_APPLUSER}/csf/out';

    prompt 'create or replace directory PSLDIR140850 as /${L_APPLUSER}/csf/out;'
    create or replace directory PSLDIR140850 as '/${L_APPLUSER}/csf/out';

    prompt 'create or replace directory WORK_DIR as /${L_ORAUSER}/inst/admin/${L_DBCONTEXT_NAME}/work;'
    create or replace directory WORK_DIR as '/${L_ORAUSER}/inst/admin/${L_DBCONTEXT_NAME}/work';

    prompt 'create or replace directory DATA_PUMP_DIR as /${L_ORAUSER}/inst/admin/${L_DBCONTEXT_NAME}/export;'
    create or replace directory DATA_PUMP_DIR as '/${L_ORAUSER}/inst/admin/${L_DBCONTEXT_NAME}/export';

    prompt 'create or replace directory ODPDIR as /usr/tmp;'
    create or replace directory ODPDIR as '/usr/tmp';

    prompt 'create or replace directory ECX_UTL_XSLT_DIR_OBJ as /usr/tmp;'
    create or replace directory ECX_UTL_XSLT_DIR_OBJ as '/usr/tmp';

    prompt 'create or replace directory ECX_UTL_LOG_DIR_OBJ as /usr/tmp;'
    create or replace directory ECX_UTL_LOG_DIR_OBJ as '/usr/tmp';

    --create or replace directory APPS_DATA_FILE_DIR as '{L_ORACLEHOME)/appsutil/outbound/{L_CONTEXT_NAME}';

    prompt 'Nr-12032152 create or replace directory XXLCC_HR_OUTPUT as /${L_APPLUSER}/csf/out;'
    create or replace directory XXLCC_HR_OUTPUT as '/${L_APPLUSER}/csf/out';


    set pages 200 lines 5000 trims on head off
    prompt 'PRE - The database directories that have the source remaining in their path'

    select DIRECTORY_NAME|| ' ' ||DIRECTORY_PATH  "pre change"
    from dba_directories
    where directory_path like '%${LC_S_SID}%';

    set echo on
    $(sql_dir_txt)
    set echo off

    prompt 'POST - The database directories that have the source remaining in their path'

    select DIRECTORY_NAME|| ' ' ||DIRECTORY_PATH  "post change"
    from dba_directories
    where directory_path like '%${LC_S_SID}%';
EOF

  export L_ERROR=$?
}


function FN_db_links
{
  #
  ## OWNER    DB_LINK                                  USERNAME HOST
  ## -------- ---------------------------------------- -------- --------------------
  ## APPS     APPS_TO_APPS                             APPS     RIPRD34
  ## APPS     APPS_TO_APPS.LEICS.GOV.UK                APPS     DEV4
  ## APPS     APPS_TO_APPS.US.ORACLE.COM               APPS     EDV3_DDS.world
  ## APPS     EDW_APPS_TO_WH                           APPS     RIPRD34
  ## APPS     EDW_APPS_TO_WH.LEICS.GOV.UK              APPS     DEV4
  ## APPS     EDW_APPS_TO_WH.US.ORACLE.COM             APPS     EDV3_DDS.world
  ## APPS     FIS_PRD3_PRD2_DBLNK.LEICS.GOV.UK         APPS     EDV3_DDS.world
  ## APPS     FIS_PRD3_TMP1_DBLNK.LEICS.GOV.UK         APPS     EDV3_DDS.world
  ## BODATA   EBUS_LPMS_DBLNK.LEICS.GOV.UK             BODATA   lpms_dds
  ## BODATA   EBUS_LPNT_DBLNK.LEICS.GOV.UK             GUEST    lpnt


  export L_ERROR=$?

}

function FN_user_ops
{
  sqlplus  -s / as sysdba <<EOF
    prompt 'Dropping the source  ops\$appl${L_S_SID} account';
    drop user ops\$appl${L_S_SID} cascade;

    whenever sqlerror exit FAILURE;
    prompt 'Creating the OPS\$APPL${L_T_SID} user account';
    create user ops\$appl${L_T_SID}
    identified externally
    temporary tablespace temp
    quota unlimited on APPS_TS_TX_DATA
    default tablespace APPS_TS_TX_DATA;

    grant create session to ops\$appl${L_T_SID};

    grant create table to ops\$appl${L_T_SID};

EOF
  export L_ERROR=$?
}   ### End of FN_user_ops ###


function FN_user_reset_db_users
{
  sqlplus  -s / as sysdba <<SQLEOF

  prompt alter user arts_user identified by arts_user_${L_ORACLESID};
         alter user arts_user identified by arts_user_${L_ORACLESID};

  prompt alter user beau_user identified by beau_user_${L_ORACLESID};
         alter user beau_user identified by beau_user_${L_ORACLESID};

  prompt alter user capm_user identified by capm_user_${L_ORACLESID};
         alter user capm_user identified by capm_user_${L_ORACLESID};

  prompt alter user cds_user identified by cds_user_${L_ORACLESID};
         alter user cds_user identified by cds_user_${L_ORACLESID};

  prompt alter user cts_user identified by cts_user_${L_ORACLESID};
         alter user cts_user identified by cts_user_${L_ORACLESID};

  prompt alter user dlo_user identified by dlo_user_${L_ORACLESID};
         alter user dlo_user identified by dlo_user_${L_ORACLESID};

  prompt alter user fpfp_user identified by fpfp_user_${L_ORACLESID};
         alter user fpfp_user identified by fpfp_user_${L_ORACLESID};

  prompt alter user htwm_user identified by htwm_user_${L_ORACLESID};
         alter user htwm_user identified by htwm_user_${L_ORACLESID};

  prompt alter user ipay_user identified by ipay_user_${L_ORACLESID};
         alter user ipay_user identified by ipay_user_${L_ORACLESID};

  prompt alter user ishc_user identified by ishc_user_${L_ORACLESID};
         alter user ishc_user identified by ishc_user_${L_ORACLESID};

  prompt alter user sky_user identified by sky_user_${L_ORACLESID};
         alter user sky_user identified by sky_user_${L_ORACLESID};

  prompt alter user ssar_user identified by ssar_user_${L_ORACLESID};
         alter user ssar_user identified by ssar_user_${L_ORACLESID};

  prompt alter user ssis_user identified by ssis_user_${L_ORACLESID};
         alter user ssis_user identified by ssis_user_${L_ORACLESID};

  prompt alter user tar_user identified by tar_user_${L_ORACLESID};
         alter user tar_user identified by tar_user_${L_ORACLESID};

  prompt alter user trent_user identified by trent_user_${L_ORACLESID};
         alter user trent_user identified by trent_user_${L_ORACLESID};

  prompt alter user commet identified by commet_${L_ORACLESID};
         alter user commet identified by commet_${L_ORACLESID};

  prompt alter user prop identified by prop_${L_ORACLESID};
         alter user prop identified by prop_${L_ORACLESID};

  prompt alter user crm_user identified by crm_user_${L_ORACLESID};
         alter user crm_user identified by crm_user_${L_ORACLESID};

  prompt alter user xxlcc_eform_sup_user identified by xxlcc_eform_sup_user_${L_ORACLESID};
         alter user xxlcc_eform_sup_user identified by xxlcc_eform_sup_user_${L_ORACLESID};

  prompt alter user xxntcty_eform_sup_user identified by xxntcty_eform_sup_user_${L_ORACLESID};
         alter user xxntcty_eform_sup_user identified by xxntcty_eform_sup_user_${L_ORACLESID};

  prompt alter user bodata identified by bodata_${L_ORACLESID};
         alter user bodata identified by bodata_${L_ORACLESID};

  prompt alter user xxlcc_ascs_user identified by xxlcc_ascs_user_${L_ORACLESID};
         alter user xxlcc_ascs_user identified by xxlcc_ascs_user_${L_ORACLESID};

  prompt alter user xxlcc_commet_user identified by xxlcc_commet_user_${L_ORACLESID};
         alter user xxlcc_commet_user identified by xxlcc_commet_user_${L_ORACLESID};

  prompt alter user xxlcc_esc_user identified by xxlcc_esc_user_${L_ORACLESID};
         alter user xxlcc_esc_user identified by xxlcc_esc_user_${L_ORACLESID};

  prompt alter user xxlcc_htwm_user identified by xxlcc_htwm_user_${L_ORACLESID};
         alter user xxlcc_htwm_user identified by xxlcc_htwm_user_${L_ORACLESID};

  prompt alter user xxlcc_cis_user identified by xxlcc_cis_user_${L_ORACLESID};
         alter user xxlcc_cis_user identified by xxlcc_cis_user_${L_ORACLESID};

  prompt alter user xxlcc_lm_user identified by xxlcc_lm_user_${L_ORACLESID};
         alter user xxlcc_lm_user identified by xxlcc_lm_user_${L_ORACLESID};

  prompt alter user xxlcc_one_user identified by xxlcc_one_user_${L_ORACLESID};
         alter user xxlcc_one_user identified by xxlcc_one_user_${L_ORACLESID};

  prompt alter user xxlcc_timesheet_user identified by xlcc_timesheet_user_${L_ORACLESID};
         alter user xxlcc_timesheet_user identified by xlcc_timesheet_user_${L_ORACLESID};

  prompt alter user dpdp_user identified by dpdp_user_${L_ORACLESID};
         alter user dpdp_user identified by dpdp_user_${L_ORACLESID};

  prompt alter user xxlcc identified by custom_${L_ORACLESID};
         alter user xxlcc identified by custom_${L_ORACLESID};

  prompt alter user xxmig identified by cust0m_${L_ORACLESID};
         alter user xxmig identified by cust0m_${L_ORACLESID};

  prompt alter user xxntcty identified by cu5tom_${L_ORACLESID};
         alter user xxntcty identified by cu5tom_${L_ORACLESID};

SQLEOF
  export L_ERROR=$?
}   ### End of FN_user_reset_db_users ###


function FN_Conc_Reqs
{
  L_PASSWD=$(FN_GetAPPSPassword $L_S_SID)

    sqlplus -s /nolog <<EOF
      connect apps/${L_PASSWD}

      whenever sqlerror exit FAILURE

      prompt Removing the running concurrent requests...
      delete from fnd_concurrent_requests
      where phase_code = 'R'
        or CONCURRENT_PROGRAM_ID = 38121;

-- FNDGSCST 38121 Gather Schema Statistics

      prompt All remaining concurrent requests on hold...
      update fnd_concurrent_requests
      set hold_flag = 'Y'
      where phase_code = 'P'
        and concurrent_program_id NOT in ( 42852, 41993, 66269, 36888, 43593, 31659, 48347, 48346, 48348);

-- User Program Name                                             CONCURRENT_PROGRAM_NAME CONCURRENT_PROGRAM_ID
-- ------------------------------------------------------------- ----------------------- ---------------------
-- OAM Applications Dashboard Collection                           FNDOAMCOL              42852
-- Purge Logs and Closed System Alerts                             FNDLGPRG               41993
-- Remove obsolete sessions from fnd_sessions                      PER_FND_SESSIONS_CLEANUP 66269
--
-- Workflow - Deferred All Processes (Workflow Background Process) FNDWFBG                36888
-- Workflow Timeout Processes (Workflow Background Process)        FNDWFBG                36888
-- Workflow Stuck Processes (Workflow Background Process)          FNDWFBG                36888
-- Workflow Control Queue Cleanup                                  FNDWFBES_CONTROL_QUEUE_CLEANUP 43593
-- Synchronize Workflow LOCAL tables (Report Set)                  FNDRSSUB               31659
-- Workflow Work Items Statistics Concurrent Program               FNDWFWITSTATCC         48346
-- Workflow Agent Activity Statistics Concurrent Program           FNDWFAASTATCC          48347
-- Workflow Mailer Statistics Concurrent Program                   FNDWFMLRSTATCC         48348

-- to be changed milbyr 20120111     prompt Cost Manager                         33733
-- to be changed milbyr 20120111     prompt Manager:Lot Move Transactions        1007492
-- to be changed milbyr 20120111     prompt Process transaction interface        32320
-- to be changed milbyr 20120111     prompt WIP Move Transaction Manager         31915

    prompt commit
    commit;

    prompt concurrent request status
--    select phase_code, status_code, hold_flag, count(*)
--    from fnd_concurrent_requests
--    group by phase_code, status_code, hold_flag;

    -- 20120910 milbyr --
    prompt Fix for the Output Post Processor

    update fnd_concurrent_queues
    set RUNNING_PROCESSES = 0
    where CONCURRENT_QUEUE_NAME = 'FNDCPOPP';

    --     delete from  fnd_concurrent_processes
    --     where CONCURRENT_QUEUE_ID = (
    --         select CONCURRENT_QUEUE_id
    --         from  fnd_concurrent_queues
    --         where CONCURRENT_QUEUE_NAME = 'FNDCPOPP'
    --         )
    --       and CREATION_DATE < sysdate -2;


    -- 20120911 ve-deanm1 (Nr-12029455)
    prompt Fix for the oc4j containers related to workflow
    prompt   cleardown required as backup taken while application hot

    update FND_CONCURRENT_QUEUES
    set RUNNING_PROCESSES = 0;
    --where CONCURRENT_QUEUE_NAME in ('WFMLRSVC','WFWSSVC','WFALSNRSVC')

    --    delete from  FND_CONCURRENT_PROCESSES
    --    where CONCURRENT_QUEUE_ID in (
    --        select CONCURRENT_QUEUE_ID
    --        from  FND_CONCURRENT_QUEUES
    --        where CONCURRENT_QUEUE_NAME in ('WFMLRSVC','WFWSSVC','WFALSNRSVC')
    --        )
    --      AND CREATION_DATE < sysdate -2;

   -- milbyr 20130411 Nr-13010156
   truncate table applsys.fnd_concurrent_processes;

EOF
  export L_ERROR=$?
}


function FN_Main
{
  FN_Init_Vars ${L_T_SID}
  FN_List_Vars

  while  ( [ $L_COMPLETE -eq 1 ] && [ $L_ERROR -eq 0 ] )
  do
    case $L_STEP in
      1)
        echo "at step $L_STEP: FN_Sym_Links"
        FN_Sym_Links
        FN_Backup_link
        FN_Inc
  #      L_COMPLETE=0
        ;;
      2)
        echo "at step $L_STEP: FN_dbTechStack"
        FN_ORACLE_ENV
        FN_dbTechStack
        FN_Inc
  #      L_COMPLETE=0
        ;;
      3)
        echo "at step $L_STEP: FN_InitOra"
        FN_ORACLE_ENV
        FN_InitOra
        FN_Inc
  #     L_COMPLETE=0
        ;;
      4)
        echo "at step $L_STEP: FN_orapwd"
        FN_orapwd manager
        FN_Inc
   #     L_COMPLETE=0
        ;;
      5)
        echo "at step $L_STEP: FN_ora_env"
        # created in step 2 above #FN_ora_env
        FN_ORACLE_ENV
        FN_Inc
   #     L_COMPLETE=0
        ;;
      6)
        echo "at step $L_STEP: FN_CR_CTL_Script"
        FN_CR_CTL_Script
        FN_CR_TMP_Script
        FN_Inc
   #     L_COMPLETE=0
        ;;
      7)
        echo "at step $L_STEP: FN_CR_CTL"
        FN_ORACLE_ENV
        FN_CR_CTL
        FN_Inc
   #     L_COMPLETE=0
        ;;
      8)
        echo "at step $L_STEP: FN_ALF"
        FN_ALF
        FN_Inc
   #     L_COMPLETE=0
        ;;
      9)
        echo "at step $L_STEP: FN_Recover_DB"
        ### not working correctly ####
        ### there is a possibility the ALF does not exist ####
        ### ALF file are not required for DR ####
        FN_Recover_DB
        FN_Inc
   #     L_COMPLETE=0
        ;;
      10)
        echo "at step $L_STEP: FN_Open_DB"
        FN_Open_DB
        FN_Inc
   #     L_COMPLETE=0
        ;;
      11)
        echo "at step $L_STEP: FN_DB_CTL stop"
        ##FN_DB_CTL stop
        FN_Inc
#        L_COMPLETE=0
        ;;
      12)
        echo "at step $L_STEP: FN_DB_CTL start"
        ##FN_DB_CTL start
        FN_Inc
#        L_COMPLETE=0
        ;;
      13)
        echo "at step $L_STEP: FN_clone_lib"
        # maybe have to bounce the database
        # to use the new init.ora or spfile
        FN_ORACLE_ENV
        FN_clone_lib
        FN_Inc
#        L_COMPLETE=0
        ;;
      14)
        echo "at step $L_STEP: FN_dbconfig"
        FN_ORACLE_ENV
        ####FN_dbconfig
          ## AC-00423: Template file: /orau010/db/tech_st/10.2.0/appsutil/template/adcrdb.sh missing from file system.
          ## Raised by oracle.apps.ad.autoconfig.InstantiateFile
          #
          ## work around until problem fixed
          # copy adcrdb.sh
          # clean nodes
          # run adautocfg.sh
        FN_autocfg
        FN_Inc
#        L_COMPLETE=0
        ;;
      15)
        echo "at step $L_STEP: FN_tns_ifile"
        FN_tns_ifile
        FN_Inc
#        L_COMPLETE=0
        ;;
      16)
        echo "at step $L_STEP: FN_lsnr_ifile"
        FN_lsnr_ifile
        FN_Inc
#        L_COMPLETE=0
        ;;
      17)
        echo "at step $L_STEP: FN_db_dirs"
        FN_db_dirs
        FN_Inc
#        L_COMPLETE=0
        ;;
      18)
        echo "at step $L_STEP: FN_db_links"
        FN_db_links
        FN_Inc
#        L_COMPLETE=0
        ;;
      19)
        FN_ORACLE_ENV
        echo "at step $L_STEP: FN_user_(various)"
        FN_user_ops
        FN_user_reset_db_users
        FN_Inc
#        L_COMPLETE=0
        ;;
      20)
        echo "at step $L_STEP: FN_Conc_Reqs"
        FN_ORACLE_ENV
        FN_Conc_Reqs
        FN_Inc
        L_COMPLETE=0
        ;;
      *)
        echo "this is an error "
        exit 1
        ;;
      esac
  done

  FN_Debug "Complete"
}

# - - - - - - - - - - - -  Main - - - - - - - - - #
  export L_S_SID=${1:?"Missing the source sid"}
  export L_T_SID=${2:?"Missing the target sid"}



  PG=$(basename $0)
  LG=${PG%%.ksh}
  TS=`date +%Y%m%d`

  export L_COMPLETE=1
  export L_ERROR=0
  export L_STEP=${3:-1}

  if FN_ValidENV $L_T_SID ; then
    FN_Main 2>&1 | tee -a $DBA/logs/${LG}_${L_S_SID}_${L_T_SID}_$(hostname).$TS.log
  else
    echo " the $L_T_SID is invalid"
    export L_ERROR=1
  fi

  exit $L_ERROR
# - - - - - - - - - - - - - - - - - - - - - - - - #
