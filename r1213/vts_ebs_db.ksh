#!/usr/bin/ksh
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# R. Milby	20111019			                                                  #
#						                                                  #
# To recover a hot backup and clone		                                                  #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# History				                                                          #
# converted to EMSS R12				                                                  #
#                                                                                                 #
# 	When		Who	What                                                              #
#	=====================================================================                     #
#	20111027	MD	Altered FN_ALF to check for existance of file                     #
#	20120203	RM	Altered FN_CR_CTL_Script to remove standby info                   #
#	20120207	RM	Added the FN_Conc_Reqs function to put CR on hold		  #
#	20120207	RM	Added the FN_lsnr_ifile function to  create the public listener	  #
#       20120308        RM	Added the FN_PASSWORD_GEN to the FN_Open_DB function		  #
#       20120515        RM	Modified FN_Conc_Reqs to allow house keeping conc. programs.	  #
#       20120530        RM	Added botemp tempfiles to the cr_tmp.sql script.	    	  #
#       20120628        RM	Fixed ish_user_ to ishc_user_ typo.	    	  	 	  #
#       20120718        RM	Created a new  FN_InitOra to fix /usr/tmp.	  		  #
#       20130402        RM	Changed inst directory to diag				  	  #
#       20130403        RM	Added the EMSS utl_file_dir entries				  #
#       20130409        RM      global change to db directories.				  #
#       20130529        RM	Added etltemp tempfiles to the cr_tmp.sql script.	    	  #
#       20130718        RM	Modified FN_ALF to uncompress all ALFs				  #
#       20130718        RM	Modified FN_Recover_DB to accept multiple ALFs			  #
#       20170130        RM	Added the streams_pool_size init.ora parameter			  #
#       20170203        RM      Added the COST Manager (33733) to the excluded conc. req. hold flag     #
#                                                                                       	  #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
#
#
export DBA=/export/vtssupp/VTS
export L_VERBOSE=1
export G_ENV=1

if [ -f $DBA/bin/vit_utils.ksh ]; then
.   $DBA/bin/vit_utils.ksh
else
  echo "$DBA/bin/vit_utils.ksh is missing"
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
control_files  = /${L_ORAUSER}/db/apps_st/data02/cntrl01.dbf,/${L_ORAUSER}/db/apps_st/data03/cntrl02.dbf,/${L_ORAUSER}/db/apps_st/data02/cntrl03.dbf
db_files                        = 500         # Max. no. of database files
undo_management=AUTO                   # Required 11i setting
undo_tablespace=APPS_UNDOTS1     # Required 11i setting
memory_max_target               = 3g
memory_target                   = 3g
db_block_size                   = 8192
compatible                      = 11.2.0
diagnostic_dest                 = /${L_ORAUSER}
EOF
) > $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora

}   ### End of FN_InitOra_old ###


function FN_InitOra
{
  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )

  mv $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora.autoconfig
  cat $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora.autoconfig | sed -e "s/utl_file_dir = \/usr\/tmp,/utl_file_dir = /" | sed "s/sga_target               = 1G/sga_target               =4G/" | sed "s/compatible                      = 11.2.0/compatible                      = 11.2.0.4/"> $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora
  echo "utl_file_dir = /${L_APPLUSER}/csf/temp, /${L_APPLUSER}/csf/log, /${L_APPLUSER}/csf/out, /usr/tmp" >> $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora
  echo "streams_pool_size               = 192M" >> $L_ORACLE_HOME/dbs/init${L_ORACLESID}.ora
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


function FN_Backup_link
{
  ### This is only requierd on Newcastle server as the backup info is created in Edinburgh  and copied accross.
 
  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  FN_Debug "Linking the backup_archive directory"
set -x

  if [ $(hostname) = "vncl1lbsx04" ] &&  [ -d  /${L_ORAUSER}/db/diag/LBPD01_vedi1lbsx04/backup_archive ]; then
    rm -f /${L_ORAUSER}/db//diag/${L_ORACLESID}_vncl1lbsx04/backup
    rm -rf /${L_ORAUSER}/db/diag/${L_ORACLESID}_vncl1lbsx04/backup_archive
    rm -rf /${L_ORAUSER}/db/diag/LBPD01_vncl1lbsx04
    ln -s /${L_ORAUSER}/db/diag/LBPD01_vedi1lbsx04/ /${L_ORAUSER}/db/diag/LBPD01_vncl1lbsx04/
  fi

  if [ -d /${L_ORAUSER}/db/diag/${L_S_SID}_$(hostname)/backup_archive/backup_`TZ=EST+24 date +%Y%m%d` ]; then
    FN_Print "FN_Backup_link: The latest backup bundle is available"
  else
    FN_Error "FN_Backup_link: The latest backup bundle is NOT available (/${L_ORAUSER}/db/diag/${L_S_SID}_$(hostname)/backup_archive/backup_`TZ=EST+24 date +%Y%m%d`"
    export L_ERROR=1
  fi

}  ### End of FN_Backup_link ###

 
function FN_Sym_Links
{

  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`

  #  move the existing admin directory
  FN_Debug "Moving the database admin directory"
##  mv /ora$L_LCORACLESID/inst/admin/${L_S_SID}_${L_DBSRV} /ora$L_LCORACLESID/inst/admin/${L_ORACLESID}_${L_DBSRV}
##  ln -s /ora$L_LCORACLESID/inst/admin/${L_ORACLESID}_${L_DBSRV} $(FN_ORACLE_HOME ${L_ORACLESID)/admin/${L_ORACLESID}_${L_DBSRV}

  rm $(FN_ORACLE_HOME ${L_ORACLESID})/admin/${L_S_SID}_${L_DBSRV}
  rm  $(FN_ORACLE_HOME ${L_ORACLESID})/admin/${L_ORACLESID}_${L_DBSRV}
  mkdir  $(FN_ORACLE_HOME ${L_ORACLESID})/admin/${L_ORACLESID}_${L_DBSRV}

  ## milbyr 20130317 perl upgrade fix ##
  FN_Debug "FIX: perl 5.10.0 and 5.8.3"
  ln -s $(FN_ORACLE_HOME ${L_ORACLESID})/perl/lib/5.10.0 $(FN_ORACLE_HOME ${L_ORACLESID})/perl/lib/5.8.3

  ####find /ora$L_LCORACLESID/product -type l ! -user ora$L_LCORACLESID -ls 2>/dev/null|awk '{print $11" "$13}'|while read L_LINK L_FN

  find /ora$L_LCORACLESID/db/tech_st -type l -ls 2>/dev/null| grep "/ora${LC_S_SID}/" |awk '{print $11" "$13}'|while read L_LINK L_FN
  do
    N_FN=`echo $L_FN | sed -e "s/ora${LC_S_SID}/ora$L_LCORACLESID/"`
    if [ -f $N_FN ]; then
      FN_Debug "rm $L_LINK"
      rm -f $L_LINK
      ln -s $N_FN $L_LINK
    else
      FN_Debug "ERROR: file $N_FN does not exist or local link"
    fi
  done
}


function FN_ora_env 
{
  # DEV1_v06ss102.env
  # cat DEV1_v06ss102.env | sed "s/DEV1/DEV4/g" | sed "s/oradev1/oradev4/g"

  L_ORACLE_HOME=$(FN_ORACLE_HOME $L_ORACLESID )
  LC_S_SID=`echo "$L_S_SID" | tr "[:upper:]" "[:lower:]"`
  LC_T_SID=`echo "$L_ORACLESID" | tr "[:upper:]" "[:lower:]"`

  cat $L_ORACLE_HOME/${L_S_SID}_${L_DBSRV}.env | sed "s/${L_S_SID}/${L_ORACLESID}/g" | sed "s/ora${LC_S_SID}/ora${LC_T_SID}/g" > $L_ORACLE_HOME/${L_ORACLESID}_${L_DBSRV}.env

}


function FN_backup_dir
{
 if [ -d /${L_ORAUSER}/db/diag/LBPD01_${L_DBSRV}/backup_archive ]; then
  l_dir=`ls -1dtr /${L_ORAUSER}/db/diag/LBPD01_${L_DBSRV}/backup_archive/backup_*|tail -1`
  #FN_Debug "FN_backup_dir: l_dir is $l_dir"
  echo "$l_dir"
 else
  echo "FN_backup_dir: /${L_ORAUSER}/db/diag/${L_ORACLESID}_${L_DBSRV}/backup_archive does NOT exist"
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
  tail +$S_LN $FN | head -n $ROWS| grep -v "^$" | grep -v "^--" | sed "s/\/orapd01\//\/$L_ORAUSER\//" | sed -e "s/\"//g"| sed "s/\/$L_S_SID\//\/${L_ORACLESID}\//g" | sed "s/DATABASE $L_S_SID NORESETLOGS FORCE LOGGING [N]*[O]*ARCHIVELOG/set DATABASE ${L_ORACLESID} RESETLOGS FORCE LOGGING NOARCHIVELOG/" >$L_BKUP_DIR/cr_ctl.sql
set +x
}


function FN_CR_TMP_Script
{
  export L_BKUP_DIR=$(FN_backup_dir)
 ( cat <<EOF

ALTER TABLESPACE TEMP1
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp03.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 5G;

ALTER TABLESPACE TEMP2
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp01.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 5G;

ALTER TABLESPACE TEMP1
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp04.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 10G;

ALTER TABLESPACE TEMP2
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp022.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 5G;

ALTER TABLESPACE TEMP2
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp023.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 10G;

ALTER TABLESPACE TEMP1
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp012.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 10G;

ALTER TABLESPACE TEMP2
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp024.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 10G;

ALTER TABLESPACE TEMP1
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp05.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 2G;

ALTER TABLESPACE TEMP1
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp025.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 3G;

ALTER TABLESPACE TEMP1
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp06.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 10G;

ALTER TABLESPACE TEMP2
ADD TEMPFILE '/${L_ORAUSER}/db/apps_st/data03/temp07.dbf'
SIZE 100M REUSE AUTOEXTEND ON NEXT 100m  MAXSIZE 10G;
EOF
) >$L_BKUP_DIR/cr_tmp.sql 2>&1

#echo  "FN_CR_TMP_Script"
}


function FN_ORACLE_ENV
{
  export ORACLE_HOME=$L_ORACLEHOME

# todo - check G_ENV to see if the env file has already ben run #

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
##  .   $HOME/.profile
set -x
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
##   .  $HOME/.profile

  export L_BKUP_DIR=$(FN_backup_dir)
  ###### 20130718 milbyr L_ALF=`ls -1tr $L_BKUP_DIR/*arc  |tail -1`
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
  L_APEX_PORT=`expr 8100 \+ $L_PORT`

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

## FN_ORACLE_ENV

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
set -x
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
              fn_db_ans "3"
            ## Target System DATA_TOP Directory 1 : /oradev4/db/apps_st/data02
              fn_db_ans "/${L_ORAUSER}/db/apps_st/data01"
            ## Target System DATA_TOP Directory 2 : /oradev4/db/apps_st/data03
              fn_db_ans "/${L_ORAUSER}/db/apps_st/data02"
            ## Target System DATA_TOP Directory 3 : /oradev4/db/apps_st/data03
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
##  .   $HOME/.profile
##  . $ORACLE_HOME/${L_ORACLESID}_${L_DBSRV}.env

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
set -x
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
  ##FN_ORACLE_ENV

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


  if [ $(hostname) = "vncl1lbsx04" ]; then
   HOST_STR="vncl1lbsx04.ladbrokescoral.com"
  else
   HOST_STR="vedi1lbsx04.ladbrokescoral.com"
  fi

}


function FN_lsnr_ifile 
{
  ##FN_ORACLE_ENV

export L_TNS_PORT=`expr 1621 \+ $L_PORT`
export L_APEX_PORT=`expr 1421 \+ $L_PORT`

 #L_DOMAIN=`awk '/domain/ {print $2}' /etc/resolv.conf`
 #HOST_STR=$(hostname).${L_DOMAIN}

 if [ $(hostname) = "vncl1lbsx04" ]; then
  HOST_STR="vncl1lbsx04.ladbrokescoral.com"
 else
  HOST_STR="vedi1lbsx04.ladbrokescoral.com"
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

## milbyr 20150610 - APEX install ##

( cat <<EOFCAT
${L_ORACLESID}_APEX =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${HOST_STR})(PORT = ${L_APEX_PORT}))
    )
  )

  )

SID_LIST_${L_ORACLESID}_APEX =
  (SID_LIST =
    (SID_DESC =
      (ORACLE_HOME= $(FN_ORACLE_HOME $L_ORACLESID ))
      (SID_NAME = ${L_ORACLESID})
    )
  )

STARTUP_WAIT_TIME_${L_ORACLESID}_APEX = 0
CONNECT_TIMEOUT_${L_ORACLESID}_APEX = 10
TRACE_LEVEL_${L_ORACLESID}_APEX = OFF

LOG_DIRECTORY_${L_ORACLESID}_APEX = ${L_ORACLEHOME}/network/admin/log
LOG_FILE_${L_ORACLESID}_APEX = listener
TRACE_DIRECTORY_${L_ORACLESID}_APEX = ${L_ORACLEHOME}/network/admin/trace
TRACE_FILE_${L_ORACLESID}_APEX = listener
ADMIN_RESTRICTIONS_${L_ORACLESID}_APEX = OFF
SUBSCRIBE_FOR_NODE_DOWN_EVENT_${L_ORACLESID}_APEX = OFF
EOFCAT
) >> ${L_ORACLEHOME}/network/admin/${L_DBCONTEXT_NAME}/listener_ifile.ora

# start the public listener
#${L_ORACLEHOME}/bin/lsnrctl start ${L_ORACLESID}_PUBLIC

#  check the status of the public listener
#${L_ORACLEHOME}/bin/lsnrctl status ${L_ORACLESID}_PUBLIC

# start the APEX listener
#${L_ORACLEHOME}/bin/lsnrctl start ${L_ORACLESID}_APEX

#  check the status of the APEX listener
#${L_ORACLEHOME}/bin/lsnrctl status ${L_ORACLESID}_APEX

}


function    sql_dir_txt 
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

prompt 'create or replace directory XXLGT_OUTBOUND as /interfaces/${L_S_SID}/outbound'
create or replace directory XXLGT_OUTBOUND as '/interfaces/${L_S_SID}/outbound';

prompt 'create or replace directory ORACLE_OCM_CONFIG_DIR as /${L_ORAUSER}/db/tech_st/11.2.0/ccr/state'
create or replace directory ORACLE_OCM_CONFIG_DIR as '/${L_ORAUSER}/db/tech_st/11.2.0/ccr/state';

prompt 'create or replace directory CSR_XML_TOP as /${L_APPLUSER}/apps/apps_st/appl/csr/12.0.0/patch/115/xml'
create or replace directory CSR_XML_TOP as '/${L_APPLUSER}/apps/apps_st/appl/csr/12.0.0/patch/115/xml';

prompt 'create or replace directory DATA_PUMP_DIR as /${L_ORAUSER}/admin/LBUA01/dpdump/'
create or replace directory DATA_PUMP_DIR as '/${L_ORAUSER}/admin/LBUA01/dpdump/';

prompt 'create or replace directory APPS_DATA_FILE_DIR as /${L_ORAUSER}/db/tech_st/11.2.0/appsutil/outbound/${L_T_SID}_$(hostname)'
create or replace directory APPS_DATA_FILE_DIR as '/${L_ORAUSER}/db/tech_st/11.2.0/appsutil/outbound/${L_T_SID}_$(hostname)';

GRANT READ,WRITE ON DIRECTORY XXLGT_OUTBOUND to apps,xxlgt,xxlb;

    -- ## milbyr 20130409 ##
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
    prompt 'Dropping the source  ops\${L_APPLUSER} account';
    drop user ops\${L_APPLUSER} cascade;

    whenever sqlerror exit FAILURE;
    prompt 'Creating the OPS\${L_APPLUSER} user account';
    create user ops\${L_APPLUSER}
    identified externally
    temporary tablespace temp
    quota unlimited on APPS_TS_TX_DATA
    default tablespace APPS_TS_TX_DATA;

    grant create session to ops\${L_APPLUSER};

    grant create table to ops\${L_APPLUSER};

EOF
  export L_ERROR=$?
}   ### End of FN_user_ops ###


function FN_user_reset_db_users
{
  sqlplus  -s / as sysdba <<SQLEOF


SQLEOF
  export L_ERROR=$?
}   ### End of FN_user_reset_db_users ###

#
#replaced by function above which resets all passwords in one function
# requested by Y.Thanki (Nr-12018429)
#
#function FN_user_xxlcc
#{
#  sqlplus  -s / as sysdba <<SQLEOF
#
#  prompt alter user XXLCC identified by custom_${L_ORACLESID};
#  alter user xxlcc identified by custom_${L_ORACLESID};
#
#SQLEOF
#  export L_ERROR=$?
#}   ### End of FN_user_xxlcc ###
#

function FN_Conc_Reqs
{
  ##FN_ORACLE_ENV
  L_PASSWD=$(FN_GetAPPSPassword $L_S_SID)

    sqlplus -s /nolog <<EOF
      connect apps/${L_PASSWD}

      whenever sqlerror exit FAILURE
-- milbyr 20120629 Nr-12022424 --      prompt Removing the completed concurrent requests...
-- milbyr 20120629 Nr-12022424 --
-- milbyr 20120629 Nr-12022424 --      delete from fnd_concurrent_requests
-- milbyr 20120629 Nr-12022424 --      where phase_code = 'C';
  
      prompt Removing the running concurrent requests...
      delete from fnd_concurrent_requests
      where phase_code = 'R';
--        or CONCURRENT_PROGRAM_ID = 38121;

-- FNDGSCST 38121 Gather Schema Statistics

      prompt All remaining concurrent requests on hold...
      update fnd_concurrent_requests
      set hold_flag = 'Y'
      where phase_code = 'P'
        and concurrent_program_id NOT in (38121, 41993, 43593, 42852, 31659, 36888, 46799, 46798);

-- CONCURRENT_PROGRAM_ID USER_CONCURRENT_PROGRAM_NAME
-- --------------------- ------------------------------------------------------------
--                 41993 Purge Logs and Closed System Alerts
--                 46798 Workflow Agent Activity Statistics Concurrent Program
--                 43593 Workflow Control Queue Cleanup
--                  42852 OAM Applications Dashboard Collection
--                  31659 Report Set
--                  36888 Workflow Background Process
--                  46799 Workflow Mailer Statistics Concurrent Program

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
#        FN_tns_ifile
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
