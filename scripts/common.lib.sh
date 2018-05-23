#!/usr/bin/env bash

# TODO: lost local override for verbose
     CURL_OPTS='--insecure --header Content-Type:application/json --silent --show-error --max-time 5'
#     CURL_OPTS="${CURL_OPTS} --verbose"
CURL_POST_OPTS="${CURL_OPTS} --header Accept:application/json --output /dev/null"
CURL_HTTP_OPTS="${CURL_POST_OPTS} --write-out %{http_code}"
      SSH_OPTS='-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null'
      SSH_OPTS="${SSH_OPTS} -q" # "-v"

function my_log {
  #TODO: Make logging format configurable
  echo $(date "+%Y-%m-%d %H:%M:%S")"|${1}"
}

function acli {
	remote_exec 'SSH' 'PE' "/usr/local/nutanix/bin/acli $@"
}

function remote_exec { # was send_file
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
  case "$1" in
    'install')
      my_log "Install Dependencies"
      export PATH=${PATH}:${HOME}

      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        if [[ -z `which sshpass` ]]; then
          sudo rpm -ivh http://mirror.centos.org/centos/7/extras/x86_64/Packages/sshpass-1.06-2.el7.x86_64.rpm
          # https://pkgs.org/download/sshpass
          # https://sourceforge.net/projects/sshpass/files/sshpass/
          if (( $? > 0 )) ; then
            my_log "Dependencies: ERROR: can't install sshpass."
            exit 98
          fi
        else
          my_log "Dependencies: found sshpass"
        fi

        if [[ -z `which jq` ]]; then
          curl --remote-name --location --retry 3 --show-error \
            https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
          if (( $? > 0 )) ; then
            my_log "Dependencies: ERROR: can't download jq."
            exit 98
          else
            chmod u+x jq-linux64 && ln -s jq-linux64 jq
          fi
        else
          my_log "Dependencies: found jq"
        fi
      fi

      if [[ `uname -s` == "Darwin" ]]; then #MacOS
        if [[ -z `which sshpass` ]]; then
          brew install https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb;
          if (( $? > 0 )) ; then
            my_log "Dependencies: ERROR: can't install sshpass."
            exit 98
          fi
        else
          my_log "Dependencies: found sshpass"
        fi

        if [[ -z `which jq` ]]; then
          brew install jq;
        else
          my_log "Dependencies: found jq"
        fi
      fi
      ;;
    'remove')
      my_log "Dependencies: removing..."
      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        sudo rpm -e sshpass
        rm -f jq jq-linux64
      fi
      ;;
    esac
}

function Prism_API_Up
{
  #my_log "PC Configuration complete: Waiting for deployment to complete, API up..."
  local       LOOP=0;
  local   PASSWORD=${MY_PE_PASSWORD};
  local PRISM_TEST=0;
  local LAST_OCTET=39; # default to PC
  if [[ ${1} == 'PE' ]]; then
    LAST_OCTET=37;
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
  # if [[ ${PCTEST} != "200" ]]; then
  #   echo -e "\e[1;31m${MY_PE_HOST} - Prism Central staging FAILED\e[0m"
  #   echo ${MY_PE_HOST} - Review logs at ${MY_PE_HOST}:/home/nutanix/stage_calmhow.log \
  #    and 10.21.${MY_HPOC_NUMBER}.39:/home/nutanix/stage_calmhow_pc.log
  # elif [[ $(acli vm.list) =~ "STAGING-FAILED" ]]; then
  #   echo -e "\e[1;31m${MY_PE_HOST} - Image staging FAILED\e[0m"
  #   echo ${MY_PE_HOST} - Review log at ${MY_PE_HOST}:stage_calmhow.log
  # fi
}
