#!/usr/bin/env bash

     CURL_OPTS='--insecure --silent --show-error' # --verbose'
CURL_POST_OPTS="${CURL_OPTS} --max-time 5 --header Content-Type:application/json --header Accept:application/json --output /dev/null"
CURL_HTTP_OPTS="${CURL_POST_OPTS} --write-out %{http_code}"
      SSH_OPTS='-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null'
     SSH_OPTS+=' -q' # -v'

function log {
  local CALLER=$(echo -n `caller 0 | awk '{print $2}'`)
  echo $(date "+%Y-%m-%d %H:%M:%S")"|${CALLER}|${1}"
}

function CheckArgsExist {
  local _ARGUMENT
  local    _ERROR=88
  for _ARGUMENT in ${1}; do
    if [[ ${DEBUG} ]]; then
      log "DEBUG: Checking ${_ARGUMENT}..."
    fi
    _RESULT=$(eval "echo \$${_ARGUMENT}")
    if [[ -z ${_RESULT} ]]; then
      log "Error ${_ERROR}: ${_ARGUMENT} not provided!"
      exit ${_ERROR}
    elif [[ ${DEBUG} ]]; then
      log "Non-error: ${_ARGUMENT} for ${_RESULT}"
    fi
  done
  if [[ ${DEBUG} ]]; then
    log 'Success: required arguments provided.'
  fi
}

function Download {
  local           _ATTEMPTS=2
  local              _ERROR=0
  local _HTTP_RANGE_ENABLED='--continue-at -'
  local               _LOOP=0
  local              _SLEEP=2

  if [[ -z ${1} ]]; then
    _ERROR=33
    log "Error ${_ERROR}: no URL to download!"
    exit ${_ERROR}
  fi

  while true ; do
    (( _LOOP++ ))
    log "${1}..."
    local _OUTPUT=''
    curl ${CURL_OPTS} ${_HTTP_RANGE_ENABLED} --remote-name --location ${1}
    _OUTPUT=$?
    #DEBUG=1; if [[ ${DEBUG} ]]; then log "DEBUG: curl exited ${_OUTPUT}."; fi

    if (( ${_OUTPUT} == 0 )); then
      log "Success: ${1##*/}"
      break
    fi

    if (( ${_LOOP} == ${_ATTEMPTS} )); then
      log "Error: couldn't download from: ${1}, giving up after ${_LOOP} tries."
      exit 11
    elif (( ${_OUTPUT} == 33 )); then
      log "Web server doesn't support HTTP range command, purging and falling back."
      _HTTP_RANGE_ENABLED=''
      rm -f ${1##*/}
    else
      log "${_LOOP}/${_ATTEMPTS}: curl=${_OUTPUT} ${1##*/} SLEEP ${_SLEEP}..."
      sleep ${_SLEEP}
    fi
  done
}

function remote_exec { # TODO: similaries to Check_Prism_API_Up
# Argument ${1} = REQIRED: ssh or scp
# Argument ${2} = REQIRED: PE, PC, or LDAP_SERVER
# Argument ${3} = REQIRED: command configuration
# Argument ${4} = OPTIONAL: populated with anything = allowed to fail

  local  _ACCOUNT='nutanix'
  local _ATTEMPTS=3
  local    _ERROR=99
  local     _HOST=${MY_PE_HOST}
  local     _LOOP=0
  local _PASSWORD="${MY_PE_PASSWORD}"
  local    _SLEEP=${SLEEP}
  local     _TEST=0

  case ${2} in
    'PC' )
          _HOST=${MY_PC_HOST}
      _PASSWORD='nutanix/4u' # TODO: hardcoded p/w
      ;;
    'LDAP_SERVER' )
       _ACCOUNT='root'
          _HOST=${LDAP_HOST}
      _PASSWORD='nutanix/4u' # TODO: hardcoded p/w
         _SLEEP=7
      ;;
  esac

  if [[ -z ${3} ]]; then
    log 'Error ${_ERROR}: missing third argument.'
    exit ${_ERROR}
  fi

  while true ; do
    (( _LOOP++ ))
    case "${1}" in
      'SSH' | 'ssh')
       #DEBUG=1; if [[ ${DEBUG} ]]; then log "_TEST will perform ${_ACCOUNT}@${_HOST} ${3}..."; fi
        SSHPASS="${_PASSWORD}" sshpass -e ssh -x ${SSH_OPTS} ${_ACCOUNT}@${_HOST} "${3}"
        _TEST=$?
        ;;
      'SCP' | 'scp')
        #DEBUG=1; if [[ ${DEBUG} ]]; then log "_TEST will perform scp ${3} ${_ACCOUNT}@${_HOST}:"; fi
        SSHPASS="${_PASSWORD}" sshpass -e scp ${SSH_OPTS} ${3} ${_ACCOUNT}@${_HOST}:
        _TEST=$?
        ;;
      *)
        log "Error ${_ERROR}: improper first argument, should be ssh or scp."
        exit ${_ERROR}
        ;;
    esac

    if (( ${_TEST} > 0 )) && [[ -z ${4} ]]; then
      _ERROR=22
      log "Error ${_ERROR}: pwd=`pwd`, _TEST=${_TEST}, _HOST=${_HOST}"
      exit ${_ERROR}
    fi

    if (( ${_TEST} == 0 )); then
      if [[ ${DEBUG} ]]; then log "${3} executed properly."; fi
      return 0
    elif (( ${_LOOP} == ${_ATTEMPTS} )); then
      _ERROR=11
      log "Error ${_ERROR}: giving up after ${_LOOP} tries."
      exit ${_ERROR}
    else
      log "${_LOOP}/${_ATTEMPTS}: _TEST=$?|${_TEST}| ${FILENAME} SLEEP ${_ACCOUNT}..."
      sleep ${_SLEEP}
    fi
  done
}

function Dependencies {
  local _ERROR

  if [[ -z ${1} ]]; then
    _ERROR=20
    log "Error ${_ERROR}: missing install or remove verb."
    exit ${_ERROR}
  elif [[ -z ${2} ]]; then
    _ERROR=21
    log "Error ${_ERROR}: missing package name."
    exit ${_ERROR}
  fi

  case "${1}" in
    'install')
      log "Install ${2}..."
      export PATH=${PATH}:${HOME}

      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # TOFIX: assumption, probably on NTNX CVM or PCVM = CentOS7
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
                log "Error: can't install ${2}."
                exit 98
              fi
            else
              log "Success: found ${2}."
            fi
            ;;
          jq )
            if [[ -z `which ${2}` ]]; then
              if [[ ! -e jq-linux64 ]]; then
                # https://stedolan.github.io/jq/download/#checksums_and_signatures
                Download https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
              fi
              if (( $? > 0 )); then
                log "Error: can't install ${2}."
                exit 98
              else
                chmod u+x jq-linux64 && ln -s jq-linux64 jq
              fi
            else
              log "Success: found ${2}."
            fi
            ;;
        esac
      elif [[ `uname -s` == "Darwin" ]]; then
        #MacOS
        case "${2}" in
          sshpass )
            if [[ -z `which ${2}` ]]; then
              brew install https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb
              if (( $? > 0 )); then
                _ERROR=98
                log "Error ${_ERROR}: can't install ${2}."
                exit ${_ERROR}
              fi
            else
              log "Success: found ${2}."
            fi
            ;;
          jq )
            if [[ -z `which ${2}` ]]; then
              brew install jq
              if (( $? > 0 )); then
                _ERROR=98
                log "Error ${_ERROR}: can't install ${2}."
                exit ${_ERROR}
              fi
            else
              log "Success: found ${2}."
            fi
            ;;
        esac
      fi #MacOS
      ;;
    'remove')
      log "Removing ${2}..."
      if [[ `uname --operating-system` == "GNU/Linux" ]]; then
        # probably on NTNX CVM or PCVM = CentOS7
        case "${2}" in
          sshpass )
            sudo rpm -e sshpass
            ;;
          jq )
            rm -f jq jq-linux64
            ;;
        esac
      else
        log "FEATURE: don't remove Dependencies on Mac."
      fi
      ;;
  esac
}

function Check_Prism_API_Up { # TODO: similaries to remote_exec
# Argument ${1} = REQUIRED: PE or PC
# Argument ${2} = OPTIONAL: number of attempts
# Argument ${3} = OPTIONAL: number of seconds per cycle
  local _ATTEMPTS=${ATTEMPTS}
  local    _ERROR=77
  local     _HOST=${MY_PE_HOST}
  local     _LOOP=0
  local _PASSWORD="${MY_PE_PASSWORD}"
  local    _SLEEP=${SLEEP}
  local     _TEST=0

  CheckArgsExist 'ATTEMPTS MY_PE_HOST MY_PC_HOST MY_PE_PASSWORD SLEEP'

  if [[ ${1} == 'PC' ]]; then
    _HOST=${MY_PC_HOST}
  fi
  if [[ ! -z ${2} ]]; then
    _ATTEMPTS=${2}
  fi

  while true ; do
    (( _LOOP++ ))
    _TEST=$(curl ${CURL_HTTP_OPTS} --user admin:${_PASSWORD} \
      -X POST --data '{ "kind": "cluster" }' \
      https://${_HOST}:9440/api/nutanix/v3/clusters/list \
      | tr -d \") # wonderful addition of "" around HTTP status code by cURL

    if [[ ! -z ${3} ]]; then
      _SLEEP=${3}
    fi

    if (( ${_TEST} == 401 )) && [[ ${1} == 'PC' ]] && [[ ${_PASSWORD} != 'Nutanix/4u' ]]; then
      _PASSWORD='Nutanix/4u' # TODO: hardcoded p/w
      log "Warning @${1}: Fallback on ${_HOST}: try initial password next cycle..."
      _SLEEP=0 #break
    fi

    if (( ${_TEST} == 200 )); then
      log "@${1}: successful."
      return 0
    elif (( ${_LOOP} > ${_ATTEMPTS} )); then
      log "Warning ${_ERROR} @${1}: Giving up after ${_LOOP} tries."
      return ${_ERROR}
    else
      log "@${1} ${_LOOP}/${_ATTEMPTS}=${_TEST}: sleep ${_SLEEP} seconds..."
      sleep ${_SLEEP}
    fi
  done
}
