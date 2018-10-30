#!/usr/bin/env bash
# stageworkshop_pe kill && stageworkshop_w1 && stageworkshop_pe

RELEASE=release.json
if [[ -e ${RELEASE} ]]; then
  echo "Sourced stageworkshop.lib.sh, release: $(grep FullSemVer ${RELEASE} | awk -F\" '{print $4}')"
fi

alias stageworkshop_w1='./stage_workshop.sh -f example_pocs.txt -w 1'

function stageworkshop_cluster() {
  local   _cluster
  local    _fields
  local  _filespec
  export NTNX_USER=nutanix
  local  _tail_arg='--lines='

  if [[ `uname -s` == "Darwin" ]]; then
    _tail_arg='-n '
  fi

  if [[ -n ${1} || ${1} == '' ]]; then
    _filespec=~/Documents/github.com/mlavi/stageworkshop/example_pocs.txt
  else
    _filespec="${1}"
    echo "INFO: Using cluster file: |${1}| ${_filespec}"
  fi

  echo -e "\nAssumptions:
    - Last uncommented cluster in: ${_filespec}
    -     ssh user authentication: ${NTNX_USER}\n"

  _cluster=$(grep --invert-match --regexp '^#' "${_filespec}" | tail ${_tail_arg}1)
   _fields=(${_cluster//|/ })

  export     PE_HOST=${_fields[0]}
  export PE_PASSWORD=${_fields[1]}
  export    MY_EMAIL=${_fields[2]}
  echo "INFO: PE_HOST=${PE_HOST}."
}

function stageworkshop_ssh() {
  local   _cmd
  local  _host
  local _octet

  stageworkshop_cluster ''

  if [[ $1 == 'PC' ]]; then
    echo "PC_VERSION=5.9.0.1 MY_EMAIL=${MY_EMAIL} MY_PE_PASSWORD=${PE_PASSWORD} ./stage_calmhow_pc.sh"
    PE_PASSWORD='nutanix/4u'
         _octet=(${PE_HOST//./ }) # zero index
          _host=${_octet[0]}.${_octet[1]}.${_octet[2]}.$((_octet[3] + 2))
  else
    _host=${PE_HOST}
    echo "curl --remote-name --location https://raw.githubusercontent.com/mlavi/stageworkshop/master/bootstrap.sh && SOURCE=${_} sh ${_##*/}"
  fi

  case "${2}" in
    log | logs)
      _cmd='date; tail -f stage_*.log'
      ;;
    calm | inflight)
      _cmd='ps -efww | grep calm'
      ;;
    kill | stop)
      _cmd='ps -efww | grep calm ; pkill calm; pkill tail; ps -efww | grep calm'
      ;;
    *)
      _cmd="${2}"
      ;;
  esac

  echo "INFO: ${_host} $ ${_cmd}"
  SSHPASS="${PE_PASSWORD}" sshpass -e ssh -q \
    -o StrictHostKeyChecking=no \
    -o GlobalKnownHostsFile=/dev/null \
    -o UserKnownHostsFile=/dev/null \
    ${NTNX_USER}@"${_host}" "${_cmd}"

  unset NTNX_USER PE_HOST PE_PASSWORD SSHPASS
}

function stageworkshop_pe() {
  stageworkshop_ssh 'PE' "${1}"
}

function stageworkshop_pc() {
  stageworkshop_ssh 'PC' "${1}"
}

# TODO: prompt for choice when more than one cluster
# TODO: bootstrap calling 4 scripts, starting with ./stage_workshop.sh -f example_pocs.txt -w 1
# TODO: scp?
