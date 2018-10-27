#!/usr/bin/env bash

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. common.lib.sh
. global.vars.sh

begin

NTNX_cmd # takes care of services coming up.

finish
