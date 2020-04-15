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
# 20203025 milbyr           fix issue creating d003 when u001 was already created #
# 20203026 milbyr           NFS fix : amended fstab entries and /export mnt pt    #
# 20204004 milbyr           added regex to snapshot_clone.                        #
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

 if L_OATAB_LN=$(grep "^${G_ENV_S}:" $L_OATAB); then
    export G_SNAP_WINDOW=$( echo ${L_OATAB_LN} |cut -d: -f14 )
    export G_DBSRV=$( echo ${L_OATAB_LN} |cut -d: -f3 )
    printf "\tThe snapshot keep window is ${G_SNAP_WINDOW} on dbTier ${G_DBSRV}\n"
 else
  printf "The environment (${G_ENV_S}) does not exist in $L_OATAB\n"
  exit 1
 fi

 if L_VGS=$(vgs -o name --noheading | grep ${G_ENV_S_UC} | sed -e "s/^[ ]+//" | tr -d "\n" | sed -e "s/^[ ]*//") ; then
   export L_VGS
   printf "\tThere are LVM volume group(s) (${L_VGS}) for this environment ($G_ENV_S)\n"

   if (echo ${L_VGS} | grep vg_db${G_ENV_S_UC} >/dev/null ); then
     printf "\tThere is a database volume group (vg_db${G_ENV_S_UC})\n"

     if L_TP=$(lvs vg_db${G_ENV_S_UC} -S "lv_attr=~[^t.*]" -o name --noheading |sed -e "s/[ ]*//g" ); then
       printf "\t\tThere is a corresponding thin_pool (${L_TP})\n"
     else
       printf "\t\tThere is NO corresponding database thin_pool for ${${G_ENV_S_UC}}\n"
       exit 1
     fi

   else
     printf "\tThere is NO database volume group (vg_db${G_ENV_S_UC})\n"
     exit 1
   fi   

   if (echo ${L_VGS} | grep vg_gp${G_ENV_S_UC} >/dev/null ); then
     printf "\tThere is a general volume group (vg_gp${G_ENV_S_UC})\n"

     if L_TP=$(lvs vg_gp${G_ENV_S_UC} -S "lv_attr=~[^t.*]" -o name --noheading) |sed -e "s/[ ]*//g" ; then
       printf "\t\tThere is a corresponding thin_pool (${L_TP})\n"
     else
       printf "\t\tThere is NO corresponding general purpose thin_pool for ${${G_ENV_S_UC}}\n"
       exit 1
     fi

   else
     printf "\tThere is NO general volume group (vg_gp${G_ENV_S_UC})\n"
     exit 1
   fi   

 else
   printf "\tThere are NO LVM volume group(s) that match ${G_ENV_S_UC} \n"
   exit 1
 fi

 # check that there are some snapshots available to allow this to progress
   #lvs -o vg_name,lv_name,origin,lv_descendants,lv_attr -S "lv_attr=~[^Vwi---.*]" --noheading | grep ${G_ENV_S_UC} | wc -l
   if [ $(lvs -o vg_name,lv_name,origin,lv_descendants,lv_attr -S "lv_attr=~[^Vwi---.*]" --noheading | grep ${G_ENV_S_UC} | wc -l) -lt 4 ]; then
     printf "\t There are NO snapshots available for to progress"
     exit 1
  fi

}   ### End of check_parameters ###



function FS_MNT_check
{
  FN_Header FS_MNT_check

  # check db mount points 
  printf "\t  -- dbTier --\n"
  for L_MNT in `df -h | grep ${G_ENV_S_LC} | awk '{print $6}' | sed -e "s/${G_ENV_S_LC}/${G_ENV_T_LC}/g"`
  do
    if [ -d $L_MNT ]; then
      printf "\tMOUNT POINT $L_MNT exists\n" 
    else
      printf "\tMOUNT POINT $L_MNT DOES NOT exists\n" 
      export G_ERROR=0
    fi

  done

  # check the appsTier mount points
  printf "\t  -- appsTier --\n"
  for L_MNT in `grep "^/appl${G_ENV_S_LC}" /etc/fstab | awk '{print $1}' | sed -e "s/${G_ENV_S_LC}/${G_ENV_T_LC}/g"`
  do
   if [ -d $L_MNT ]; then
      printf "\tMOUNT POINT $L_MNT exists\n"
    else
      printf "\tMOUNT POINT $L_MNT DOES NOT exists\n"
      export G_ERROR=0
    fi

  done

   ###   check the NFS export rpc bind mount point


}   ### End of FS_MNT_check ###



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


function snapshot_clone
{
  FN_Header snapshot_clone

  ##   This is the newest snapshot ##

  L_SS_TMSTMP=$( lvs -S "lv_attr=~Vwi---tz-k" --noheading -o name | grep ${G_ENV_S_UC} | grep -E "*_[0-9]*4" | awk -n YEAR=$(date +%Y)'{print substr($0,index($0, YEAR)) }' | sort -r | \
    awk  'BEGIN {str_prev=$1}
    { str_new=$1;
     if ( str_prev != str_new )
     {
      print str_prev;
      str_prev=str_new;
     }
    }
    END {print str_new}
  '  | grep -v "^$" | head -1 )

  L_TMP_MNT=/tmp/.lvm_$$
  ## have to mount the XFS volume before you can change the UUID ##
  mkdir ${L_TMP_MNT}

  printf "\t== Snapshot time stamp used:  ${L_SS_TMSTMP}\n"

  for L_VG_TYPE in db gp
  do
    L_VG=vg_${L_VG_TYPE}${G_ENV_S_UC}

    ## loop for all snapshots
    lvs -o origin,vg_name,lv_name,lv_size ${L_VG} | grep -v vtssupp | grep ${L_SS_TMSTMP} |sort | while read L_ORIGIN L_VG_NAME L_LV_NAME L_LV_SIZE
    do
      L_V_SZ=$(( $(echo ${L_LV_SIZE} | cut -d. -f1) / 4))
      printf "\t==  using a virtual size of ${L_V_SZ} (${L_LV_SIZE})\n"
          ##  -V|--virtualsize Size[m|UNIT]  ## do NOT use -L as this will crease a stand alone thin-pool and break everything ##

      ## lvcreate -s -kn -n -V${L_V_SZ:-4}G  ${L_ORIGIN}_${G_ENV_T_UC} ${L_VG_NAME}/${L_LV_NAME}

      lvcreate -s -kn -n ${L_ORIGIN}_${G_ENV_T_UC} ${L_VG_NAME}/${L_LV_NAME}
      lvchange -ay -Ky ${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}
      ## lvchange -kn     ${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}

      printf "\n"
      ls -al /dev/mapper/${L_VG_NAME}-${L_ORIGIN}_${G_ENV_T_UC}

      printf "\n"

      mount -o nouuid /dev/${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC} ${L_TMP_MNT}
      ## There is a problem with the RUN FS (fs1) still being mounted ## fatal error -- couldn't initialize XFS library
      ## wait 10   ## did not fix

      umount -f ${L_TMP_MNT}

## - investigation - ##

df -h | grep -i ${G_ENV_T_UC}
if [ $? -eq 0 ]; then
  L_E_FS=$(df -h | grep -i ${G_ENV_T_UC} | awk '{print $6}' )
  printf "\t== ERROR: umount -f ${L_E_FS}\n"
  umount -f ${L_E_FS}
fi
#umount -f $( df -h | grep -i ${G_ENV_T_UC} | awk '{print $6}' )

##- - - - - - - - - ##

      printf "\t== generating a new UUID for /dev/${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}\n"
      xfs_admin -U generate /dev/${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}
      printf "\t== new UUID\n"
      xfs_admin -u /dev/${L_VG_NAME}/${L_ORIGIN}_${G_ENV_T_UC}
      ## or xfs_admin -U generate /dev/mapper/${L_VG_NAME}-${L_ORIGIN}_${G_ENV_T_UC}
    done

  done

  rmdir ${L_TMP_MNT}

}   ### End of snapshot_clone ###


function snapshot_clone_status
{
 FN_Header snapshot_clone_status

  for L_VG_TYPE in db gp
  do
    L_VG=vg_${L_VG_TYPE}${G_ENV_S_UC}

    printf "\n\tnew snapshot status\n"
    ## loop for all snapshots
   ##lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-aotz--]" --noheading ${L_VG} | grep -v vtssupp | grep ${G_ENV_T_UC} | sort | while read L_VG_NAME L_LV_NAME

    lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-a-tz--]" --noheading ${L_VG} | grep -v vtssupp | grep ${G_ENV_T_UC} | sort | while read L_VG_NAME L_LV_NAME
    do
      #lvs -v ${L_VG_NAME}/${L_LV_NAME}_${G_ENV_T_UC} --noheading
      lvs -v ${L_VG_NAME}/${L_LV_NAME} --noheading
    done

    printf "\n\n\tnew device info (${L_VG_TYPE})\n"
    ## loop for all snapshots
    #lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-aotz--]" --noheading ${L_VG} | grep -v vtssupp | grep ${G_ENV_T_UC} | sort | while read L_VG_NAME L_LV_NAME

    lvs -o vg_name,lv_name -S "lv_attr=~[Vwi-a-tz--]" --noheading ${L_VG} | grep -v vtssupp | grep ${G_ENV_T_UC} | sort | while read L_VG_NAME L_LV_NAME
    do
      ##ls -al /dev/mapper/${L_VG_NAME}-${L_LV_NAME}_${G_ENV_T_UC}
      ls -al /dev/mapper/${L_VG_NAME}-${L_LV_NAME}
    done

  done
}   ### End of snapshot_clone_status ###


function  snapshot_clone_mount_fstab
{
  FN_Header snapshot_clone_mount_fstab

  L_FS=/etc/fstab

  if grep ${G_ENV_T_UC} ${L_FS} 2>&1 >/dev/null ; then
    printf "\t==  There are entries for ${G_ENV_T_UC} already in the ${L_FS}\n"
  else

    for FS in fs1 fs2 fs_ne csf custom
    do
      L_MNT=/export/${G_ENV_S_UC}${FS}_${G_ENV_T_UC}

      if [ -d ${L_MNT} ]; then
        printf "\t== ERROR: the filesystem  ${L_MNT} should not exist at this point\n"
        ls -ald ${L_MNT}
        printf "\n"
      else
        mkdir $L_MNT
        chown ${L_APPLUSER}:applmgr $L_MNT
      fi
    done

    printf "\t==  ADDING ${G_ENV_T_UC} entries to ${L_FS}\n"
    ( cat <<CATEOF
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/dev/mapper/vg_db${G_ENV_S_UC}-lv_${G_ENV_S_UC}data03_${G_ENV_T_UC}  /ora${G_ENV_T_LC}/apps_st/data03 xfs defaults 0 2
/dev/mapper/vg_gp${G_ENV_S_UC}-lv_${G_ENV_S_UC}data01_${G_ENV_T_UC}  /ora${G_ENV_T_LC}/apps_st/data01 xfs defaults 0 2
/dev/mapper/vg_gp${G_ENV_S_UC}-lv_${G_ENV_S_UC}data02_${G_ENV_T_UC}  /ora${G_ENV_T_LC}/apps_st/data02 xfs defaults 0 2
/dev/mapper/vg_gp${G_ENV_S_UC}-lv_${G_ENV_S_UC}fra_${G_ENV_T_UC}     /ora${G_ENV_T_LC}/apps_st/fra    xfs defaults 0 2
/dev/mapper/vg_gp${G_ENV_S_UC}-lv_${G_ENV_S_UC}tech_st_${G_ENV_T_UC} /ora${G_ENV_T_LC}/tech_st        xfs defaults 0 2
#
/dev/vg_gp${G_ENV_S_UC}/lv_${G_ENV_S_UC}fs1_${G_ENV_T_UC}    /export/${G_ENV_S_UC}fs1_${G_ENV_T_UC}    xfs defaults 0 2
/dev/vg_gp${G_ENV_S_UC}/lv_${G_ENV_S_UC}fs2_${G_ENV_T_UC}    /export/${G_ENV_S_UC}fs2_${G_ENV_T_UC}    xfs defaults 0 2
/dev/vg_gp${G_ENV_S_UC}/lv_${G_ENV_S_UC}fs_ne_${G_ENV_T_UC}  /export/${G_ENV_S_UC}fs_ne_${G_ENV_T_UC}  xfs defaults 0 2
/dev/vg_gp${G_ENV_S_UC}/lv_${G_ENV_S_UC}csf_${G_ENV_T_UC}    /export/${G_ENV_S_UC}csf_${G_ENV_T_UC}    xfs defaults 0 2
/dev/vg_gp${G_ENV_S_UC}/lv_${G_ENV_S_UC}custom_${G_ENV_T_UC} /export/${G_ENV_S_UC}custom_${G_ENV_T_UC} xfs defaults 0 2
#
/export/${G_ENV_S_UC}fs1_${G_ENV_T_UC}    /appl${G_ENV_T_LC}/fs1    none rbind 0 0
/export/${G_ENV_S_UC}fs2_${G_ENV_T_UC}    /appl${G_ENV_T_LC}/fs2    none rbind 0 0
/export/${G_ENV_S_UC}fs_ne_${G_ENV_T_UC}  /appl${G_ENV_T_LC}/fs_ne  none rbind 0 0
/export/${G_ENV_S_UC}csf_${G_ENV_T_UC}    /appl${G_ENV_T_LC}/csf    none rbind 0 0
/export/${G_ENV_S_UC}custom_${G_ENV_T_UC} /appl${G_ENV_T_LC}/custom none rbind 0 0
#
CATEOF


) >> ${L_FS}

  fi

   printf "\t==     details     ==\n\n"
   grep ${G_ENV_T_UC} ${L_FS}
   printf "\n\t==     ======     ==\n"

}   ### End of snapshot_clone_status ###


function snapshot_clone_mount
{
  FN_Header snapshot_clone_mount

  printf "\n\t  These are the expected file systems:\n"
  grep ${G_ENV_S_LC} /etc/fstab | awk '{print $2}' | egrep "ora${G_ENV_S_LC}|appl${G_ENV_S_LC}" | sed -e "s/${G_ENV_S_LC}/${G_ENV_T_LC}/"


  #  for FS in $(grep ${G_ENV_S_LC} /etc/fstab | awk '{print $2}' | egrep "ora${G_ENV_S_LC}|appl${G_ENV_S_LC}" | sed -e "s/${G_ENV_S_LC}/${G_ENV_T_LC}/")
  #  do
  #    mount ${FS}
  #  done

  mount -a

  printf "\t== these are the available file systems\n"
  df -h | grep -i ${G_ENV_S_LC}

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
  L_TAGS=$(lvs -S "lv_attr=~Vwi---tz-k" --noheading -o name | grep ${G_ENV_UC} | awk -n YEAR=$(date +%Y)'{print substr($0,index($0, YEAR)) }' | sort | \
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


function snapshot_chown
{
  FN_Header snapshot_chown
  L_LV_USE=${1:?"snapshot_chown: Missing the LV function (dbTier|appsTier)"}

  if [ "${L_LV_USE}" == "dbTier" ]; then
    L_OWNER=ora${G_ENV_T_LC} 

    for L_FS in $( df -h | grep ${L_OWNER} | awk '{print $6}' )
    do
      printf "\t  == chown -PR ${L_OWNER} ${L_FS} &\n"
      chown -PR ${L_OWNER} ${L_FS} &
    done
  else
    L_OWNER=appl${G_ENV_T_LC}

    for L_FS in $( df -h | grep {G_ENV_T_UC}  | awk '{print $6}' )
    do
      printf "\t  == chown -PR ${L_OWNER} ${L_FS} &\n"
      chown -PR ${L_OWNER} ${L_FS} &
    done
  fi

  printf "\t  == WAITING on the ${L_LV_USE} chown(s) to complete `date`\n"
  wait

}   ### End of snapshot_chown ###


function snapshot_nfs
{
   FN_Header snapshot_nfs

  if ( df -h | grep ${G_ENV_T_UC} 2>&1 >/dev/null ) ; then
    ( cat <<CATEOF
#
/export/${G_ENV_S_UC}fs1_${G_ENV_T_UC}    10.66.89.0/24(rw,insecure,no_subtree_check,async,no_root_squash) 10.66.90.0/24(rw,insecure,no_subtree_check,async,no_root_squash)
/export/${G_ENV_S_UC}fs2_${G_ENV_T_UC}    10.66.89.0/24(rw,insecure,no_subtree_check,async,no_root_squash) 10.66.90.0/24(rw,insecure,no_subtree_check,async,no_root_squash)
/export/${G_ENV_S_UC}fs_ne_${G_ENV_T_UC}  10.66.89.0/24(rw,insecure,no_subtree_check,async,no_root_squash) 10.66.90.0/24(rw,insecure,no_subtree_check,async,no_root_squash)
/export/${G_ENV_S_UC}csf_${G_ENV_T_UC}    10.66.89.0/24(rw,insecure,no_subtree_check,async,no_root_squash) 10.66.90.0/24(rw,insecure,no_subtree_check,async,no_root_squash)
/export/${G_ENV_S_UC}custom_${G_ENV_T_UC} 10.66.89.0/24(rw,insecure,no_subtree_check,async,no_root_squash) 10.66.90.0/24(rw,insecure,no_subtree_check,async,no_root_squash)
CATEOF
) >> /etc/exports

    printf "\t== the file systems are mounted under /export and will be automatically mounted on /mnt file system on the NFS client(s)\n"
    exportfs -r

    printf "\n\t=== The /etc/exports file has not been updated at this stage ===\n"
  else
    printf "\n\n\t === There are no ${L_APPLUSER} file systems ===\n"
  fi

}   ### End of snapshot_nfs ###


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
     #   db_env_prepare
        FS_MNT_check
        FN_Inc
      #  G_COMPLETE=0
        ;;
     3)
        snapshot_clone 
        FN_Inc
      #  G_COMPLETE=0
        ;;
     4)
        snapshot_clone_status
        FN_Inc
      #  G_COMPLETE=0
        ;;
     5) 
        snapshot_clone_mount_fstab
        FN_Inc
      #  G_COMPLETE=0
        ;;
     6) 
        snapshot_clone_mount
        FN_Inc
     #   G_COMPLETE=0
        ;;
     7)
        snapshot_chown dbTier
          ##   start EBS dbTier clone
        FN_Inc
      #  G_COMPLETE=0
        ;;

     8)
        snapshot_chown appsTier
        FN_Inc
      #  G_COMPLETE=0
        ;;
     9)
        ##   Fix the EBS appsTier NFS exports - generate a new UUID or add fsid to the /etc/exports ##
        snapshot_nfs 
          ##   if dbTier is completed sucessfully then start EBS appsTier clone
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

  if [ $# -lt 2 ]; then
   printf "Missing some paramters\n"
   printf "\n\nUSE:\n\t${PG}.sh  <EBS SOURCE environment> <EBS TARGET environment> [stage]\n"
   exit 1
  fi

  # source
  export G_ENV_S=${1:?"Missing the EBS SOURCE environment"}
  export G_ENV_S_LC=${G_ENV_S,,}
  export G_ENV_S_UC=${G_ENV_S^^}

  # target
  export G_ENV_T=${2:?"Missing the EBS TARGET environment"}
  export G_ENV_T_LC=${G_ENV_T,,}
  export G_ENV_T_UC=${G_ENV_T^^}

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
