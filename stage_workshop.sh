#!/bin/bash
# -x
# use !/bin/bash -x to debug command substitution and evaluation instead of echo.

WORKSHOPS=(\
"Calm Workshop (AOS/AHV PC 5.8)" \
"Calm Workshop (AOS/AHV PC 5.7.1)" \
"Calm Workshop (AOS/AHV PC 5.6.x)" \
"Citrix Desktop on AHV Workshop (AOS/AHV 5.6)" \
#"Tech Summit 2018" \
)

function usage {
  # Display script usage
  cat << EOF

See README.md and guidebook.md for more information.

    Interactive Usage: $0
Non-interactive Usage: $0 -f [${_CLUSTER_FILE}] -w [workshop_number]

Available Workshops:
EOF

  for (( i = 0; i < ${#WORKSHOPS[@]}-${NONWORKSHOPS}; i++ )); do
    let OFFBYONE=$i+1
    echo "${OFFBYONE} = ${WORKSHOPS[$i]}"
  done

  exit
}

function get_file {
  echo
  read -p "$_CLUSTER_FILE: " CLUSTER_LIST # Prompt user

  if [[ ! -f "${CLUSTER_LIST}" ]]; then
    echo "Error: file not found = ${CLUSTER_LIST}"
    get_file
  fi

  echo
  select_workshop
}

function select_workshop {
  # Get workshop selection from user, set script files to send to remote clusters
  PS3='Select an option: '
  select WORKSHOP in "${WORKSHOPS[@]}"
  do
    case $WORKSHOP in
      "Change ${_CLUSTER_FILE}")
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
      *)
        for (( i = 0; i < ${#WORKSHOPS[@]}-${NONWORKSHOPS}; i++ )); do
          if [[ ${WORKSHOPS[$i]} == ${WORKSHOP} ]]; then
            let WORKSHOP_NUM=$i+1
          fi
        done

        if [[ ${WORKSHOP_NUM} == "" ]]; then
          echo -e "\nInvalid entry = ${WORKSHOP}, please try again."
        else
          echo "Matched!"
          break
        fi
        ;;
    esac
  done

  echo -e "\nAre you sure you want to stage ${WORKSHOP} to the clusters in ${CLUSTER_LIST}? \
    \nYour only 'undo' option is running Foundation on your cluster(s) again."
  read -p '(Y/N)' -n 1 -r

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo
    stage_clusters
  else
    echo -e "\nCome back soon!"
  fi
}

function stage_clusters {
  # Send configuration scripts to remote clusters and execute Prism Element script
  Dependencies 'install' 'sshpass'

  log "WORKSHOP #${WORKSHOP_NUM} = ${WORKSHOPS[$((${WORKSHOP_NUM}-1))]}"
  #  case ${WORKSHOPS[$((${WORKSHOP_NUM}-1))]} in
  case ${WORKSHOPS[$((${WORKSHOP_NUM}-1))]} in
    "Calm Workshop (AOS/AHV PC 5.7.1)")
      MY_PC_VERSION=5.7.1
         PE_CONFIG+=stage_calmhow.sh
         PC_CONFIG+=stage_calmhow_pc.sh
      ;;
    "Calm Workshop (AOS/AHV PC 5.6.x)")
      MY_PC_VERSION=5.6
         PE_CONFIG+=stage_calmhow.sh
         PC_CONFIG+=stage_calmhow_pc.sh
      ;;
    "Calm Workshop (AOS/AHV PC 5.8)")
      MY_PC_VERSION=5.8
         PE_CONFIG+=stage_calmhow.sh
         PC_CONFIG+=stage_calmhow_pc.sh
      ;;
    "Citrix Desktop on AHV Workshop (AOS/AHV PC 5.6)")
      PE_CONFIG+=stage_citrixhow.sh
      PC_CONFIG+=stage_citrixhow_pc.sh
      ;;
    "Tech Summit 2018")
      PE_CONFIG+=stage_ts18.sh
      PC_CONFIG+=stage_ts18_pc.sh
      ;;
    # *)
    #   echo "No one should ever see this. Time to panic."
    #   ;;
  esac

  for MY_LINE in `cat ${CLUSTER_LIST} | grep -v ^#`
  do
    set -f
           _FIELDS=(${MY_LINE//|/ })
        MY_PE_HOST=${_FIELDS[0]}
    MY_PE_PASSWORD=${_FIELDS[1]}
          MY_EMAIL=${_FIELDS[2]}

    . scripts/global.vars.sh # re-import for relative settings

    Check_Prism_API_Up 'PE' 60

    if [[ -d cache ]]; then
      #TODO:60 proper cache detection and downloads
      local _DEPENDENCIES='jq-linux64 sshpass-1.06-2.el7.x86_64.rpm'
      log "Sending cached dependencies (optional)..."
      cd cache && remote_exec 'SCP' 'PE' "${_DEPENDENCIES}" 'OPTIONAL' \
        && cd ..
    fi

    if (( $? == 0 )) ; then
      log "Sending configuration script(s) to PE@${MY_PE_HOST}"
    else
      log "Error: Can't reach PE@${MY_PE_HOST}, are you on VPN?"
      exit 15
    fi

    cd scripts && remote_exec 'SCP' 'PE' "common.lib.sh global.vars.sh ${PE_CONFIG} ${PC_CONFIG}" \
      && cd ..

    # For Calm container updates...
    if [[ -d cache/pc-${MY_PC_VERSION}/ ]]; then
      log "Uploading PC updates in background..."
      cd cache/pc-${MY_PC_VERSION} \
      && pkill scp || true
      for _CONTAINER in epsilon nucalm ; do \
        if [[ -f ${_CONTAINER}.tar ]]; then \
          remote_exec 'SCP' 'PE' ${_CONTAINER}.tar 'OPTIONAL' & \
        fi
      done
      cd ../..
    else
      log "No PC updates found in cache/pc-${MY_PC_VERSION}/"
    fi

    SSHKEY=${HOME}/.ssh/id_rsa.pub
    if [[ -f ${SSHKEY} ]]; then
      log "Sending ${SSHKEY} for additon to cluster..."
      remote_exec 'SCP' 'PE' ${SSHKEY} 'OPTIONAL'
    fi

    log "Remote execution configuration script on PE@${MY_PE_HOST}"
    remote_exec 'SSH' 'PE' "MY_EMAIL=${MY_EMAIL} MY_PE_HOST=${MY_PE_HOST} MY_PE_PASSWORD=${MY_PE_PASSWORD} MY_PC_VERSION=${MY_PC_VERSION} nohup bash /home/nutanix/${PE_CONFIG} >> stage_calmhow.log 2>&1 &"

    cat <<EOM

Cluster automation progress can be monitored via Prism Element and Central.

If your SSH key has been uploaded to Prism > Gear > Cluster Lockdown,
the following will fail silently, use ssh nutanix@{PE|PC} instead.

$ SSHPASS='${MY_PE_PASSWORD}' sshpass -e ssh ${SSH_OPTS} \\
    nutanix@${MY_PE_HOST} 'date; tail -f stage_calmhow.log'
  You can login to PE to see tasks in flight and eventual PC registration:
  https://admin:${MY_PE_PASSWORD}@${MY_PE_HOST}:9440/

$ SSHPASS='nutanix/4u' sshpass -e ssh ${SSH_OPTS} \\
    nutanix@${MY_PC_HOST} 'date; tail -f stage_calmhow_pc.log'
  https://admin@${MY_PC_HOST}:9440/

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

    Check_Prism_API_Up 'PE'
    if (( $? == 0 )) ; then
      log "Success: execute PE API on ${MY_PE_HOST}"
    else
      log "Failure: cannot validate PE API on ${MY_PE_HOST}"
    fi
  done
}

#__main__

. scripts/common.lib.sh # source common routines
. scripts/global.vars.sh

    _VALIDATE='Validate Staged Clusters'
_CLUSTER_FILE='Cluster Input File'

# NONWORKSHOPS appended to end of WORKSHOPS
             WORKSHOP_COUNT=${#WORKSHOPS[@]}
WORKSHOPS[${#WORKSHOPS[@]}]="Change ${_CLUSTER_FILE}"
WORKSHOPS[${#WORKSHOPS[@]}]=${_VALIDATE}
WORKSHOPS[${#WORKSHOPS[@]}]="Quit"
           let NONWORKSHOPS=${#WORKSHOPS[@]}-${WORKSHOP_COUNT}

# Check if file passed via command line, otherwise prompt for cluster list file
while getopts "f:w:\?" opt; do
  log "Checking option: ${opt} with arguent ${OPTARG}"
  case ${opt} in
    f )
      if [ -f ${OPTARG} ]; then
        CLUSTER_LIST=${OPTARG}
      else
        echo "Error: file not found = ${OPTARG}"
        usage
      fi
      ;;
    w )
      if [[ $(($OPTARG)) > 0 ]] \
      && [[ $(($OPTARG)) < $((${#WORKSHOPS[@]}-${NONWORKSHOPS}+1)) ]]; then
        WORKSHOP_NUM=${OPTARG}
      else
        echo "Error: workshop not found = ${OPTARG}"
        usage
      fi
      ;;
    \? )
      usage
      ;;
  esac
done
shift $((OPTIND -1))

if [[ -n ${CLUSTER_LIST} && -n ${WORKSHOP_NUM} ]]; then
  stage_clusters
elif [[ -n ${CLUSTER_LIST} ]]; then
  log "Error: missing ${_CLUSTER_FILE} argument."
  usage
elif [[ -n ${WORKSHOP_NUM} ]]; then
  log "Error: missing workshop number argument."
  usage
elif [[ ${WORKSHOPS[${WORKSHOP_NUM}]} == ${_VALIDATE} ]]; then
  validate_clusters
else
  get_file # If no command line arguments, start interactive session
fi
