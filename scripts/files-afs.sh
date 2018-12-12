#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. lib.pe.sh
. global.vars.sh

begin

args_required 'MY_EMAIL PE_PASSWORD PC_VERSION PE_HOST'
files_install
log "Files install complete"
log "PE = https://${PE_HOST}:9440"

finish
