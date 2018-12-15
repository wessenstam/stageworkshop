#!/usr/bin/env bash
# -x

function pc_admin() {
  local  _http_body
  local       _test
  local _admin_user='marklavi'

  _http_body=$(cat <<EOF
  {"profile":{
    "username":"${_admin_user}",
    "firstName":"Mark",
    "lastName":"Lavi",
    "emailId":"${MY_EMAIL}",
    "password":"${PE_PASSWORD}",
    "locale":"en-US"},"enabled":false,"roles":[]}
EOF
  )
  _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/users)
  log "create.user=${_admin_user}=|${_test}|"

  _http_body='["ROLE_USER_ADMIN","ROLE_MULTICLUSTER_ADMIN"]'
       _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/users/${_admin_user}/roles)
  log "add.roles ${_http_body}=|${_test}|"
}

function network_configure_shcolo() {

  if [[ ! -z $(acli "net.list" | grep ${NW1_NAME}) ]]; then
    log "IDEMPOTENCY: ${NW1_NAME} network set, skip."
  else
    args_required 'MY_DOMAIN_NAME IPV4_PREFIX AUTH_HOST'

    if [[ ! -z $(acli "net.list" | grep 'Rx-Automation-Network') ]]; then
      log "Remove Rx-Automation-Network..."
      acli "-y net.delete Rx-Automation-Network"
    fi

          NW1_VLAN=${NW2_VLAN}
        NW1_SUBNET=${NW2_SUBNET}
    NW1_DHCP_START=${NW2_DHCP_START}
      NW1_DHCP_END=${NW2_DHCP_END}

    log "Create primary network: Name: ${NW1_NAME}, VLAN: ${NW1_VLAN}, Subnet: ${NW1_SUBNET}, Domain: ${MY_DOMAIN_NAME}, Pool: ${NW1_DHCP_START} to ${NW1_DHCP_END}"
    acli "net.create ${NW1_NAME} vlan=${NW1_VLAN} ip_config=${NW1_SUBNET}"
    acli "net.update_dhcp_dns ${NW1_NAME} servers=${AUTH_HOST},${DNS_SERVERS} domains=${MY_DOMAIN_NAME}"
    acli "net.add_dhcp_pool ${NW1_NAME} start=${NW1_DHCP_START} end=${NW1_DHCP_END}"

    #if [[ ! -z "${NW2_NAME}" ]]; then
    #  log "Create secondary network: Name: ${NW2_NAME}, VLAN: ${NW2_VLAN}, Subnet: ${NW2_SUBNET}, Pool: ${NW2_DHCP_START} to ${NW2_DHCP_END}"
    #  acli "net.create ${NW2_NAME} vlan=${NW2_VLAN} ip_config=${NW2_SUBNET}"
    #  acli "net.update_dhcp_dns ${NW2_NAME} servers=${AUTH_HOST},${DNS_SERVERS} domains=${MY_DOMAIN_NAME}"
    #  acli "net.add_dhcp_pool ${NW2_NAME} start=${NW2_DHCP_START} end=${NW2_DHCP_END}"
    #fi
  fi
}

function pc_upload_manual() {
  # upload PC for sh-colo manually
  PC_SHCOLO_URL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy.tar
  PC_META_SHCOLO_URL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy-metadata.json
  wget -c -O pc-${PC_VERSION}-deploy.tar --progress=dot:mega ${PC_SHCOLO_URL} 
  wget -q ${PC_META_SHCOLO_URL}
  ncli software upload software-type=PRISM_CENTRAL_DEPLOY \
         file-path="`pwd`/${PC_SHCOLO_URL##*/}" \
    meta-file-path="`pwd`/${PC_META_SHCOLO_URL##*/}"

}

function pc_clean_manual() {
  rm -f ${PC_SHCOLO_URL##*/} ${PC_META_SHCOLO_URL##*/}

}

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'MY_EMAIL PE_PASSWORD PC_VERSION'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization

log "Adding key to ${1} VMs..."
ssh_pubkey & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    args_required 'PE_HOST'

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure_shcolo \
    && authentication_source \
    && pe_auth

    if (( $? == 0 )) ; then
      pc_upload_manual

      pc_install \
      && prism_check 'PC' \
      && dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq'

      log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
      log "PE = https://${PE_HOST}:9440"
      log "PC = https://${PC_HOST}:9440"
      
      pc_clean_manual

      finish
    else
      finish
      log "Error 18: in main functional chain, exit!"
      exit 18
    fi
  ;;
  PC | pc )
    . lib.pc.sh
    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' || exit 13

    pc_passwd
    ntnx_cmd # check cli services available?

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    if [[ -z "${PE_HOST}" ]]; then
      pe_determine ${1}
      . global.vars.sh # re-populate PE_HOST dependencies
    fi

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
    && prism_check 'PC'

    # new functions, non-blocking, at the end.
    pc_project
    flow_enable
    pc_admin

    # ntnx_download 'AOS' # function in lib.common.sh

    unset NUCLEI_SERVER NUCLEI_USERNAME NUCLEI_PASSWORD

    if (( $? == 0 )); then
      #dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq' \
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
