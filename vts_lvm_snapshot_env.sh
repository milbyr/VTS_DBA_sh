#!/usr/bin/bash -x
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Robert Milby     20200317                    Velocity         #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
#                                                               #
# Function: reate LVM thin-pool snapshots                       #
# Parameters:                                                   #
#       ORACLE_SID                                              #
#       BACKUP_TYPE  HOT/COLD                                   #
#                                                               #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
# Modifications:                                                #
# YYYYMMDD      Who     Ver     description                     #
# 20200317 milbyr       1.0  Created                            #
# -------- ----------  ----  ---------------------------------  #
#                                                               #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#  setup the environment
.   $HOME/.bash_profile

   ## This assumes that the configuration has already been done.

function FN_Inc
{
  export G_STEP=$(($G_STEP + 1))
}   ### End of FN_Inc ###


function FN_Header
{
  printf "\n${LN_BREAK}\n"
  printf "= STEP ${G_STEP} : starting $@ `date`\n"
  printf "${LN_BREAK}\n"

}   ### End of FN_Header ##


function check_parameters {
 FN_Header check_parameters

 if L_OATAB_LN=$(grep "^${G_ENV}:" $L_OATAB); then
    export G_SNAP_WINDOW=$( echo ${L_OATAB_LN} |cut -d: -f14 )
    export G_DBSRV=$( echo ${L_OATAB_LN} |cut -d: -f3 )
    printf "\tThe snapshot keep window is ${G_SNAP_WINDOW} on dbTier ${G_DBSRV}\n"
 else
  printf "The environment (${G_ENV}) does not exist in $L_OATAB\n"
  exit 1
 fi

 if L_VGS=$(vgs -o name --noheading | grep ${G_ENV_UC} | sed -e "s/^[ ]+//" | tr -d "\n" | sed -e "s/^[ ]*//") ; then
   export L_VGS
   printf "\tThere are LVM volume group(s) (${L_VGS}) for this environment ($G_ENV)\n"

   if (echo ${L_VGS} | grep vg_db${G_ENV_UC} >/dev/null ); then
     printf "\tThere is a database volume group (vg_db${G_ENV_UC})\n"

     if L_TP=$(lvs vg_db${G_ENV_UC} -S "lv_attr=~[^t.*]" -o name --noheading |sed -e "s/[ ]*//g" ); then
       printf "\t\tThere is a corresponding thin_pool (${L_TP})\n"
     else
       printf "\t\tThere is NO corresponding database thin_pool for ${${G_ENV_UC}}\n"
       exit 1
     fi

   else
     printf "\tThere is NO database volume group (vg_db${G_ENV_UC})\n"
     exit 1
   fi   

   if (echo ${L_VGS} | grep vg_gp${G_ENV_UC} >/dev/null ); then
     printf "\tThere is a general volume group (vg_gp${G_ENV_UC})\n"

     if L_TP=$(lvs vg_gp${G_ENV_UC} -S "lv_attr=~[^t.*]" -o name --noheading) |sed -e "s/[ ]*//g" ; then
       printf "\t\tThere is a corresponding thin_pool (${L_TP})\n"
     else
       printf "\t\tThere is NO corresponding general purpose thin_pool for ${${G_ENV_UC}}\n"
       exit 1
     fi

   else
     printf "\tThere is NO general volume group (vg_gp${G_ENV_UC})\n"
     exit 1
   fi   

 else
   printf "\tThere are NO LVM volume group(s) that match ${G_ENV_UC} \n"
   exit 1
 fi
}   ### End of check_parameters ###



function snapshot_list
{
  FN_Header snapshot_list

  L_VG_TYPE=${1}

  if [ ${L_VG_TYPE} == "" ]; then
    printf "\n\tThis is the current status of ALL LVM logical volumes\n"
    lvs -a -S "lv_attr=~[^V.*]"
  else
    L_VG=vg_${L_VG_TYPE}${G_ENV_UC}
    printf "\n\tThis is the current status of LVM logical volumes for the ${L_VG} volume group\n"
    lvs -a ${L_VG} -S "lv_attr=~[^V.*]"
  fi

}   ### End of snapshot_list ###


function snapshot_create
{
  FN_Header snapshot_create

  L_VG_TYPE=${1:?"Missing the volume group type (gp|db)"}
  L_GROWTH=2
  L_VG=vg_${L_VG_TYPE}${G_ENV_UC}
 
  ## lvs -o vg_name,lv_name,size --noheadings -S "lv_attr=~[^V.*]"  ${L_VG} 
   
  lvs -o vg_name,lv_name,size --noheadings -S "origin= && segtype!=thin-pool"  ${L_VG} | while read VG LV LVSIZE
  do
    LVSIZE=`echo ${LVSIZE} | sed -e "s/g$//g" | sed -e "s/.00//g"`
    ## assume 20% reserve ##
    L_RESERVE=$((LVSIZE / 5 ))
    printf " Creating a snapshot of the LVM logical volume for $MNT (${VG}/${LV} size=${LVSIZE}G  reserve=${L_RESERVE})\n"
    if (lvcreate -s ${L_VG}/${LV} -n ${LV}_${G_TIMESTAMP} ); then
      printf "\n\tCREATED:  ${L_VG}/${LV} -n ${LV}_${G_TIMESTAMP}\n"
    else
     printf "\n\tThe creation of ${L_VG}/{LV} -n ${LV}_${G_TIMESTAMP} FAILED\n"
    fi
  done

}   ### End of snapshot_create ###


function snapshot_delete
{
  L_VG_NAME=${1:?"Missing the LVM VG name"}
  L_LV_NAME=${2:?"Missing the LVM LV snapshot name"}

  ## check that it is a snapshot
  ## check that it does not have any dependencies  - but this should have been done inthe calling function
  lvremove ${L_VG_NAME}/${L_LV_NAME}

}   ### End of snapshot_delete ###


function snapshot_delete_tag
{
  FN_Header snapshot_delete_tag

  L_KEEP=0
  L_DAYS=1

  ## check the snapshot dependency before deletion ##
  ## keep window - count or days ##
  
  printf "\n\tThe snapshot keep window is ${G_SNAP_WINDOW}\n"

  if (echo ${G_SNAP_WINDOW} | grep days ); then
    printf "\tThe appsoratab parameter is using \"days\" as the keep unit\n"
    L_KEEP=$(echo ${G_SNAP_WINDOW} | cut -d_ -f1)
    L_DAYS=0
  else
    printf "\tThe appsoratab parameter is using \"count\" as the keep unit, and NOT \"days\"\n"
    L_KEEP=${G_SNAP_WINDOW}
    L_DAYS=1
  fi

  printf "\n\n\tL_KEEP - ${L_KEEP}  L_DAYS - ${L_DAYS}\n\n"

  #L_TAGS=$(lvs -S "lv_attr=~Vwi---tz-k" --noheading -o name |cut -d_ -f3,4 | sort -r | \
  L_TAGS=$(lvs -S "lv_attr=~Vwi---tz-k" --noheading -o name |awk -n YEAR=$(date +%Y)'{print substr($0,index($0, YEAR)) }' | sort | \
    awk  'BEGIN {str_prev=$1}
    { str_new=$1;
     if ( str_prev != str_new )
     {
      print str_prev;
      str_prev=str_new;
     }
    }
    END {print str_new}'
  )

   L_TAGS_CNT=$(echo ${L_TAGS} |wc -w)
   # echo "L_TAGS_CNT  ${L_TAGS_CNT} : ${L_TAGS}"

  L_REMOVE=1
  while [ ${L_REMOVE} -le $((L_TAGS_CNT - ${L_KEEP})) ]
  do
    L_REMOVE_STR=$( echo ${L_TAGS} |cut -d" " -f${L_REMOVE} )
    printf "\tRemoving all snapshots with the >${L_REMOVE_STR}< tag\n"
    lvs -o vg_name,lv_name  --noheadings -S "lv_attr=~[^Vwi---.*]" | grep ${L_REMOVE_STR} | while read L_VG_NAME L_LV_NAME
    do
      snapshot_delete $L_VG_NAME $L_LV_NAME
    done
    L_REMOVE=$((L_REMOVE +1))
  done

}   ### End of snapshot_delete_tag ##


function FN_MAIN
{
  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "$PG  Ver $VERSION starting at `date` \n"
  printf "${LN_BREAK}${LN_BREAK}\n"

  while ( [ $G_COMPLETE -eq 1 ] && [ $G_ERROR -eq 0 ] )
  do
    case $G_STEP in
     1)
        check_parameters 
        FN_Inc
      #  G_COMPLETE=0
        ;;
     2)
        printf "\n\t## This will put the database into backup mode ##\n"
        ssh ora${G_ENV_LC}@${G_DBSRV} ". \$HOME/.bash_profile; ${DBA}/bin/vts_db_package.sh ${G_ENV} HOT BEGIN"
        FN_Inc
      #  G_COMPLETE=0
        ;;
     3)
        snapshot_create db
        snapshot_list db
        FN_Inc
      #  G_COMPLETE=0
        ;;
     4) 
        printf "\n\t## This will release the database from backup mode ##\n"
        ssh ora${G_ENV_LC}@${G_DBSRV} ". \$HOME/.bash_profile; ${DBA}/bin/vts_db_package.sh ${G_ENV} HOT END"
        FN_Inc
      #  G_COMPLETE=0
        ;;
     5)
        snapshot_create gp
        snapshot_list gp
        FN_Inc
      #  G_COMPLETE=0
        ;;

     6)
        snapshot_delete_tag
        FN_Inc
        G_COMPLETE=0
        ;;

    *)
        FN_Header ERROR
        G_ERROR=1
        G_COMPLETE=0
        ;;
    esac
  done

  printf "\n$LN_BREAK\n"
  printf "$PG  completed at `date` \n"
  printf "$LN_BREAK\n"
}   ### End of FN_MAIN ###


#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
  PG=$(basename $0 .sh)
  VERSION=1.0

  export PATH=/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aspx/bin:/opt/bacula/bin:/opt/puppetlabs/bin:.:/root/bin

  if [ $# -lt 1 ]; then
   printf "Missing some paramters\n"
   printf "\n\nUSE:\n\t$PG  <EBS environment> [stage]\n"
   exit 1
  fi

  export G_ENV=${1:?"Missing the EBS environment"}
  export G_ENV_LC=${G_ENV,,}
  export G_ENV_UC=${G_ENV^^}

  export G_STEP=${2:-1}

  LN_BREAK="================================================================="

  export DBA=/export/vtssupp/VTS
  export L_OATAB=${DBA}/etc/appsoratab

  export G_DAY=$(date +'%Y%m%d')

  export G_TIMESTAMP=$(date +'%Y%m%d_%H%M')
  export LOG_FN=$DBA/logs/${PG}.log.${G_TIMESTAMP}
  export DB_BKUP_SH=${DBA}/bin/vts_db_package.sh

  export G_COMPLETE=1
  export G_ERROR=0
  export G_VERBOSE=1

  FN_MAIN 2>&1 | tee ${LOG_FN}
# - - - - - - - - - - - - - - - - - - end - - - - - - - - - - - - - - - - - - - -
