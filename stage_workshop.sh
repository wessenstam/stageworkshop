#!/bin/bash
# -x
# use !/bin/bash -x to debug command substitution and evaluation instead of echo.

. scripts/common.lib.sh # source common routines
Dependencies 'install' 'sshpass';

WORKSHOPS=("Calm Introduction Workshop (AOS/AHV PC 5.7.0.x)" \
"Calm Introduction Workshop (AOS/AHV PC 5.6.x)" \
"Citrix Desktop on AHV Workshop (AOS/AHV 5.6)" \
#"Tech Summit 2018" \
"Change Cluster Input File" \
"Validate Staged Clusters" \
"Quit")
ATTEMPTS=40;
   SLEEP=60;
#CURL_OPTS="${CURL_OPTS} --verbose"

# Get list of clusters from user
function get_file {
  read -p 'Cluster Input File: ' CLUSTER_LIST

  if [ ! -f ${CLUSTER_LIST} ]; then
    echo "FILE DOES NOT EXIST!"
    get_file
  fi

  select_workshop
}

function select_workshop {
  # Get workshop selection from user, set script files to send to remote clusters
  PS3='Select an option: '
  select WORKSHOP in "${WORKSHOPS[@]}"
  do
    case $WORKSHOP in
      "Calm Introduction Workshop (AOS/AHV 5.5+)")
        PE_CONFIG=stage_calmhow.sh
        PC_CONFIG=stage_calmhow_pc.sh
        break
        ;;
      "Citrix Desktop on AHV Workshop (AOS/AHV 5.6)")
        PE_CONFIG=stage_citrixhow.sh
        PC_CONFIG=stage_citrixhow_pc.sh
        break
        ;;
      "Tech Summit 2018")
        PE_CONFIG=stage_ts18.sh
        PC_CONFIG=stage_ts18_pc.sh
        break
        ;;
      "Change Cluster Input File")
        get_file
        break
        ;;
      "Validate Staged Clusters")
        validate_clusters
        break
        ;;
      "Quit")
        exit
        ;;
      *) echo "Invalid entry, please try again.";;
    esac
  done

  read -p "Are you sure you want to stage ${WORKSHOP} to the clusters in ${CLUSTER_LIST}? Your only 'undo' option is running Foundation on your cluster(s) again. (Y/N)" -n 1 -r

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo
    stage_clusters
  else
    echo
    echo "Come back soon!"
  fi
}

# Set script files to send to remote clusters based on command line argument
function set_workshop {

#      PE_CONFIG='scripts/'
#      PC_CONFIG=${PE_CONFIG}
  MY_PC_VERSION=5.6

  case ${WORKSHOPS[$((${WORKSHOP_NUM}-1))]} in
    "Calm Introduction Workshop (AOS/AHV PC 5.7.0.x)")
       MY_PC_VERSION=5.7.0.1
          PE_CONFIG+=stage_calmhow.sh
          PC_CONFIG+=stage_calmhow_pc.sh
      stage_clusters
      ;;
    "Calm Introduction Workshop (AOS/AHV PC 5.6.x)")
          PE_CONFIG+=stage_calmhow.sh
          PC_CONFIG+=stage_calmhow_pc.sh
      stage_clusters
      ;;
    "Citrix Desktop on AHV Workshop (AOS/AHV PC 5.6)")
          PE_CONFIG+=stage_citrixhow.sh
          PC_CONFIG+=stage_citrixhow_pc.sh
      stage_clusters
      ;;
    "Tech Summit 2018")
          PE_CONFIG+=stage_ts18.sh
          PC_CONFIG+=stage_ts18_pc.sh
      stage_clusters
      ;;
    "Validate Staged Clusters")
      validate_clusters
      ;;
    *) echo "No one should ever see this. Time to panic.";;
  esac
}

# Send configuration scripts to remote clusters and execute Prism Element script
function stage_clusters {
  local _DEPENDENCIES=''

  if [[ -d cache ]]; then
    #TODO: proper cache detection and downloads
    _DEPENDENCIES='jq-linux64 sshpass-1.06-2.el7.x86_64.rpm'
  fi

  for MY_LINE in `cat ${CLUSTER_LIST} | grep -v ^#`
  do
    set -f
    array=(${MY_LINE//|/ })
    MY_PE_HOST=${array[0]}
    MY_PE_PASSWORD=${array[1]}
    array=(${MY_PE_HOST//./ })
    MY_HPOC_NUMBER=${array[2]}

    #TODO: Check rx cluster foundation status, then PE API login success to proceed!
    # 12 failed SSH login attempts registered, but it took more time than successful email.
    # rx: 20180518 21:38:52 INFO All 140 cluster services are up
    # we move from: ssh: connect to host 10.21.20.37 port 22: Operation timed out
    # lost connection
    # to: Warning: Permanently added '10.21.20.37' (ECDSA) to the list of known hosts.
    # Nutanix Controller VM
    # Permission denied, please try again.

    Check_Prism_API_Up 'PE' 60
    if (( $? == 0 )) ; then
      my_log "Sending configuration script(s) to PE: ${MY_PE_HOST}"
    else
      my_log "Error: Can't reach PE @${MY_PE_HOST}, are you on VPN?"
      exit 15
    fi

    if [[ `pwd | awk -F/ '{ print $NF}'` != 'scripts' ]]; then
      cd scripts
    fi
    remote_exec 'SCP' 'PE' "common.lib.sh ${PE_CONFIG} ${PC_CONFIG}"
    # echo TOFIX: _DEPENDENCIES disabled.
    cd ../cache
    remote_exec 'SCP' 'PE' "${_DEPENDENCIES}"

    # Execute that file asynchroneously remotely (script keeps running on CVM in the background)
    my_log "Executing configuration script on PE: ${MY_PE_HOST}"
    remote_exec 'SSH' 'PE' "MY_PE_PASSWORD=${MY_PE_PASSWORD} MY_PC_VERSION=${MY_PC_VERSION} nohup bash /home/nutanix/${PE_CONFIG} >> stage_calmhow.log 2>&1 &"

    cat <<EOM
Progress of individual clusters can be monitored by:
 $ sshpass -p ${MY_PE_PASSWORD} ssh ${SSH_OPTS} nutanix@${MY_PE_HOST} 'tail -f stage_calmhow.log'
   https://${MY_PE_HOST}:9440/
 $ sshpass -p 'nutanix/4u' ssh ${SSH_OPTS} nutanix@10.21.${MY_HPOC_NUMBER}.39 'tail -f stage_calmhow_pc.log'
EOM
  done
  exit
}

function validate_clusters {
  for MY_LINE in `cat ${CLUSTER_LIST} | grep -v ^#`
  do
    set -f
    array=(${MY_LINE//|/ })
    MY_PE_HOST=${array[0]}
    MY_PE_PASSWORD=${array[1]}
    array=(${MY_PE_HOST//./ })
    MY_HPOC_NUMBER=${array[2]}

    Check_Prism_API_Up 'PE'
    if (( $? == 0 )) ; then
      my_log "Success: execute PE API on ${MY_PE_HOST}"
    else
      my_log "Failure: cannot validate PE API on ${MY_PE_HOST}"
    fi
  done
}

# Display script usage
function usage {
  cat << EOF

    Interactive Usage: ./stage_workshop.sh
Non-interactive Usage: ./stage_workshop.sh -f [cluster_list_file] -w [workshop_number]

Available Workshops:
1) Calm Introduction Workshop (AOS/AHV 5.6)
2) Citrix XenDesktop on Nutanix AHV (AOS/AHV 5.6)

See README.md for more information :+1:

EOF
exit
}

#__main__
# Check if file passed via command line, otherwise prompt for cluster list file
while getopts ":f:w:" opt; do
  case ${opt} in
    f )
    if [ -f ${OPTARG} ]; then
      CLUSTER_LIST=${OPTARG}
    else
      echo "FILE DOES NOT EXIST!"
      usage
    fi
    ;;
    w )
#    if [ $(($OPTARG)) -gt 0 ] && [ $(($OPTARG)) -le $((${#WORKSHOPS[@]}-3)) ]; then
    if [ $(($OPTARG)) -gt 0 ] && [ $(($OPTARG)) -le $((${#WORKSHOPS[@]})) ]; then
      # do something
      WORKSHOP_NUM=${OPTARG}
    else
      echo "INVALID WORKSHOP SELECTION!"
      usage
    fi
    ;;
    \? ) usage;;
  esac
done
shift $((OPTIND -1))

if [ ! -z ${CLUSTER_LIST} ] && [ ! -z ${WORKSHOP_NUM} ]; then
  # If file and workshop selections are valid, begin staging clusters
  set_workshop
elif [ ! -z ${CLUSTER_LIST} ] || [ ! -z ${WORKSHOP_NUM} ]; then
  echo "MISSING ARGUMENTS! CLUSTER_LIST=|${CLUSTER_LIST}|, WORKSHOP_NUM=|${WORKSHOP_NUM}|"
  usage
else
  # If no command line arguments, start interactive session
  get_file
fi
