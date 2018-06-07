#!/usr/bin/env bash

# TODO: lost local override for verbose
     CURL_OPTS='--insecure --silent --show-error' # --verbose"
CURL_POST_OPTS="${CURL_OPTS} --max-time 5 --header Content-Type:application/json --header Accept:application/json --output /dev/null"
CURL_HTTP_OPTS="${CURL_POST_OPTS} --write-out %{http_code}"
      SSH_OPTS='-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null'
      SSH_OPTS="${SSH_OPTS} -q" # "-v"

function my_log {
  #TODO: Make logging format configurable
  local CALLER=$(echo -n `caller 0 | awk '{print $2}'`)
  echo $(date "+%Y-%m-%d %H:%M:%S")"|${CALLER}|${1}"
}

function download {
  my_log "Download ${1}"
  curl ${CURL_OPTS} --remote-name --location --retry 3 --continue-at - ${1}
  if (( $? > 0 )) ; then
    my_log "Error: couldn't download from: ${1}"
    exit 1
  fi
}

function acli {
	remote_exec 'SSH' 'PE' "/usr/local/nutanix/bin/acli $@"
}

function remote_exec {
  local   ATTEMPTS=3
  local       LOOP=0
  local   SSH_TEST=0
  local   PASSWORD="${MY_PE_PASSWORD}"
  local LAST_OCTET=37 # default to PE
  if [[ ${2} == 'PC' ]]; then
    LAST_OCTET=39 # Prism Cental
      PASSWORD='nutanix/4u' # TODO: hardcoded p/w
  fi
  local      HOST="10.21.${MY_HPOC_NUMBER}.${LAST_OCTET}"
  if [[ -z ${3} ]]; then
    my_log 'remote_exec: ERROR -- missing third argument. Exit.'
    exit 99
  fi

  while true ; do
    (( LOOP++ ))
    case "${1}" in
      'SSH' | 'ssh')
        SSH_TEST=$(sshpass -p ${PASSWORD} ssh -x ${SSH_OPTS} nutanix@${HOST} "${3}")
        my_log "remote_exec:SSH_TEST:${SSH_TEST}:$?"
        ;;
      'SCP' | 'scp')
        # local FILENAME="${1##*/}"
        SSH_TEST=$(sshpass -p ${PASSWORD} scp ${SSH_OPTS} ${3} nutanix@${HOST}:)
        my_log "remote_exec:SSH_TEST:${SSH_TEST}:$?"
        ;;
      *)
        my_log "remote_exec:Error: improper first argument, should be ssh or scp. Exit."
        exit 99
        ;;
    esac

    if (( $? == 0 )); then
      my_log "remote_exec: |${1}|${2}|${3}| done"
      break;
    elif (( ${LOOP} == ${ATTEMPTS} )); then
      my_log "remote_exec: giving up after ${LOOP} tries."
      exit 11;
    else
      my_log "remote_exec ${LOOP}/${ATTEMPTS}: SSH_TEST=$?|${SSH_TEST}| ${FILENAME} SLEEP ${SLEEP}...";
      sleep ${SLEEP};
    fi
  done
}

function Dependencies {
  if [[ -z ${1} ]]; then
    my_log "Error: missing install or remove verb."
    exit 20
  elif [[ -z ${2} ]]; then
    my_log "Error: missing package name."
    exit 21
  fi

  case "$1" in
    'install')
      my_log "Install..."
      export PATH=${PATH}:${HOME}

      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        case "${2}" in
          sshpass )
            if [[ -z `which ${2}` ]]; then
              if [[ -e sshpass-1.06-2.el7.x86_64.rpm ]]; then
                sudo rpm -ihv sshpass-1.06-2.el7.x86_64.rpm
              else
                sudo rpm -ivh http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm
                # https://pkgs.org/download/sshpass
                # https://sourceforge.net/projects/sshpass/files/sshpass/
              fi
              if (( $? > 0 )) ; then
                my_log "Error: can't install ${2}."
                exit 98
              fi
            else
              my_log "Success: found ${2}."
            fi
            ;;
          jq )
            if [[ -z `which ${2}` ]]; then
              if [[ ! -e jq-linux64 ]]; then
                # https://stedolan.github.io/jq/download/#checksums_and_signatures
                download https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
              fi
              if (( $? > 0 )) ; then
                my_log "Error: can't install ${2}."
                exit 98
              else
                chmod u+x jq-linux64 && ln -s jq-linux64 jq
              fi
            else
              my_log "Success: found ${2}."
            fi
            ;;
        esac
      elif [[ `uname -s` == "Darwin" ]]; then
        #MacOS
        case "${2}" in
          sshpass )
            if [[ -z `which ${2}` ]]; then
              brew install https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb;
              if (( $? > 0 )) ; then
                my_log "Error: can't install ${2}."
                exit 98
              fi
            else
              my_log "Success: found ${2}."
            fi
            ;;
          jq )
            if [[ -z `which ${2}` ]]; then
              brew install jq

              if (( $? > 0 )) ; then
                my_log "Error: can't install ${2}."
                exit 98
              fi
            else
              my_log "Success: found ${2}."
            fi
            ;;
        esac
      fi #MacOS
      ;;

    'remove')
      my_log "Dependencies: removing..."
      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        sudo rpm -e sshpass
        rm -f jq jq-linux64
      fi
      ;;
      # FEATURE: don't remove Dependencies on Mac. :)
    esac
}

function Check_Prism_API_Up
{
  #my_log "PC Configuration complete: Waiting for deployment to complete, API up..."
  local       LOOP=0
  local   PASSWORD=${MY_PE_PASSWORD}
  local PRISM_TEST=0
  local LAST_OCTET=39 # default to PC
  if [[ ${1} == 'PE' ]]; then
    LAST_OCTET=37
  fi
  if [[ ! -z ${2} ]]; then
    local ATTEMPTS=${2}
  fi

  while true ; do
    (( LOOP++ ))
    PRISM_TEST=$(curl ${CURL_HTTP_OPTS} --user admin:${PASSWORD} \
      -X POST --data '{ "kind": "cluster" }' \
      https://10.21.${MY_HPOC_NUMBER}.${LAST_OCTET}:9440/api/nutanix/v3/clusters/list \
      | tr -d \") # wonderful addition of "" around HTTP status code by cURL

    if (( $? > 0 )); then
      echo
    fi
    if (( ${PRISM_TEST} == 401 )) && [[ ${1} == 'PC' ]] ; then
      PASSWORD='Nutanix/4u'
      my_log "PRISM_API_Up@${1}: Fallback: try initial password next cycle..."
    fi

    if (( ${PRISM_TEST} == 200 )) ; then
      my_log "PRISM_API_Up@${1}: successful"
      return 0
      break
    elif (( ${LOOP} > ${ATTEMPTS} )) ; then
      my_log "PRISM_API_Up@${1}: Giving up after ${LOOP} tries."
      return 11
    else
      my_log "__PRISM_API_Up@${1} ${LOOP}/${ATTEMPTS}=${PRISM_TEST}: sleep ${SLEEP} seconds..."
      sleep ${SLEEP}
    fi
  done
}
