#!/usr/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Robert Milby     20200319                    Velocity         #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
#                                                               #
# Function: Create LVM thin-pool snapshot clone                 #
# Parameters:                                                   #
#       ORACLE_SID                                              #
#                                                               #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
# Modifications:                                                #
# YYYYMMDD      Who     Ver     description                     #
# 20200319 milbyr       1.0  Created                            #
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


function check_parameters 
{
 FN_Header check_parameters

 if L_OATAB_LN=$(grep "^${G_ENV}:" $L_OATAB); then
    export G_SNAP_WINDOW=$( echo ${L_OATAB_LN} |cut -d: -f14 )
    export G_DBSRV=$( echo ${L_OATAB_LN} |cut -d: -f3 )
    printf "\tThe snapshot keep window is ${G_SNAP_WINDOW} on dbTier ${G_DBSRV}\n"
 else
  printf "The environment (${G_ENV}) does not exist in $L_OATAB\n"
  exit 1
 fi

 # check that there are some snapshots available to allow this to progress
   #lvs -o vg_name,lv_name,origin,lv_descendants,lv_attr -S "lv_attr=~[^Vwi---.*]" --noheading | grep ${G_ENV_S_UC} | wc -l
   ##if [ $(lvs -o vg_name,lv_name,origin,lv_descendants,lv_attr -S "lv_attr=~[^Vwi---.*]" --noheading | grep ${G_ENV_UC} | wc -l) -lt 4 ]; then
   if [ $(lvs -o vg_name,lv_name,origin,lv_descendants,lv_attr --noheading | grep ${G_ENV_UC} | wc -l) -lt 4 ]; then
     printf "\t There are NO snapshots available for to progress\n"
     exit 1
  fi

}   ### End of check_parameters ###


function FN_EXPORTS_remove_env
{
  FN_Header FN_EXPORTS_remove_env

  L_E_F=/etc/exports
  L_T_E_F=/tmp/exports.$$

  cp $L_E_F $L_T_E_F
  if [ $? -eq 0 ]; then
    printf "\t== The existing $L_E_F has been copied to $L_T_E_F\n"
    cat ${L_T_E_F}  | grep -vi ${G_ENV} > ${L_E_F}
    ## rm ${L_T_E_F}
  else
    printf "\t== ERROR: The existing $L_E_F has NOT been copied to $L_T_E_F\n"
    export G_ERROR=1
  fi

}   ### End of FN_EXPORTS_remove_env ###


function FN_remove_env_export_mntpts
{
  FN_Header FN_remove_env_export_mntpts

  for MNT_PT in $(ls -d1 /export/*${G_ENV^^} )
  do
    umount -f  $MNT_PT
    rmdir $MNT_PT
    if [ $? -eq 0 ]; then
      printf "\t== The mount point $MNT_PT has been removed \n"
    else
      printf "\t== ERROR: The mount point $MNT_PT has NOT been removed \n"
      # export G_ERROR=1
    fi
  done
}   ### End of FN_remove_env_export_mntpts ###



function FN_NFS_destroy
{
  FN_Header FN_NFS_destroy

  FN_EXPORTS_remove_env
  exportfs -r

  for NFS in $( df -h | grep -E "appld003|D003"  |awk '{print $6}' )
  do 
    printf "\t==  umount -f $NFS\n"
    umount -f $NFS
  done

  FN_remove_env_export_mntpts
}   ### End of FN_NFS_destroy ###


function FN_FSTAB_remove_env
{
  L_FS=/etc/fstab
  L_T_FS=/tmp/fstab.$$

  cp $L_FS $L_T_FS
  if [ $? -eq 0 ]; then
    printf "\t== The existing $L_FS has been copied to $L_T_FS\n"
    cat ${L_T_FS}  | grep -vi ${G_ENV} > ${L_FS}
    ## rm ${L_T_FS}
  else
    printf "\t== ERROR: The existing $L_FS has NOT been copied to $L_T_FS\n"
    export G_ERROR=1
  fi

}   ### End of FN_FSTAB_remove_env ###


function FN_FS_UNMOUNT
{
  FN_Header FN_FS_UNMOUNT

  printf "\tCreating a backup of the /etcfstab to $DBA/logs\n\n"
  cp /etc/fstab ${DBA}/logs/${PG}_fstab.${G_TIMESTAMP}

  L_PS_CNT=$( ps -ef | egrep "${G_ENV}|${G_ENV_LC}|${G_ENV_UC}" | grep -v grep | grep -v ${PG} | grep -v vts_ebs_env_destroy.sh | wc -l )

  if [ $L_PS_CNT -eq 0 ]; then
    printf "\t There are no running processes that match ${G_ENV}|${G_ENV_LC}|${G_ENV_UC}\n"
  else
    printf "\t\tERROR:  There are ${L_PS_CNT} proceses running for ${G_ENV_LC}\n\n"
    ps -ef | egrep "${G_ENV}|${G_ENV_LC}|${G_ENV_UC}" | grep -v grep | grep -v ${PG}
    export G_ERROR=0
    exit 1
  fi

  printf "\t  processing mounted file systems\n"
  for L_MNT in `df -h | egrep "${G_ENV}|${G_ENV_LC}|${G_ENV_UC}" | grep -v "/export/" | awk '{print $6}' `
  do
  
    printf "\t== UNMOUNTING :${L_MNT}\n"
    fuser ${L_MNT}
    umount -f ${L_MNT}
    L_G_STR=$(echo ${L_MNT} | awk '{ gsub("/","\\/"); print }' )

    if [ -d $L_MNT ]; then
      printf "\tMOUNT POINT $L_MNT exists\n" 
      # not removing for future use
    else
      printf "\tMOUNT POINT $L_MNT DOES NOT exists\n" 
    fi
  done

  FN_FSTAB_remove_env

}   ### End of FN_FS_UNMOUNT ###



function snapshot_list
{
  FN_Header snapshot_list

  L_VG_TYPE=${1}

  if [ "${L_VG_TYPE}" == "" ]; then
    printf "\n\tThis is the current status of ${G_ENV} LVM logical volumes\n"
    #lvs -a -S "lv_attr=~[^V.*]"
    lvs -a | egrep "${G_ENV}|${G_ENV_LC}|${G_ENV_UC}"
  else
    L_VG=vg_${L_VG_TYPE}${G_ENV_UC}
    printf "\n\tThis is the current status of LVM logical volumes for the ${L_VG} volume group\n"
    lvs -a ${L_VG} -S "lv_attr=~[^V.*]"
  fi

}   ### End of snapshot_list ###


function snapshot_clone
{
  FN_Header snapshot_clone

  for L_VG_TYPE in db gp
  do
    L_VG=vg_${L_VG_TYPE}${G_ENV_S_UC}

    ## loop for all snapshots
    lvs -o origin,vg_name,lv_name ${L_VG} | grep -v vtssupp | grep $(date +%Y%m%d) |sort | while read L_ORIGIN L_VG_NAME L_LV_NAME
    do
      lvcreate -s -kn -n ${L_ORIGIN}_${G_ENV_T_UC} ${L_VG_NAME}/${L_LV_NAME}
      lvchange -ay -Ky ${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}
      ## lvchange -kn     ${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}
      ls -al /dev/mapper/${L_VG_NAME}-${L_ORIGIN}_${G_ENV_T_UC}
      xfs_admin -U generate /dev/mapper/${L_VG_NAME}-${L_ORIGIN}_${G_ENV_T_UC}
      ## or xfs_admin -U generate /dev/${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}
    done

  done

}   ### End of snapshot_clone ###


function snapshot_clone_status
{
 FN_Header snapshot_clone_status

  for L_VG_TYPE in db gp
  do
    L_VG=vg_${L_VG_TYPE}${G_ENV_S_UC}

    printf "\n\tnew snapshot status\n"
    ## loop for all snapshots
    lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-aotz--]" --noheading ${L_VG} | grep -v vtssupp | sort | while read L_VG_NAME L_LV_NAME
    do
      lvs -a ${L_VG_NAME}/${L_LV_NAME}_${G_ENV_T_UC} --noheading
    done

    printf "\n\n\tnew device info (${L_VG_TYPE})\n"
    ## loop for all snapshots
    lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-aotz--]" --noheading ${L_VG} | grep -v vtssupp | sort | while read L_VG_NAME L_LV_NAME
    do
      ls -al /dev/mapper/${L_VG_NAME}-${L_LV_NAME}_${G_ENV_T_UC}
    done
  done
}   ### End of snapshot_clone_status ###


function snapshot_clone_mount
{
 FN_Header snapshot_clone_mount

  #for L_VG_TYPE in db gp
  for L_VG_TYPE in db
  do
    L_VG=vg_${L_VG_TYPE}${G_ENV_S_UC}

    ## loop for all snapshots
    lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-a-tz--]" --noheading ${L_VG} | grep -v vtssupp |grep ${G_ENV_T_UC} | sort | while read L_VG_NAME L_LV_NAME
    do
     L_ORIGIN=${L_LV_NAME/_${G_ENV_T_UC}}
      echo "df -h  | grep ${L_VG_NAME}-${L_ORIGIN}"
      df -h  | grep ${L_VG_NAME}-${L_ORIGIN}
      echo mount /dev/mapper/${L_VG_NAME}-${L_LV_NAME}
#_${G_ENV_T_UC}
    done
  done
}   ### End of snapshot_clone_mount ###


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
  FN_Header snapshot_delete

  L_VG_NAME=${1:?"Missing the LVM VG name"}
  L_LV_NAME=${2:?"Missing the LVM LV snapshot name"}

  ## check that it is a snapshot
  ## check that it does not have any dependencies  - but this should have been done inthe calling function

  lvremove -y ${L_VG_NAME}/${L_LV_NAME}

  if [ $? -ne 0 ]; then
    printf "\n\tERROR: snapshot_delete:  ${L_VG_NAME}/${L_LV_NAME} failed to be removed\n\n"
  fi

}   ### End of snapshot_delete ###


function snapshot_destroy_tag
{
  FN_Header snapshot_destroy_tag

   #########      $( lvs -a -o vg_name,lv_name|grep U001 |awk '{print "lvremove "$1"/"$2}')   ###############

  lvs -a -o vg_name,lv_name|grep ${G_ENV_UC} |awk '{print $1" "$2}' | while read L_VG L_LV
  do
    ## check the snapshot dependency before deletion ##

    snapshot_delete ${L_VG} ${L_LV}

    ## lvremove $(lvm_ss_check_20200204.py | grep 20200317_110605 | sed -e "s/lv/vg_gpEWPRD\/lv/")
  done
}   ### End of snapshot_destroy_tag ###


function FN_MAIN
{
  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "${PG}.sh  Ver $VERSION starting at `date` \n"
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
        FN_NFS_destroy
        FN_Inc
     #   G_COMPLETE=0
        ;;
     3)
        FN_FS_UNMOUNT
        FN_Inc
     #   G_COMPLETE=0
        ;;
     4)
        snapshot_list
        FN_Inc
     #   G_COMPLETE=0
        ;;
     5) 
        snapshot_destroy_tag
        FN_Inc
        G_COMPLETE=0
        ;;
     6)
        snapshot_list
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

  printf "\n${LN_BREAK}${LN_BREAK}\n"
  printf "$PG  completed at `date` \n"
  printf "${LN_BREAK}${LN_BREAK}\n"
}   ### End of FN_MAIN ###


#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
  PG=$(basename $0 .sh)
  VERSION=1.0

  export PATH=/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aspx/bin:/opt/bacula/bin:/opt/puppetlabs/bin:.:/root/bin

  if [ $# -lt 1 ]; then
   printf "Missing some paramters\n"
   printf "\n\nUSE:\n\t${PG}.sh  <EBS TARGET environment> [stage]\n"
   exit 1
  fi

  export G_ENV=${1:?"Missing the EBS TARGET environment"}
  export G_ENV_LC=${G_ENV,,}
  export G_ENV_UC=${G_ENV^^}

  export G_STEP=${3:-1}

  LN_BREAK="================================================================="

  export DBA=/export/vtssupp/VTS
  export L_OATAB=${DBA}/etc/appsoratab

  export G_DAY=$(date +'%Y%m%d')

  export G_TIMESTAMP=$(date +'%Y%m%d_%H%M')
  export LOG_FN=$DBA/logs/${PG}.log.${G_TIMESTAMP}

  export G_COMPLETE=1
  export G_ERROR=0
  export G_VERBOSE=1

  FN_MAIN 2>&1 | tee ${LOG_FN}
# - - - - - - - - - - - - - - - - - - end - - - - - - - - - - - - - - - - - - - -
