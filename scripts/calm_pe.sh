#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. lib.pe.sh
. global.vars.sh
begin

CheckArgsExist 'MY_EMAIL MY_PE_HOST MY_PE_PASSWORD PC_VERSION'

#Dependencies 'install' 'jq' && NTNX_Download 'PC' & #attempt at parallelization

log "Adding key to PE/CVMs..." && SSH_PubKey || true & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!
Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' \
&& pe_license \
&& pe_init \
&& network_configure \
&& authentication_source \
&& pe_auth \
&& pc_init \
&& Check_Prism_API_Up 'PC'

if (( $? == 0 )) ; then
  pc_configure && Dependencies 'remove' 'sshpass' && Dependencies 'remove' 'jq';
  log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
  log "PE = https://${MY_PE_HOST}:9440"
  log "PC = https://${MY_PC_HOST}:9440"
  finish
else
  log "Error 18: in main functional chain, exit!"
  exit 18
fi
