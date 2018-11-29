#!/usr/bin/env bash
# -x

function img_import() {
  local _http_body='{"action_on_failure":"CONTINUE","execution_order":"SEQUENTIAL","api_request_list":[{"operation":"POST","path_and_params":"/api/nutanix/v3/images","body":{"spec":{"name":"nutanix-afs","description":"testdesc","resources":{"image_type":"DISK_IMAGE","source_uri":"http://10.21.250.221/images/ahv/techsummit/nutanix-afs-el7.3-release-afs-3.0.0.1-stable.qcow2"}},"metadata":{"kind":"image"},"api_version":"3.1.0"}}],"api_version":"3.0"}'
  local      _test

  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/batch)
  log "batch _test=|${_test}|"
}
function cluster_img_import() {
  local _http_body='{"action_on_failure":"CONTINUE","execution_order":"SEQUENTIAL","api_request_list":[{"operation":"POST","path_and_params":"/api/nutanix/v3/images/migrate","body":{"image_reference_list":[],"cluster_reference":{"uuid":"00057baf-2e83-dcfd-0000-0000000086b7","kind":"cluster","name":"string"}}}],"api_version":"3.0"}'
  local      _test

  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/batch)
  log "batch _test=|${_test}|"
}

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

    if [[ -n ${PE_PASSWORD} ]]; then
      Determine_PE
      . global.vars.sh # populate PE_HOST dependencies
    fi

    pc_passwd

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password nx2Tech704\! vm.list

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
    && Check_Prism_API_Up 'PC'

    pc_project # TODO:50 pc_project is a new function, non-blocking at end.
    flow_enable

    img_import
    cluster_img_import
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
