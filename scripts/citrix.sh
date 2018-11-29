#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

CheckArgsExist 'MY_EMAIL PE_HOST PE_PASSWORD PC_VERSION'

#Dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization

log "Adding key to ${1} VMs..."
SSH_PubKey & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    log "Configure PE role mapping"
    ncli authconfig add-role-mapping role=ROLE_CLUSTER_ADMIN entity-type=group name="${MY_DOMAIN_NAME}" entity-values="${MY_DOMAIN_ADMIN_GROUP}"

    my_log "Creating Reverse Lookup Zone on DC VM"
    remote_exec 'ssh' 'AUTH_SERVER' "samba-tool dns zonecreate dc1 ${MY_HPOC_NUMBER}.21.10.in-addr.arpa; service samba-ad-dc restart"
    log 'Create custom OUs...'
    remote_exec 'ssh' 'AUTH_SERVER' "apt install ldb-tools -y -q"
    remote_exec 'ssh' 'AUTH_SERVER' "cat << EOF > ous.ldif
dn: OU=Non-PersistentDesktop,DC=NTNXLAB,DC=local
changetype: add
objectClass: top
objectClass: organizationalunit
description: Non-Persistent Desktop OU

dn: OU=PersistentDesktop,DC=NTNXLAB,DC=local
changetype: add
objectClass: top
objectClass: organizationalunit
description: Persistent Desktop OU

dn: OU=XenAppServer,DC=NTNXLAB,DC=local
changetype: add
objectClass: top
objectClass: organizationalunit
description: XenApp Server OU

EOF"
    remote_exec 'ssh' 'AUTH_SERVER' "ldbmodify  -H /var/lib/samba/private/sam.ldb ous.ldif; service samba-ad-dc restart"

    log "Create PE user account XD for MCS Plugin"
    ncli user create user-name=xd user-password=nutanix/4u first-name=XenDesktop last-name=Service email-id=no-reply@nutanix.com
    ncli user grant-cluster-admin-role user-name=xd

    log "Get UUIDs from cluster:"
    MY_NET_UUID=$(acli net.get ${NW1_NAME} | grep "uuid" | cut -f 2 -d ':' | xargs)
    log "${NW1_NAME} UUID is ${MY_NET_UUID}"
    MY_CONTAINER_UUID=$(ncli container ls name=${MY_CONTAINER_NAME} | grep Uuid | grep -v Pool | cut -f 2 -d ':' | xargs)
    log "${MY_CONTAINER_NAME} UUID is ${MY_CONTAINER_UUID}"

    log "Download AFS image from ${MY_AFS_SRC_URL}"
    wget -nv ${MY_AFS_SRC_URL}
    log "Download AFS metadata JSON from ${MY_AFS_META_URL}"
    wget -nv ${MY_AFS_META_URL}
    log "Stage AFS"
    ncli software upload file-path=/home/nutanix/${MY_AFS_SRC_URL##*/} meta-file-path=/home/nutanix/${MY_AFS_META_URL##*/} software-type=FILE_SERVER
    log "Delete AFS sources to free some space"
    rm ${MY_AFS_SRC_URL##*/} ${MY_AFS_META_URL##*/}

    curl -u admin:${PE_PASSWORD} -k -H 'Content-Type: application/json' -X POST https://127.0.0.1:9440/api/nutanix/v3/prism_central -d "${MY_DEPLOY_BODY}"
    log "Waiting for PC deployment to complete (Sleeping 15m)"
    sleep 900
    log "Sending PC configuration script"
    pc_send_file stage_citrixhow_pc.sh

    # Execute that file asynchroneously remotely (script keeps running on CVM in the background)
    log "Launching PC configuration script"
    pc_remote_exec "PE_PASSWORD=${PE_PASSWORD} nohup bash /home/nutanix/stage_citrixhow_pc.sh >> pcconfig.log 2>&1 &"

    Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && authentication_source \
    && pe_auth \
    && pc_init \
    && Check_Prism_API_Up 'PC'

    if (( $? == 0 )) ; then
      pc_configure \
      && Dependencies 'remove' 'sshpass' && Dependencies 'remove' 'jq'

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

    #MY_PC_UPGRADE_URL='http://10.21.250.221/images/ahv/techsummit/nutanix_installer_package_pc-release-euphrates-5.5.0.6-stable-14bd63735db09b1c9babdaaf48d062723137fc46.tar.gz'

    # Set Prism Central Password to Prism Element Password
    # my_log "Setting PC password to PE password"
    # ncli user reset-password user-name="admin" password="${PE_PASSWORD}"

    # Prism Central upgrade
    #my_log "Download PC upgrade image: ${MY_PC_UPGRADE_URL##*/}"
    #wget -nv ${MY_PC_UPGRADE_URL}

    #my_log "Prepare PC upgrade image"
    #tar -xzf ${MY_PC_UPGRADE_URL##*/}
    #rm ${MY_PC_UPGRADE_URL##*/}

    #my_log "Upgrade PC"
    #cd /home/nutanix/install ; ./bin/cluster -i . -p upgrade

    log "PC Configuration complete on `$date`"

    Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' || exit 13

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
    && pc_ui \
    && pc_auth \
    && pc_smtp

    ssp_auth \
    && calm_enable \
    && images \
    && flow_enable \
    && Check_Prism_API_Up 'PC'

    pc_project # TODO:50 pc_project is a new function, non-blocking at end.
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
