#!/usr/bin/bash
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# R. Milby      20141205                                                                          #
#                                                                                                 #
# To create the required users accounts and mount points for EBS R12.2                            #
#= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =#
# History                                                                                         #
# converted to EMSS R12.2                                                                         #
#                                                                                                 #
# When     Who      What                                                                          #
# =====================================================================                           #
# 20190617 milbyr   Migrated to NCL.                                                              #
# 20190618 milbyr   Completed testing on U002 (NCL).                                              #
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


function FN_appsoratab
{
  FN_Header FN_appsoratab

  L_AOT=$DBA/etc/appsoratab

  L_T_PP=$( echo ${L_T_SID} | cut -c4 )

  if  L_SRC=$( grep "^${L_S_SID}:" ${L_AOT} ) ; then
    printf "\t>$L_SRC<\n" 
    L_S_PP=$( echo $L_SRC | cut -d: -f2 )
    printf "\n L_T_PP=>${L_T_PP}< L_S_PP=>${L_S_PP}<\n"
    echo ${L_SRC} | sed -e "s/${L_S_SID}/${L_T_SID}/"| sed -e "s/${L_S_SID,,}/${L_T_SID,,}/g" | sed -e "s/:${L_S_PP}:/:${L_T_PP}:/" >>${L_AOT}
  else
    printf "\t==   Something wrong with ${L_S_SID}\n"
    L_ERROR=1
  fi

  exit $L_ERROR

}   ### End of  FN_appsoratab ###


function FN_oratab
{
  FN_Header FN_oratab

  L_OT=/etc/oratab

  if  L_SRC=$( grep "^${L_S_SID}:" ${L_OT} ) ; then
    printf "\t>$L_SRC<\n" 
    echo ${L_SRC} | sed -e "s/${L_S_SID}/${L_T_SID}/"| sed -e "s/${L_S_SID,,}/${L_T_SID,,}/g" >> ${L_OT}
  else
    printf "\t==   Something wrong with ${L_S_SID}\n"
    L_ERROR=1
  fi

  exit $L_ERROR
}   ### End of  FN_oratab ###


function FN_check_groups
{
    FN_Header FN_check_group


}   ### End of FN_check_group ###


function FN_mtppt_create
{

  FN_Header FN_mtppt_create

  for N in $( grep d003 /export/vtssupp/VTS/etc/appsoratab | cut -d: -f4 | sed -e "s/,/ /g" )
  do    
    L_DP=$(echo $N | awk -F\- '{print $2}')

    if [ -d $L_DP ]; then
      printf "\t== the directory (${L_DP}) exists\n"
    else
      printf "\t== Creating the directory ${L_DP} \n"
      mkdir -p ${L_DP}
      if [ $(echo ${L_DP} | cut -c2,4) == "ora" ]; then
        chown ${L_ORAUSER}:dba ${L_DP}
        chmod 775 ${L_DP}
      else 
        mkdir -p /export/${L_DP}
        chown ${L_APPLUSER}:applmgr ${L_DP} /export/${L_DP}
        chmod 755 ${L_DP} /export/${L_DP}
      fi
   fi
  done

  touch /${L_APPLUSER}/EBSapps.env
  chown ${L_APPLUSER}:applmgr  /${L_APPLUSER}/EBSapps.env

}  ### End of FN_mtppt_create ###


function FN_create_ebs_users
{
  FN_Header FN_create_ebs_users


  L_T_PP=$( echo ${L_T_SID} | cut -c4 )

  if ( ! grep ${L_ORAUSER} /etc/passwd 2>&1 >/dev/null ); then
    useradd -u $((L_T_PP + 1800 )) -g dba -G ebs -m -d /home/${L_ORAUSER} -s /usr/bin/bash ${L_ORAUSER}
    (echo Velos389; echo Velos389 ) | passwd ${L_ORAUSER}
  fi

  if ( ! grep ${L_APPLUSER} /etc/passwd 2>&1 >/dev/null ); then
    useradd -u $((L_T_PP + 1000 )) -g applmgr -G ebs -m -d /home/${L_APPLUSER} -s /usr/bin/bash ${L_APPLUSER}
   (echo Velos389; echo Velos389 ) | passwd ${L_APPLUSER}
  fi 

}   ### End of FN_create_ebs_users ##



function FN_ORAUSER_profile
{
  FN_Header FN_ORAUSER_profile


  cp $DBA/etc/profile_db /home/${L_ORAUSER}/.bash_profile

  chown ${L_ORAUSER}:dba /home/${L_ORAUSER}/.bash_profile


}   ### End of FN_ORAUSER_profile ###


function FN_APPLUSER_profile
{
  FN_Header FN_APPLUSER_profile

  cp $DBA/etc/profile_apps /home/${L_APPLUSER}/.bash_profile
  chown ${L_ORAUSER}:dba /home/${L_APPLUSER}/.bash_profile


}   ### End of FN_APPLUSER_profile ###


function FN_crypt_seed
{
  FN_Header FN_crypt_seed

  for u in ${L_ORAUSER} ${L_APPLUSER}
  do
    echo "hello" > /home/$u/.appspwd
    chown $u /home/$u/.appspwd
  done
}   ### End of FN_crypt_seed ###


function FN_ssh_keys
{
  FN_Header FN_ssh_keys

  for u in ${L_ORAUSER} ${L_APPLUSER}
  do
    mkdir /home/$u/.ssh
    cp $DBA/etc/auth_keys.txt /home/$u/.ssh/authorized_keys
    
    chown -R $u /home/$u/.ssh
    chmod -R 700 /home/$u/.ssh
  done
}   ### End of FN_ssh_keys ###


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
        FN_create_ebs_users 
        FN_Inc
      #  L_COMPLETE=0
        ;;
      2)
        FN_ORAUSER_profile
        FN_Inc
      #  L_COMPLETE=0
        ;;
      3)
        FN_APPLUSER_profile
        FN_Inc
      # L_COMPLETE=0
        ;;
      4)
        FN_crypt_seed
        FN_Inc
      # L_COMPLETE=0
        ;;
      5)
        FN_ssh_keys
        FN_Inc
      # L_COMPLETE=0
        ;;
      6)
        FN_mtppt_create 
        FN_Inc
      #  L_COMPLETE=0
        ;;
      7)
        FN_oratab 
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
  export L_T_SID=${2:?"Missing the target sid - remember that the training digits are the port pool"}

  PG=$(basename $0 .sh)
  TS=`date +%Y%m%d`

  export LN_BREAK="================================================================="

  export L_COMPLETE=1
  export L_ERROR=0
  export L_STEP=${3:-1}

 if FN_ValidENV $L_T_SID ; then
    FN_Main 2>&1 | tee -a $DBA/logs/${PG}_${L_S_SID}_${L_T_SID}_$(hostname)_$TS.log
  else
    if FN_ValidENV $L_S_SID ; then
      FN_appsoratab
#      FN_Main 2>&1 | tee -a $DBA/logs/${PG}_${L_S_SID}_${L_T_SID}_$(hostname)_$TS.log
    else
      printf "\n the $L_S_SID is invalid\n"
      export L_ERROR=1
    fi
  fi

  exit $L_ERROR
# - - - - - - - - - - - - - - - - - - - - - - - - #
