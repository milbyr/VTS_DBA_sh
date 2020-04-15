#!/usr/bin/bash
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# R. Milby      20141205                                                                          #
#                                                                                                 #
# To recover a hot backup and clone                                                               #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# History                                                                                         #
# converted to EMSS R12.2                                                                         #
#                                                                                                 #
# When     Who		What                                                              	  #
# =====================================================================                     	  #
# 20190617 milbyr	Migrated to NCL.                                                          #
# 20190618 milbyr	Completed testing on U002 (NCL).					  #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
#
export DBA=/export/vtssupp/VTS
export L_VERBOSE=1
export G_ENV=1

if [ -f $DBA/bin/vts_utils.sh ]; then
.   $DBA/bin/vts_utils.sh
else
  echo "$DBA/bin/vts_utils.sh is missing"
  exit 1
fi


function FN_Inc
{
  export L_STEP=$((L_STEP + 1))
}


function FN_Header
{
  printf "\n${LN_BREAK}\n"
  printf "= STEP ${L_STEP} : starting $@ `date`\n"
  printf "${LN_BREAK}\n"

}   ### End of FN_Header ##


function FN_InitOra_old
{
  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )

( cat <<EOF

db_name = $L_ORACLESID
control_files  = /ora${L_LCORACLESID}/data01/cntrl01.dbf,/ora${L_LCORACLESID}/data02/cntrl02.dbf,/ora${L_LCORACLESID}/fra/cntrl03.dbf
db_files                        = 512         # Max. no. of database files
undo_management=AUTO                   # Required 11i setting
undo_tablespace=APPS_UNDOTS1     # Required 11i setting
sga_target						= 5G
processes						= 1200
sessions						= 2400
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
} ### End of FN_orapwd ###


function FN_Sym_Links
{
echo
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
 L_DN=/${L_ORAUSER}/tech_st/diag/${L_S_SID}_${L_DBSRV}/backup_archive

 if [ -d ${L_DN} ]; then
  l_dir=`ls -1dtr ${L_DN}/backup_*|tail -1`
  #FN_Debug "FN_backup_dir: l_dir is $l_dir"
  echo "$l_dir"
 else
  echo "FN_backup_dir: ${L_DN} does NOT exist"
 fi
}


function FN_ALF
{
  FN_Header FN_ALF

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


function FN_Clone_dir
{
  FN_Header FN_Clone_dir
  CLONE_DIR=$HOME/CLONE_${L_T_SID}
  
  if [ -d $CLONE_DIR ]; then
     echo $CLONE_DIR
  else
     mkdir -p $CLONE_DIR
     echo $CLONE_DIR
  fi
}


function FN_CR_CTL_Script
{
  FN_Header FN_CR_CTL_Script


  UC_S_SID=${L_S_SID^^}
  UC_T_SID=${L_T_SID^^}

  LC_S_SID=${L_S_SID,,}
  LC_T_SID=${L_T_SID,,}

  L_BKUP_DIR=$(FN_backup_dir)

  L_FN=$( ls -1tr ${L_BKUP_DIR}/*trc | tail -1 )
  FN_Print "Generating Control file script from ${L_FN}"

  S_LN=`egrep -n "CREATE CONTROLFILE" $L_FN | head -1 | awk -F: '{print $1}'`
  E_LN=`egrep -n "CHARACTER" $L_FN | head -1 | awk -F: '{print $1}'`
  ROWS=$( wc -l $L_FN | awk '{print $1}' )
  
  ##  The source trace file has a different mount point /u01 ## 
  ##  tail -$((ROWS - ${S_LN} + 1 ))  $L_FN | head -$((E_LN - ${S_LN} + 2 )) | grep -v "^--" | sed 's/REUSE/SET/' | sed 's/NORESETLOGS/RESETLOGS/' | \
  ##   sed 's/ARCHIVELOG/NOARCHIVELOG/' | sed "s/$UC_S_SID/$UC_T_SID/" | sed "s/$LC_S_SID/$LC_T_SID/" > $L_BKUP_DIR/cr_ctl.sql

  tail -$((ROWS - ${S_LN} + 1 ))  $L_FN | head -$((E_LN - ${S_LN} + 2 )) | grep -v "^--" | sed 's/REUSE/SET/' | \
      sed 's/NORESETLOGS/RESETLOGS/' | sed "s/ARCHIVELOG/NOARCHIVELOG/" | sed -e "s/${UC_S_SID}/${UC_T_SID}/" | \
      sed -e "s/\/u01\/app\/oracle\/oradata\/log/\/${L_ORAUSER}\/apps_st\/data01\/log/"                       | \
      sed -e "s/\/u01\/app\/oracle\/oradata/\/${L_ORAUSER}\/apps_st\/data03/" > $L_BKUP_DIR/cr_ctl.sql

      ## sed -e "s/${LC_S_SID}/${LC_T_SID}/" | \

  FN_Print "Created $L_BKUP_DIR/cr_ctl.sql"
}


function FN_CR_TMP_Script
{
  FN_Header FN_CR_TMP_Script
  export L_BKUP_DIR=$(FN_backup_dir)
 ( cat <<EOF

ALTER TABLESPACE TEMP
ADD TEMPFILE '/ora${L_LCORACLESID}/data03/temp01.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 4000M;

EOF
 ) >$L_BKUP_DIR/cr_tmp.sql 2>&1

}


function FN_ORACLE_ENV
{
  ## FN_Header FN_ORACLE_ENV
   
  if [ $G_ENV -eq 1 ]; then
    export ORACLE_HOME=$L_ORACLEHOME
    if [ -f  $L_ORACLEHOME/${L_DBCONTEXT_NAME}.env ]; then
      . $L_ORACLEHOME/${L_DBCONTEXT_NAME}.env
      export G_ENV=0
    else
      FN_Error "FN_ORACLE_ENV: the environment file $L_ORACLEHOME/${L_DBCONTEXT_NAME}.env DOES NOT EXIST"
      export ORACLE_SID=${L_ORACLESID}
      export LD_LIBRARY_PATH=${ORACLE_HOME}/lib,${ORACLE_HOME}/ctx/lib
      export PATH=$ORACLE_HOME/bin:$PATH:/usr/ccs/bin:/usr/bin
      export TNS_ADMIN=$ORACLE_HOME/network/admin/${L_ORACLESID}_${L_DBSRV}
    fi
  else
    FN_Debug "FN_ORACLE_ENV: G_ENV=$G_ENV :- ${L_DBCONTEXT_NAME}.env already run"
  fi
}


function FN_Env
{
  FN_Header FN_Env
  if [ -f $HOME/scripts/$L_T_SID.env ]; then
     . $HOME/scripts/$L_T_SID.env
  else
     echo "Error: Environment file is missing."
     exit;
  fi
}


function FN_DB_CTL
{
  FN_Header FN_DB_CTL

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


function FN_Check_cr
{
  FN_Header FN_Check_cr

  for L_CTL_FN in `awk -F= '/^control_files/ { gsub(","," ", $2); print $2 }'  ${L_ORACLEHOME}/dbs/init${L_T_SID}.ora`
  do 
    if [ -f $L_CTL_FN ]; then
     echo "Removing control file $L_CTL_FN"
     rm -rf $L_CTL_FN 
    else
     echo "The control file $L_CTL_FN does not exist at this point"
    fi
  done 
}


function FN_CR_CTL
{
  FN_Header FN_CR_CTL

  FN_Print "Creating database control files."

  export L_BKUP_DIR=$(FN_backup_dir)
  
  sqlplus -s "/ as sysdba" << SQLEOF
    --create spfile from pfile;
    startup nomount;
    @$L_BKUP_DIR/cr_ctl.sql
SQLEOF

  export L_ERROR=$?
  if [ $L_ERROR -ne 0 ]; then
    FN_Print "The creation of the control files has FAILED"
  else
    FN_Print "The control files have been created"
  fi
}


function FN_Recover_DB
{
  FN_Header FN_Recover_DB

  FN_Print "Recover Database"
  
  sqlplus -s "/as sysdba" << SQLEOF
    -- ## spfile not created yet ## --alter system set log_archive_format='%t_%s_%r.arc' scope=spfile; 
    shutdown immediate;
    startup mount;
    set autorecovery on
    --  the dataguard database does not require recovery --
    recover database using backup controlfile until cancel;
    
    --CANCEL
SQLEOF

  export L_ERROR=$?
  if [ $L_ERROR -ne 0 ]; then
    FN_Print "The database recovery has FAILED ($L_ERROR)"
  else
    FN_Print "The database recovery was successful"
  fi

} ### End of FN_Recover_DB ###


function FN_Open_DB
{
  FN_Header FN_Open_DB

  FN_Print "Opening the Database."
  
  sqlplus -s "/ as sysdba" << SQLEOF
    whenever sqlerror exit FAILURE;
    alter database open resetlogs;
    select name, open_mode from v\$database;
    shutdown immediate;
    create spfile from pfile;
    startup;

SQLEOF

  export L_ERROR=$?
  if [ $L_ERROR -ne 0 ]; then
    FN_Print "The database OPEN has FAILED ($L_ERROR)"
  else
    FN_Print "The database OPEN was successful"
  fi
}


function FN_add_temp
{
  FN_Header FN_add_temp

  FN_Print "Adding Tempfiles (TEMP and QV_TEMP."
  
  sqlplus -s "/as sysdba"  << SQLEOF
    set echo on verify on
    ALTER TABLESPACE TEMP ADD TEMPFILE '/${L_ORAUSER}/apps_st/data03/temp01.dbf' size 4G REUSE autoextend on maxsize 8g;
    ALTER TABLESPACE TEMP ADD TEMPFILE '/${L_ORAUSER}/apps_st/data03/temp02.dbf' size 2G REUSE autoextend on maxsize 8g;
    prompt  There might be a requirement for additional CUSTOM temp tablespaces.
SQLEOF
}


function FN_genpairs 
{
  FN_Header FN_genpairs

 L_P_FN=${DBA}/logs/pairsfile_${L_T_SID}_${TS}.txt
  FN_Print "Generating Pairsfile.(${L_P_FN})"

( cat <<CATEOF
s_dbhost=${L_DBSRV}
s_dbCluster=false
s_dbSid=${L_T_SID}
s_db_oh=${L_ORACLEHOME}
s_display=${L_DBSRV}:1.0
s_port_pool=$( echo ${L_PORT} | cut -d, -f1 )
s_base=/${L_ORAUSER}
s_dbhome1=/${L_ORAUSER}/apps_st/data01
s_dbhome2=/${L_ORAUSER}/apps_st/data02
s_dbhome3=/${L_ORAUSER}/apps_st/data03
s_archive_dest=/${L_ORAUSER}/apps_st/fra
s_archive_format=%t_%s_%r.arc
s_db_sga_target=8G
s_db_pga_aggregate_target=2G
s_db_shared_pool_size=2500M
s_db_processes=2000
s_db_sessions=4000
s_db_util_filedir=/${L_APPLUSER}/csf/temp,/${L_APPLUSER}/csf/out,/${L_APPLUSER}/csf/log
CATEOF
) > ${L_P_FN}
}


function FN_adclonectx
{
  FN_Header FN_adclonectx
  FN_Print "Ganerating ${L_T_SID} DB Context File"
  
  echo $(FN_GetAPPSPassword $L_S_SID) | perl ${L_ORACLEHOME}/appsutil/clone/bin/adclonectx.pl contextfile=${L_ORACLEHOME}/appsutil/${L_S_SID}_${L_DBSRV}.xml pairsfile=${DBA}/logs/pairsfile_${L_T_SID}_${TS}.txt outfile=${L_ORACLEHOME}/appsutil/${L_T_SID}_${L_DBSRV}.xml noprompt

  export L_ERROR=$?
  
  if [ $L_ERROR != 0 ];
  then
     FN_Print "DB adclonectx failed."
  else
     FN_Print "DB adclonectx completed."
  fi
}


function FN_dbTechStack
{
  FN_Header FN_dbTechStack

  FN_Print "Running DB Tech Stack"
  
  echo $(FN_GetAPPSPassword $L_S_SID) | perl ${L_ORACLEHOME}/appsutil/clone/bin/adcfgclone.pl dbTechStack ${L_ORACLEHOME}/appsutil/${L_T_SID}_${L_DBSRV}.xml

  export L_ERROR=$?
  
  if [ $L_ERROR != 0 ];
  then
     echo "DB Tech Stack failed."
  else
     echo "DB Tech Stack completed."
  fi
   
}


function FN_dbconfig
{
  FN_Header FN_dbconfig

  FN_Print "Running DB Config."
  
  echo $(FN_GetAPPSPassword $L_S_SID) | perl ${L_ORACLEHOME}/appsutil/clone/bin/adcfgclone.pl dbconfig ${L_ORACLEHOME}/appsutil/${L_T_SID}_${L_DBSRV}.xml

  export L_ERROR=$?

  if [ $L_ERROR != 0 ];
  then
     echo "DB config failed."
  else
     echo "DB config completed."
  fi

}


function FN_clone_lib
{
  FN_Header FN_clone_lib

  FN_Print "Update Library." 
  

  sqlplus -s "/as sysdba" << SQLEOF
  @?/appsutil/install/${L_T_SID}_${L_DBSRV}/adupdlib.sql so
SQLEOF
}


function FN_setup_clean
{
  FN_Header FN_setup_clean

  FN_Print "Running Clone Setup Clean."

  sqlplus -s apps/$(FN_GetAPPSPassword $L_S_SID) << SQLEOF
    set echo on termout on feedback on
    exec fnd_conc_clone.setup_clean;
SQLEOF
}


function FN_updt_utl
{
  FN_Header FN_updt_utl

  sqlplus -s "/ as sysdba" << SQLEOF
    prompt 'Updating the spfile to set the APPLCSF/temp to be the first entry'
    alter system set utl_file_dir='/${L_APPLUSER}/csf/temp','/${L_APPLUSER}/csf/out','/${L_APPLUSER}/csf/log','/${L_APPLUSER}/appsutil/outbound/${L_T_SID}_${L_DBSRV}','/usr/tmp' scope=spfile;
    alter system set diagnostic_dest='/${L_ORAUSER}/tech_st' scope=both;

    prompt 'VCAMP not creating HUGE PAGES'
    prompt 'NOT Changing the database to use Large Pages'
    prompt '-- alter system set lock_sga = true scope=spfile;'

    shutdown immediate;
    create pfile from spfile;
    startup;
    show parameter utl_file_dir
    show parameter lock_sga
SQLEOF
}


function FN_chng_passwd
{
  FN_Header FN_chng_passwd

  FN_Print "Changing SYS/SYSTEM Passwords."

  L_MANAGER=$(FN_PASSWORD_GEN "Manager" $L_ORACLESID)
  L_APEX_PORT=$(( L_PORT + 8100 ))

  FN_Print "Changing APEX listener port to ${L_APEX_PORT}."

  sqlplus -s / as sysdba <<SQLEOF
    whenever sqlerror exit FAILURE;
    alter user system identified by $L_MANAGER;
    alter user sys identified by $L_MANAGER;
    exec dbms_xdb.sethttpport($L_APEX_PORT);

    alter user apps account unlock;
    alter profile default limit FAILED_LOGIN_ATTEMPTS UNLIMITED;
SQLEOF
} ### End of FN_chng_passwd ###


function FN_autocfg
{
  FN_Header FN_autocfg

  if [ -d $ORACLE_HOME/appsutil/scripts/${L_DBCONTEXT_NAME} ]; then
    L_PASSWD=$(FN_GetAPPSPassword $L_S_SID)
    $ORACLE_HOME/appsutil/scripts/${L_DBCONTEXT_NAME}/adautocfg.sh appspass=${L_PASSWD}
  else
    FN_Error "FN_autocfg: $L_ORACLEHOME/appsutil/scripts/${L_DBCONTEXT_NAME} MISSING"
  fi
}   ### end of FN_autocfg ###


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


function FN_DB_Dir
{
  FN_Header FN_DB_Dir

  FN_Print "Updating the XXLB directories"

  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  sqlplus -s "/ as sysdba" << SQLEOF
    create or replace directory TIMEZDIF_DIR            as '${L_ORACLEHOME}/oracore/zoneinfo';
    -- create or replace directory XXLBG_GFI_INT           as '/${L_APPLUSER}/csf/interface09/process';
    -- create or replace directory XXLBG_GFI_INT_BAD_FILES as '/${L_APPLUSER}/csf/interface09/bad_files';
    -- create or replace directory XXLBG_GFI_INT_LOG       as '/${L_APPLUSER}/csf/interface09/log';
    -- create or replace directory XXLBG_GFI_ARC           as '/${L_APPLUSER}/csf/interface09/archive';
    -- create or replace directory XXLBG_GFI_INT_OUTB      as '/${L_APPLUSER}/csf/interface09/outbound';
    create or replace directory EXT_TAB_DATA_1          as '/${L_APPLUSER}/csf/temp';

    prompt 'PRE - The database directories with ${LC_S_SID} in their path'

    set pages 200 lines 5000 trims on head off
    select DIRECTORY_NAME|| ' ' ||DIRECTORY_PATH  "post change"
    from dba_directories
    where directory_path like '%${LC_S_SID}%';

    prompt 'Updating all other database directories with ${LC_S_SID} in their path'
    set echo on
    $(sql_dir_txt)
    set echo off

    prompt 'POST - The database directories with ${LC_S_SID} in their path'

    set pages 200 lines 5000 trims on head off
    select DIRECTORY_NAME|| ' ' ||DIRECTORY_PATH  "post change"
    from dba_directories
    where directory_path like '%${LC_S_SID}%';

SQLEOF
} ### End of FN_DB_Dir ###


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
  echo 
}   ### End of FN_user_ops ###


function FN_user_reset_db_users
{
  sqlplus  -s / as sysdba <<SQLEOF

  prompt alter user xxlbg identified by xxlbg_${L_ORACLESID};
         alter user xxlbg identified by xxlbg_${L_ORACLESID};
 
SQLEOF
  export L_ERROR=$?
}   ### End of FN_user_reset_db_users ###


function FN_Conc_Reqs
{
  FN_Header FN_Conc_Reqs

  L_PASSWD=$(FN_GetAPPSPassword $L_S_SID)

    sqlplus -s /nolog <<SQLEOF
      connect apps/${L_PASSWD}

      whenever sqlerror exit FAILURE

      prompt Changing the running concurrent requests...
      update fnd_concurrent_requests
      set phase_code = 'C', status_code = 'X'
      where phase_code = 'R';

      prompt Changing the pending concurrent requests...
      update fnd_concurrent_requests
      set phase_code = 'C', status_code = 'X'
      where status_code IN ('Q','I')
        and requested_start_date > trunc(sysdate) -2
        and hold_flag = 'N';

SQLEOF
  export L_ERROR=$?
}


function FN_sqlnet
{
  FN_Header FN_sqlnet

  ( cat <<EOF
tcp.validnode_checking = yes
tcp.invited_nodes = (${L_DBSRV}.velocitycloud.io,${L_IASSRV}.volocitycloud.io)
EOF
  ) >> $TNS_ADMIN/sqlnet_ifile.ora

}  ### End of FN_sqlnet ###


function FN_oraInstloc
{
  FN_Header FN_oraInstloc

    ## /orad003/tech_st/product/11.2.0/dbhome_3/oraInventory
  L_FN=/etc/oraInst.loc

  if ! grep ${L_T_SID} ${L_FN} >/dev/null ; then
    printf "\tUpdating the ${L_FN} with ${L_T_SID} details\n"

    (  cat <<EOF
inventory_loc=${ORACLE_HOME}/oraInventory
inst_group=dba
EOF
  ) >${L_FN}

  else
    printf "\tThe ${L_FN} has ${L_T_SID} details\n"
  fi

}   ### End of FN_oraInstloc ###


function FN_detach_ORA_home
{
  FN_Header FN_detach_ORA_home

  L_OH=${L_T_SID}_DB__${L_ORAUSER}_11_2_0
  ## ewprd_DB__u01_app_oracle_product_11_2_0_dbhome_3" "/u01/app/oracle/product/11.2.0/dbhome_3" ##

  FN_Print "\nRemoving ${L_OH} Oracle Home from Inventory."
  
  cd ${L_ORACLEHOME}/oui/bin
  ./runInstaller -detachhome ORACLE_HOME=${L_ORACLEHOME} ORACLE_HOME_NAME="$L_OH"

  cd $HOME
} ### End of FN_detach_ORA_home ###


function FN_tns_ifile
{
  FN_Header FN_tns_ifile

  L_APEX_PORT=$(( L_PORT + 1421 ))
  L_TNS_IFILE=${TNS_ADMIN}/${L_T_SID}_${L_DBSRV}_ifile.ora

  FN_Print "Adding the TNS ifile (${L_TNS_IFILE})"

  (cat <<CATEOF
${L_T_SID}_APEX =
      (DESCRIPTION=
        (ADDRESS=(PROTOCOL=tcp)(HOST=${L_DBSRV}.ncl.ladbrokes.co.uk)(PORT=${L_APEX_PORT}))
        (CONNECT_DATA=
         (service_name=${L_T_SID}_apex)
        )
     )
    
KRONOS_UAT =
       (DESCRIPTION =
          (ADDRESS_LIST =
             (ADDRESS =
                (PROTOCOL = TCP)
                (HOST = 10.224.33.18)
                (PORT = 1521)
             )
          )
          (CONNECT_DATA =
             (SID = dg4UAT)
          )
          (HS=OK)
       )
CATEOF
  ) > ${L_TNS_IFILE}
} ### End of FN_tns_ifile ###


function FN_lsnr_ifile
{
  FN_Header FN_lsnr_ifile

  L_APEX_PORT=$(( L_PORT + 1421 ))
  L_LSNR_IFILE=${TNS_ADMIN}/listener_ifile.ora

  FN_Print "Adding the TNS listener ifile (${L_LSNR_IFILE})"

  (cat <<CATEOF
${L_T_SID}_APEX =
      (DESCRIPTION_LIST =
        (DESCRIPTION =
          (ADDRESS = (PROTOCOL = TCP)(HOST = ${L_DBSRV}.ncl.ladbrokes.co.uk)(PORT = ${L_APEX_PORT}))
        )
      )
    
SID_LIST_${L_T_SID}_APEX =
      (SID_LIST =
        (SID_DESC =
          (ORACLE_HOME= ${L_ORACLEHOME})
          (global_name = ${L_T_SID}_APEX)
          (sid_name = ${L_T_SID})
        )
      )
    
STARTUP_WAIT_TIME_${L_T_SID}_APEX = 0
CONNECT_TIMEOUT_${L_T_SID}_APEX = 10
TRACE_LEVEL_${L_T_SID}_APEX = OFF

LOG_DIRECTORY_${L_T_SID}_APEX = ${L_ORACLEHOME}/network/admin
LOG_FILE_${L_T_SID}_APEX = ${L_T_SID}_APEX
TRACE_DIRECTORY_${L_T_SID}_APEX = ${L_ORACLEHOME}/network/admin
TRACE_FILE_${L_T_SID}_APEX = ${L_T_SID}_APEX
ADMIN_RESTRICTIONS_${L_T_SID}_APEX = ON
SUBSCRIBE_FOR_NODE_DOWN_EVENT_${L_T_SID}_APEX = OFF


# added parameters for bug# 9286476
LOG_STATUS_${L_T_SID}_APEX  =  ON
INBOUND_CONNECT_TIMEOUT_${L_T_SID}_APEX = 60

# ADR is only applicable for 11gDB
DIAG_ADR_ENABLED_${L_T_SID}_APEX  = ON
ADR_BASE_${L_T_SID}_APEX =  ${L_ORACLEHOME}/admin/${L_T_SID}_${L_DBSRV}
CATEOF
  ) > ${L_LSNR_IFILE}

  lsnrctl start ${L_T_SID}_APEX

} ### End of FN_lsnr_ifile ###


function FN_kronos
{
  case $L_T_SID in
    U002)
      FN_Print "Configuring the db_links and synonyms for kronos UAT"

       sqlplus -s "/ as sysdba" <<SQLEOF
        set echo on verify on

        drop public database link KRONOS_PRD.US.ORACLE.COM;

        create public database link kronos_UAT
        connect to kronos_odbc_UAT
        identified by S0lsth31m
        using 'KRONOS_UAT';
        
        drop synonym XXLBG.UKCUSTOM_ORGANIZATIONAL_SETS;
        drop synonym XXLBG.UKCUSTOM_INTERFACE_ORG_MAP;
        drop synonym XXLBG.UKCUSTOM_INTERFACE_ORGCOSTING;
        drop synonym XXLBG.UKCUSTOM_INTERFACE_AUDIT;
        drop synonym XXLBG.UKCUSTOM_EMD_EMPLOYEE;
        drop synonym XXLBG.UKCUSTOM_DELEGATION_SETS;
        
        create synonym XXLBG.UKCUSTOM_EMD_EMPLOYEE         for dbo.UKCUSTOM_EMD_EMPLOYEE@KRONOS_UAT;
        create synonym XXLBG.UKCUSTOM_DELEGATION_SETS      for dbo.UKCUSTOM_DELEGATION_SETS@KRONOS_UAT;
        create synonym XXLBG.UKCUSTOM_INTERFACE_AUDIT      for dbo.UKCUSTOM_INTERFACE_AUDIT@KRONOS_UAT;
        create synonym XXLBG.UKCUSTOM_ORGANIZATIONAL_SETS  for dbo.UKCUSTOM_ORGANIZATIONAL_SETS@KRONOS_UAT;
        create synonym XXLBG.UKCUSTOM_INTERFACE_ORG_MAP    for dbo.UKCUSTOM_INTERFACE_ORG_MAP@KRONOS_UAT;
        create synonym XXLBG.UKCUSTOM_INTERFACE_ORGCOSTING for dbo.UKCUSTOM_INTERFACE_ORGCOSTING@KRONOS_UAT;
SQLEOF
    ;;
    *) 
      FN_Print " There is no kronos set-up for this clone (${L_T_SID}"
       sqlplus -s "/ as sysdba" <<SQLEOF
        set echo on verify on

        drop public database link KRONOS_PRD.US.ORACLE.COM;

        drop synonym XXLBG.UKCUSTOM_ORGANIZATIONAL_SETS;
        drop synonym XXLBG.UKCUSTOM_INTERFACE_ORG_MAP;
        drop synonym XXLBG.UKCUSTOM_INTERFACE_ORGCOSTING;
        drop synonym XXLBG.UKCUSTOM_INTERFACE_AUDIT;
        drop synonym XXLBG.UKCUSTOM_EMD_EMPLOYEE;
        drop synonym XXLBG.UKCUSTOM_DELEGATION_SETS;
SQLEOF
    ;;
  esac
}  ### End of FN_kronos ###


function FN_Get_Edition
{
  FN_Header FN_Get_Edition

  L_ED_FN=$DBA/logs/${L_S_SID}_${L_T_SID}_EDITIONS.$TS.txt

  if  [ -f ${L_ED_FN} ]; then
    FN_Print "The Edition file already exists (${L_ED_FN})"
  else
    FN_Print "Creating the Edition file cloning appsTier ${L_ED_FN})"

    sqlplus -s apps/$(FN_GetAPPSPassword $L_S_SID) <<SQLEOF
      set echo off head off pages 300 lines 160 trims on verify off
      prompt ' Creating the clone editions file for appsTier'
      spool ${L_ED_FN}
      SELECT  extractValue(XMLType(TEXT),'//host[@oa_var="s_hostname"]') ||' '||
      extractValue(XMLType(TEXT),'//file_edition_type') ||' '||
      extractValue(XMLType(TEXT),'//file_edition_name')
      from apps.fnd_oam_context_files
      where name not in ('TEMPLATE','METADATA')
      and (status is null or status !='H')
      and EXTRACTVALUE(XMLType(TEXT),'//file_edition_type')='run'
      and CTX_TYPE = 'A';
SQLEOF

  fi
}   ### End of FN_Get_Edition ###


function FN_fix_source_context
{
  FN_Header FN_fix_source_context

  L_ENV_S_LC=${L_S_SID,,}
  L_ENV_T_LC=${L_T_SID,,}

  L_T_FN=${L_ORACLEHOME}/appsutil/${L_ENV_S_LC}_${L_DBSRV}.xml


  if [ -f ${L_T_FN} ]; then
    printf "\n\nThe required CONTEXT_FILE (${L_T_FN}) exists\n"
  else
    printf "\n\nThe required CONTEXT_FILE (${L_T_FN}) DOES NOT exists - generating one\n"
    L_FN=$( ls -1t ${L_ORACLEHOME}/appsutil/${L_ENV_S_LC}_*.xml | head -1 )
    L_OLD_HN=$( basename $L_FN .xml | cut -d_ -f2 )
    cat ${L_FN} | sed -e "s/${L_OLD_HN}/${L_DBSRV}/g" | sed -e "s/\/u01\/app\/oracle\//\/orau001\/tech_st\//g" > ${L_T_FN}
    ls -al ${L_T_FN}
  fi

}   ### End of FN_fix_source_context ###


function FN_Main
{
  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "${PG}.sh  Ver $VERSION starting at `date` \n"
  printf "${LN_BREAK}${LN_BREAK}\n"

  FN_Init_Vars ${L_T_SID}
  FN_List_Vars

  while  ( [ $L_COMPLETE -eq 1 ] && [ $L_ERROR -eq 0 ] )
  do
    case $L_STEP in
      1)
        FN_ORACLE_ENV
        FN_Clone_dir
        FN_Inc
      #  L_COMPLETE=0
        ;;

      2)
        FN_ORACLE_ENV
        FN_genpairs
        FN_Inc
      #  L_COMPLETE=0
        ;;
      3)
        FN_ORACLE_ENV
        FN_fix_source_context
        FN_Inc
      #  L_COMPLETE=0
        ;;
      4)
        FN_ORACLE_ENV
        FN_oraInstloc
        FN_adclonectx 
        FN_Inc
      #  L_COMPLETE=0
        ;;
      5)
        FN_ORACLE_ENV
        ##FN_detach_ORA_home
        FN_Inc
      #  L_COMPLETE=0
        ;;
      6)
        FN_ORACLE_ENV
        FN_dbTechStack 
        chmod 666 /tmp/addbhomtgt.xml
        FN_Inc
      #  L_COMPLETE=0
        ;;
      7)
        FN_ORACLE_ENV
        FN_orapwd manager 
        FN_Inc
      #  L_COMPLETE=0
        ;;
      8)
        FN_ORACLE_ENV
        FN_tns_ifile
        FN_Inc
      #  L_COMPLETE=0
        ;;
      9)
        FN_ORACLE_ENV
        FN_lsnr_ifile
        FN_Inc
      #  L_COMPLETE=0
        ;;
      10)
        FN_ORACLE_ENV
        FN_sqlnet
        FN_Inc
      #  L_COMPLETE=0
        ;;
      11)
        FN_ORACLE_ENV
        FN_CR_CTL_Script
        FN_Inc
      #  L_COMPLETE=0
        ;;
      12)
        FN_ORACLE_ENV
        FN_Check_cr 
        FN_Inc
      #  L_COMPLETE=0
        ;;
      13)
        FN_ORACLE_ENV
        FN_CR_CTL
        FN_Inc
      #  L_COMPLETE=0
        ;;
      14)
        FN_ORACLE_ENV
        FN_Recover_DB
        FN_Inc
      #  L_COMPLETE=0
        ;;
      15)
        FN_ORACLE_ENV
        FN_Open_DB
        FN_Inc
      #  L_COMPLETE=0
        ;;
      16)
        FN_ORACLE_ENV
        FN_add_temp
        FN_Inc
      #  L_COMPLETE=0
        ;;
      17)
        FN_ORACLE_ENV
        FN_Get_Edition
        FN_Inc
      #  L_COMPLETE=0
        ;;
      18)
        FN_ORACLE_ENV
        FN_setup_clean
        FN_Inc
      #  L_COMPLETE=0
        ;;
      19)
        FN_ORACLE_ENV
        FN_clone_lib
        FN_Inc
      #  L_COMPLETE=0
        ;;
      20)
        FN_ORACLE_ENV
        ## FN_dbconfig
        FN_autocfg
        FN_Inc
      #  L_COMPLETE=0
        ;;
      21)
        FN_ORACLE_ENV
        FN_updt_utl
        FN_Inc
      #  L_COMPLETE=0
        ;;
      22)
        FN_ORACLE_ENV
        FN_chng_passwd
        FN_Inc
      #  L_COMPLETE=0
        ;;
      23)
        FN_ORACLE_ENV
        FN_DB_Dir
        FN_Inc
      #  L_COMPLETE=0
        ;;
      24)
        FN_ORACLE_ENV
 
        FN_Inc
      #  L_COMPLETE=0
        ;;
      25)
        FN_ORACLE_ENV
        FN_Conc_Reqs
        FN_Inc
        L_COMPLETE=0
        ;;
      *)
        FN_Header ERROR
        exit 1
        ;;
      esac
  done

  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "$PG  completed at `date` \n"
  printf "${LN_BREAK}${LN_BREAK}\n"

}   ### End of FN_Main ###

# - - - - - - - - - - - -  Main - - - - - - - - - #
  export L_S_SID=${1:?"Missing the source sid"}
  export L_T_SID=${2:?"Missing the target sid"}

  PG=$(basename $0 .sh)
  TS=`date +%Y%m%d`

  export LN_BREAK="================================================================="

  export L_COMPLETE=1
  export L_ERROR=0
  export L_STEP=${3:-1}

  if FN_ValidENV $L_T_SID ; then
    FN_Main 2>&1 | tee -a $DBA/logs/${PG}_${L_S_SID}_${L_T_SID}_$(hostname)_$TS.log
  else
    printf "\n the $L_T_SID is invalid\n"
    export L_ERROR=1
  fi

  exit $L_ERROR
# - - - - - - - - - - - - - - - - - - - - - - - - #
