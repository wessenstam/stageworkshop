#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

CheckArgsExist 'MY_EMAIL PE_PASSWORD PC_VERSION'

#Dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization

log "Adding key to ${1} VMs..."
SSH_PubKey & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    CheckArgsExist 'PE_HOST'

    Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && authentication_source \
    && pe_auth

    if (( $? == 0 )) ; then
      files_install & # parallel test, optional?

      pc_init \
      && Check_Prism_API_Up 'PC' \
      && pc_configure \
      && Dependencies 'remove' 'sshpass' \
      && Dependencies 'remove' 'jq'

      log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
      log "PE = https://${PE_HOST}:9440"
      log "PC = https://${PC_HOST}:9440"

      finish
    else
      finish
      log "Error 18: in main functional chain, exit!"
      exit 18
    fi
  ;;
  PC | pc )
    . lib.pc.sh
    Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' || exit 13

    if [[ -z "${PE_HOST}" ]]; then
      Determine_PE
      . global.vars.sh # re-populate PE_HOST dependencies
    fi

    pc_passwd

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    NTNX_cmd # check cli services available?

    if [[ ! -z "${2}" ]]; then
      # hidden bonus
      log "Don't forget: $0 first.last@nutanixdc.local%password"
      calm_update && exit 0
    fi

    export ATTEMPTS=2
    export    SLEEP=10

    pc_init \
    && pc_dns_add \
    && pc_ui \
    && pc_auth \
    && pc_smtp

    ssp_auth \
    && calm_enable \
    && lcm \
    && images \
    && pc_cluster_img_import \
    && Check_Prism_API_Up 'PC'

    pc_project # TODO:50 pc_project is a new function, non-blocking at end.
    flow_enable

    # NTNX_Upload 'AOS' # function in lib.common.sh

    unset NUCLEI_SERVER NUCLEI_USERNAME NUCLEI_PASSWORD

    if (( $? == 0 )); then
      #Dependencies 'remove' 'sshpass' && Dependencies 'remove' 'jq' \
      #&&
      log "PC = https://${PC_HOST}:9440"
      finish
    else
      _error=19
      log "Error ${_error}: failed to reach PC!"
      exit ${_error}
    fi
  ;;
esac
