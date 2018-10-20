#!/usr/bin/env bash
echo "Sourced $(pwd)/stageworkshop.lib.sh, version: TBD"

function stageworkshop-cluster() {
  local   _cluster
  local    _fields
  local  _filespec
  export NTNX_USER=nutanix
  local  _tail_arg

  if [[ -n ${1} || ${1} == '' ]]; then
    _filespec=~/Documents/github.com/mlavi/stageworkshop/example_pocs.txt
  else
    _filespec="${1}"
    echo "INFO: Using cluster file: |${1}| ${_filespec}"
  fi

  echo -e "Assumptions:\n
    - Only the last uncommented cluster in manifest: ${_filespec}
    -                    Authenticating with ssh as: ${NTNX_USER}\n"

  _tail_arg='--lines='
  if [[ `uname -s` == "Darwin" ]]; then
    _tail_arg='-n '
  fi

  _cluster=$(grep --invert-match --regexp '^#' "${_filespec}" | tail ${_tail_arg}1)
   _fields=(${_cluster//|/ })

  export     PE_HOST=${_fields[0]}
  export PE_PASSWORD=${_fields[1]}
  echo "INFO: PE_HOST=${PE_HOST}."
}

function stageworkshop-ssh() {
  local   _cmd
  local  _host
  local _octet

  stageworkshop-cluster ''

  if [[ $1 == 'PC' ]]; then
    PE_PASSWORD='nutanix/4u'
         _octet=(${PE_HOST//./ }) # zero index
          _host=${_octet[0]}.${_octet[1]}.${_octet[2]}.$((_octet[3] + 2))
  else
    _host=${PE_HOST}
  fi

  case "${2}" in
    log | logs)
      _cmd='date; tail -f stage_*.log'
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

function stageworkshop-pe() {
  stageworkshop-ssh 'PE' "${1}"
}

function stageworkshop-pc() {
  stageworkshop-ssh 'PC' "${1}"
}

# TODO: prompt for choice when more than one cluster
# TODO: bootstrap calling 4 scripts, starting with ./stage_workshop.sh -f example_pocs.txt -w 1
# TODO: scp?
