#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'EMAIL PE_HOST PE_PASSWORD PC_VERSION'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization

log "Adding key to PE/CVMs..."
ssh_pubkey & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && files_install \
    && images \
    && pc_install "${NW1_NAME}" \
    && prism_check 'PC'

    if (( $? == 0 )) ; then
      pc_configure #\
      # && dependencies 'remove' 'sshpass' \
      # && dependencies 'remove' 'jq'

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
esac
