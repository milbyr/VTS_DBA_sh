#!/usr/bin/bash

#L_SEED="Velocity"
L_SEED=`cat $HOME/.appspwd`
#L_WORD=${1:?"Missing the word to be encrypted/decrypted"}
L_PG=$(basename $0 .ksh)



function get_decrypted
{
  set +x
  echo "$1" | openssl enc -aes-128-cbc -a -d -salt -pass pass:${L_SEED}
}

function get_encrypted
{
  echo "$1" | openssl enc -aes-128-cbc -a -salt -pass pass:${L_SEED}
}

function print_usage
{
  echo "USE: \c"
  echo "$L_PG (-e|-d) <string>"
  echo '\t\t-d - decrypt'
  echo '\t\t-e - encrypt'
}


function main {

  case $1 in
  -e) # print " executing the following >get_encrypted "$2"<"
      get_encrypted $2
     ;;
  -d) # print " executing the following >get_decrypted "$2"<"
      get_decrypted "$2"
     ;;
  -h) print_usage
     ;;
  *)  echo "You have entered the incorrect options"
      print_usage
     ;;
  esac
}

main $@
