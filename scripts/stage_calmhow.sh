#!/bin/bash
# -x
# Dependencies: acli, ncli, dig, jq, sshpass, curl, md5sum, pgrep, wc, tr, pkill
# Please configure according to your needs

function _testDNS {
  local _DNS=$(dig +short @10.21.${MY_HPOC_NUMBER}.40 dc1.${MY_DOMAIN_FQDN})
  if [[ ${_DNS} != "10.21.${MY_HPOC_NUMBER}.40" ]]; then
    return 44
  fi
}

function acli {
  local CMD=$@
	/usr/local/nutanix/bin/acli ${CMD}
  # DEBUG=1 && if [[ ${DEBUG} ]]; then my_log "$@"; fi
}

function PC_Download
{
  if [[ ! -e ${MY_PC_META_URL##*/} ]]; then
    my_log "Retrieving Prism Central metadata ${MY_PC_META_URL} ..."
    Download "${MY_PC_META_URL}"
  fi

  MY_PC_SRC_URL=$(cat ${MY_PC_META_URL##*/} | jq -r .download_url_cdn)

  if (( `pgrep curl | wc --lines | tr -d '[:space:]'` > 0 )); then
    pkill curl
  fi
  my_log "Retrieving Prism Central bits..."
  Download "${MY_PC_SRC_URL}"
}

function PE_Init
{
  if [[ `ncli cluster get-params | grep 'External Data' | \
         awk -F: '{print $2}' | tr -d '[:space:]'` == "10.21.${MY_HPOC_NUMBER}.38" ]]; then
    my_log "IDEMPOTENCY: Data Services IP set, skip."
  else
    my_log "Configure SMTP"
    ncli cluster set-smtp-server address=${SMTP_SERVER_ADDRESS} from-email-address=cluster@nutanix.com port=25

    my_log "Configure NTP"
    ncli cluster add-to-ntp-servers servers=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org

    my_log "Rename default container to ${MY_CONTAINER_NAME}"
    default_container=$(ncli container ls | grep -P '^(?!.*VStore Name).*Name' | cut -d ':' -f 2 | sed s/' '//g | grep '^default-container-')
    ncli container edit name="${default_container}" new-name="${MY_CONTAINER_NAME}"

    my_log "Rename default storage pool to ${MY_SP_NAME}"
    default_sp=$(ncli storagepool ls | grep 'Name' | cut -d ':' -f 2 | sed s/' '//g)
    ncli sp edit name="${default_sp}" new-name="${MY_SP_NAME}"

    my_log "Check if there is a container named ${MY_IMG_CONTAINER_NAME}, if not create one"
    (ncli container ls | grep -P '^(?!.*VStore Name).*Name' | cut -d ':' -f 2 | sed s/' '//g | grep "^${MY_IMG_CONTAINER_NAME}" 2>&1 > /dev/null) \
        && my_log "Container ${MY_IMG_CONTAINER_NAME} exists" \
        || ncli container create name="${MY_IMG_CONTAINER_NAME}" sp-name="${MY_SP_NAME}"

    # Set external IP address:
    #ncli cluster edit-params external-ip-address=10.21.${MY_HPOC_NUMBER}.37

    my_log "Set Data Services IP address to 10.21.${MY_HPOC_NUMBER}.38"
    ncli cluster edit-params external-data-services-ip-address=10.21.${MY_HPOC_NUMBER}.38
  fi
}

function Network_Configure
{
  if [[ ! -z `acli "net.list" | grep ${MY_SECONDARY_NET_NAME}` ]]; then
    my_log "IDEMPOTENCY: ${MY_SECONDARY_NET_NAME} network set, skip"
  else
    my_log "Remove Rx-Automation-Network if it exists..."
    acli "-y net.delete Rx-Automation-Network"

    my_log "Create primary network: Name: ${MY_PRIMARY_NET_NAME}"
    # my_log "VLAN: ${MY_PRIMARY_NET_VLAN}"
    # my_log "Subnet: 10.21.${MY_HPOC_NUMBER}.1/25"
    # my_log "Domain: ${MY_DOMAIN_NAME}"
    # my_log "Pool: 10.21.${MY_HPOC_NUMBER}.50 to 10.21.${MY_HPOC_NUMBER}.125"
    acli "net.create ${MY_PRIMARY_NET_NAME} vlan=${MY_PRIMARY_NET_VLAN} ip_config=10.21.${MY_HPOC_NUMBER}.1/25"
    acli "net.update_dhcp_dns ${MY_PRIMARY_NET_NAME} servers=10.21.${MY_HPOC_NUMBER}.40,10.21.253.10 domains=${MY_DOMAIN_NAME}"
    acli "net.add_dhcp_pool ${MY_PRIMARY_NET_NAME} start=10.21.${MY_HPOC_NUMBER}.50 end=10.21.${MY_HPOC_NUMBER}.125"

    if [[ ${MY_SECONDARY_NET_NAME} ]]; then
      my_log "Create secondary network: Name: ${MY_SECONDARY_NET_NAME}"
      # my_log "VLAN: ${MY_SECONDARY_NET_VLAN}"
      # my_log "Subnet: 10.21.${MY_HPOC_NUMBER}.129/25"
      # my_log "Domain: ${MY_DOMAIN_NAME}"
      # my_log "Pool: 10.21.${MY_HPOC_NUMBER}.132 to 10.21.${MY_HPOC_NUMBER}.253"
      acli "net.create ${MY_SECONDARY_NET_NAME} vlan=${MY_SECONDARY_NET_VLAN} ip_config=10.21.${MY_HPOC_NUMBER}.129/25"
      acli "net.update_dhcp_dns ${MY_SECONDARY_NET_NAME} servers=10.21.${MY_HPOC_NUMBER}.40,10.21.253.10 domains=${MY_DOMAIN_NAME}"
      acli "net.add_dhcp_pool ${MY_SECONDARY_NET_NAME} start=10.21.${MY_HPOC_NUMBER}.132 end=10.21.${MY_HPOC_NUMBER}.253"
    fi
  fi
}

function AuthenticationServer()
{
  if [[ -z ${LDAP_SERVER} ]]; then
    my_log "Error: please provide a choice for authentication server."
    exit 13
  fi

  case "${LDAP_SERVER}" in
    'ActiveDirectory')
      my_log "Manual setup = http://www.nutanixworkshops.com/en/latest/setup/active_directory/active_directory_setup.html"
      ;;
    'AutoDC')
      if (( _testDNS == 0 )); then
        my_log "${LDAP_SERVER}.IDEMPOTENCY: Samba dc1.${MY_DOMAIN_FQDN} set, skip"
      else
        my_log "${LDAP_SERVER}.IDEMPOTENCY failed, no _DNS match for Samba dc1.${MY_DOMAIN_FQDN} in: ${_DNS}"
        my_log "Import ${LDAP_SERVER} image..."

        local  _LOOP=0
        local _SLEEP=${SLEEP}
        local  _TEST=0

# task.list operation_type_list=kVmCreate
# Task UUID                             Parent Task UUID  Component  Sequence-id  Type       Status
# b21efb77-5447-45f9-9d6e-fc3ef6b22e36                    Acropolis  54           kVmCreate  kSucceeded
#
# acli -o json-pretty task.get b21efb77-5447-45f9-9d6e-fc3ef6b22e36
# {
#   "data": {
#     "canceled": false,
#     "cluster_uuid": "00056e27-2f51-7a31-1a72-0cc47ac3b4a0",
#     "complete_time_usecs": "2018-06-09T00:52:11.527367",
#     "component": "Acropolis",
#     "create_time_usecs": "2018-06-09T00:52:11.380946",
#     "deleted": false,
#     "disable_auto_progress_update": true,
#     "entity_list": [
#       {
#         "entity_id": "1dbcb887-c368-4142-97be-ff53417355ad",
#         "entity_type": "kVM"
#       }
#     ],
#     "internal_opaque": "ChIKEB28uIfDaEFCl77/U0FzVa0=",
#     "internal_task": false,
#     "last_updated_time_usecs": "2018-06-09T00:52:11.527367",
#     "local_root_task_uuid": "b21efb77-5447-45f9-9d6e-fc3ef6b22e36",
#     "logical_timestamp": 1,
#     "message": "",
#     "operation_type": "kVmCreate",
#     "percentage_complete": 100,
#     "request": {
#       "arg": {
#         "spec": {
#           "memory_mb": 2048,
#           "name": "STAGING-FAILED-AutoDC",
#           "num_vcpus": 1
#         }
#       },
#       "method_name": "VmCreate"
#     },
#     "requested_state_transition": 20,
#     "response": {
#       "error_code": 0,
#       "ret": {
#         "embedded": "ChAdvLiHw2hBQpe+/1NBc1Wt"
#       }
#     },
#     "sequence_id": 54,
#     "start_time_usecs": "2018-06-09T00:52:11.433001",
#     "status": "kSucceeded",
#     "uuid": "b21efb77-5447-45f9-9d6e-fc3ef6b22e36",
#     "weight": 1000
#   },
#   "error": null,
#   "status": 0
# }

        # while true ; do
        #   (( _LOOP++ ))
        if (( `source /etc/profile.d/nutanix_env.sh && acli image.list | grep ${LDAP_SERVER} | wc --lines` == 0 )); then
          acli image.create ${LDAP_SERVER} \
            container=${MY_IMG_CONTAINER_NAME} \
            image_type=kDiskImage \
            source_url=http://10.21.250.221/images/ahv/techsummit/AutoDC.qcow2 \
            wait=true
        fi

          # if [[ ${_TEST} =~ 'complete' ]]; then
          #   break
          # elif (( ${_LOOP} > ${ATTEMPTS} )); then
          #   acli "vm.create STAGING-FAILED-${LDAP_SERVER}"
          #   my_log "${LDAP_SERVER} failed to upload after ${_LOOP} attempts. This cluster may require manual remediation."
          #   exit 13
          # else
          #   my_log "_TEST ${_LOOP}=${_TEST}: ${LDAP_SERVER} failed. Sleep ${_SLEEP} seconds..."
          #   sleep ${_SLEEP}
          # fi
        # done

        my_log "Create ${LDAP_SERVER} VM based on ${LDAP_SERVER} image"
        acli "vm.create ${LDAP_SERVER} num_vcpus=2 num_cores_per_vcpu=1 memory=2G"
        # vmstat --wide --unit M --active # suggests 2G sufficient, was 4G
        acli "vm.disk_create ${LDAP_SERVER} cdrom=true empty=true"
        acli "vm.disk_create ${LDAP_SERVER} clone_from_image=${LDAP_SERVER}"
        acli "vm.nic_create ${LDAP_SERVER} network=${MY_PRIMARY_NET_NAME} ip=10.21.${MY_HPOC_NUMBER}.40"
        my_log "Power on ${LDAP_SERVER} VM"
        acli "vm.on ${LDAP_SERVER}"

        local _ATTEMPTS=10
         _LOOP=0
        _SLEEP=7

        while true ; do
          (( _LOOP++ ))
          _TEST=$(remote_exec 'SSH' 'LDAP_SERVER' 'systemctl show samba-ad-dc --property=SubState' \
          | tr -d '[:space:]')

          if [[ "${_TEST}" == "SubState=running" ]]; then
            my_log "${LDAP_SERVER} is ready."
            sleep ${_SLEEP}
            break
          elif (( ${_LOOP} > ${_ATTEMPTS} )); then
            my_log "${LDAP_SERVER} VM running: giving up after ${_LOOP} tries."
            acli "-y vm.delete ${LDAP_SERVER}"
            exit 12
          else
            my_log "_TEST ${_LOOP}/${_ATTEMPTS}=|${_TEST}|: sleep ${_SLEEP} seconds..."
            sleep ${_SLEEP}
          fi
        done

        my_log "Create Reverse Lookup Zone on ${LDAP_SERVER} VM"
        _ATTEMPTS=3
            _LOOP=0
        while true ; do
          (( _LOOP++ ))
          remote_exec 'SSH' 'LDAP_SERVER' \
            "samba-tool dns zonecreate dc1 ${MY_HPOC_NUMBER}.21.10.in-addr.arpa && sleep 2 && service samba-ad-dc restart" \
            'OPTIONAL'

          if (( _testDNS == 0 )); then
            my_log "Success."
            break
          elif (( ${_LOOP} > ${_ATTEMPTS} )); then
            my_log "${LDAP_SERVER}: giving up after ${_LOOP} tries."
            acli "-y vm.delete ${LDAP_SERVER}"
            exit 12
          else
            my_log "_TEST ${_LOOP}/${_ATTEMPTS}=|${_TEST}|: sleep ${_SLEEP} seconds..."
            sleep ${_SLEEP}
          fi
        done

      fi
      ;;
    'OpenLDAP')
      my_log "To be documented, see https://drt-it-github-prod-1.eng.nutanix.com/mark-lavi/openldap"
      ;;
  esac
}

function PE_Auth
{
  if [[ -z `ncli authconfig list-directory name=${MY_DOMAIN_NAME} | grep Error` ]]; then
    my_log "IDEMPOTENCY: ${MY_DOMAIN_NAME} directory set, skip"
  else
    my_log "Configure PE external authentication"
    ncli authconfig add-directory \
      directory-type=ACTIVE_DIRECTORY \
      connection-type=LDAP directory-url="${MY_DOMAIN_URL}" \
      domain="${MY_DOMAIN_FQDN}" \
      name="${MY_DOMAIN_NAME}" \
      service-account-username="${MY_DOMAIN_USER}" \
      service-account-password="${MY_DOMAIN_PASS}"

    my_log "Configure PE role map"
    ncli authconfig add-role-mapping \
      role=ROLE_CLUSTER_ADMIN \
      entity-type=group name="${MY_DOMAIN_NAME}" \
      entity-values="${MY_DOMAIN_ADMIN_GROUP}"
  fi
}

function PE_Configure
{
  Check_Prism_API_Up 'PC' 2 10
  if (( $? == 0 )) ; then
    my_log "IDEMPOTENCY: PC API responds, skip"
  else
    my_log "Validate EULA on PE"
    curl ${CURL_POST_OPTS} --user admin:${MY_PE_PASSWORD} -X POST --data '{
      "username": "SE with stage_calmhow.sh",
      "companyName": "Nutanix",
      "jobTitle": "SE"
    }' https://localhost:9440/PrismGateway/services/rest/v1/eulas/accept

    my_log "Disable Pulse in PE"
    curl ${CURL_POST_OPTS} --user admin:${MY_PE_PASSWORD} -X PUT --data '{
      "defaultNutanixEmail": null,
      "emailContactList": null,
      "enable": false,
      "enableDefaultNutanixEmail": false,
      "isPulsePromptNeeded": false,
      "nosVersion": null,
      "remindLater": null,
      "verbosityType": null
    }' https://localhost:9440/PrismGateway/services/rest/v1/pulse

    #echo; my_log "Create PE Banner Login" # TODO: for PC, login banner
    # https://portal.nutanix.com/#/page/docs/details?targetId=Prism-Central-Guide-Prism-v56:mul-welcome-banner-configure-pc-t.html
    # curl ${CURL_POST_OPTS} --user admin:${MY_PE_PASSWORD} -X POST --data \
    #  '{type: "welcome_banner", key: "welcome_banner_status", value: true}' \
    #  https://localhost:9440/PrismGateway/services/rest/v1/application/system_data
    #curl ${CURL_POST_OPTS} --user admin:${MY_PE_PASSWORD} -X POST --data
    #  '{type: "welcome_banner", key: "welcome_banner_content", value: "HPoC '${MY_HPOC_NUMBER}' password = '${MY_PE_PASSWORD}'"}' \
    #  https://localhost:9440/PrismGateway/services/rest/v1/application/system_data
  fi
}

function PC_Init
{
  Check_Prism_API_Up 'PC' 2 10
  if (( $? == 0 )) ; then
    my_log "IDEMPOTENCY: PC API responds, skip."
  else
    my_log "Get NET_UUID,MY_CONTAINER_UUID from cluster: PC_Init dependency."
    MY_NET_UUID=$(acli "net.get ${MY_PRIMARY_NET_NAME}" | grep "uuid" | cut -f 2 -d ':' | xargs)
    my_log "${MY_PRIMARY_NET_NAME} UUID is ${MY_NET_UUID}"
    MY_CONTAINER_UUID=$(ncli container ls name=${MY_CONTAINER_NAME} | grep Uuid | grep -v Pool | cut -f 2 -d ':' | xargs)
    my_log "${MY_CONTAINER_NAME} UUID is ${MY_CONTAINER_UUID}"

    PC_Download

    local _CHECKSUM=$(md5sum ${MY_PC_SRC_URL##*/} | awk '{print $1}')
    if [[ `cat ${MY_PC_META_URL##*/} | jq -r .hex_md5` != ${_CHECKSUM} ]]; then
      my_log "Error: md5sum ${_CHECKSUM} does't match on: ${MY_PC_SRC_URL##*/} removing and exit!"
      rm -f ${MY_PC_SRC_URL##*/}
      exit 2
    else
      my_log "Prism Central downloaded and passed MD5 checksum!"
    fi

    my_log "Prism Central upload..."
    ncli software upload file-path=/home/nutanix/${MY_PC_SRC_URL##*/} \
      meta-file-path=/home/nutanix/${MY_PC_META_URL##*/} \
      software-type=PRISM_CENTRAL_DEPLOY

    MY_PC_RELEASE=$(cat ${MY_PC_META_URL##*/} | jq -r .version_id)

    my_log "Delete PC sources to free CVM space"
    rm ${MY_PC_SRC_URL##*/} ${MY_PC_META_URL##*/}

    my_log "Deploy Prism Central"
    # TODO: Parameterize DNS Servers & add secondary
    # TODO: make scale-out & dynamic, was: 4vCPU/16GB = 17179869184, 8vCPU/40GB = 42949672960
    HTTP_BODY=$(cat <<EOF
{
    "resources": {
        "should_auto_register":true,
        "version":"${MY_PC_VERSION}",
        "pc_vm_list":[{
            "data_disk_size_bytes":536870912000,
            "nic_list":[{
                "network_configuration":{
                    "subnet_mask":"255.255.255.128",
                    "network_uuid":"${MY_NET_UUID}",
                    "default_gateway":"10.21.${MY_HPOC_NUMBER}.1"
                },
                "ip_list":["10.21.${MY_HPOC_NUMBER}.39"]
            }],
            "dns_server_ip_list":["10.21.${MY_HPOC_NUMBER}.40"],
            "container_uuid":"${MY_CONTAINER_UUID}",
            "num_sockets":8,
            "memory_size_bytes":42949672960,
            "vm_name":"Prism Central ${MY_PC_RELEASE}"
        }]
    }
}
EOF
    )
    PCD_TEST=$(curl ${CURL_POST_OPTS} --user admin:${MY_PE_PASSWORD} \
      -X POST --data "${HTTP_BODY}" \
      https://localhost:9440/api/nutanix/v3/prism_central)
    my_log "PCD_TEST=|${PCD_TEST}|"
  fi
}

function PC_Configure {
  local PC_FILES='common.lib.sh stage_calmhow_pc.sh'
  my_log "Send configuration scripts to PC and remove: ${PC_FILES}"
  remote_exec 'scp' 'PC' "${PC_FILES}" && rm -f ${PC_FILES}

  PC_FILES='jq-linux64 sshpass-1.06-2.el7.x86_64.rpm'
  my_log "OPTIONAL: Send binary dependencies to PC: ${PC_FILES}"
  remote_exec 'scp' 'PC' "${PC_FILES}" 'OPTIONAL'

  # Execute that file asynchroneously remotely (script keeps running on CVM in the background)
  my_log "Launch PC configuration script"
  remote_exec 'ssh' 'PC' \
   "LDAP_SERVER=${LDAP_SERVER} MY_DOMAIN_FQDN=${MY_DOMAIN_FQDN} MY_DOMAIN_USER=${MY_DOMAIN_USER} MY_DOMAIN_PASS=${MY_DOMAIN_PASS} MY_PE_PASSWORD=${MY_PE_PASSWORD} MY_PC_VERSION=${MY_PC_VERSION} nohup bash /home/nutanix/stage_calmhow_pc.sh >> stage_calmhow_pc.log 2>&1 &"
  my_log "PC Configuration complete: try Validate Staged Clusters now."
}

#__main()__________

# Source Nutanix environments (for PATH and other things)
. /etc/profile.d/nutanix_env.sh
. common.lib.sh # source common routines, global variables

my_log `basename "$0"`": PID=$$"

CheckArgsExist 'MY_PE_PASSWORD MY_PC_VERSION'

# Derive HPOC number from IP 3rd byte
MY_CVM_IP=$(/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2}')
array=(${MY_CVM_IP//./ })
MY_HPOC_NUMBER=${array[2]}
MY_SP_NAME='SP01'
MY_CONTAINER_NAME='Default'
MY_IMG_CONTAINER_NAME='Images'

LDAP_SERVER='AutoDC'
MY_DOMAIN_FQDN='ntnxlab.local'
MY_DOMAIN_NAME='NTNXLAB'
MY_DOMAIN_USER='administrator@'${MY_DOMAIN_FQDN}
MY_DOMAIN_PASS='nutanix/4u'
MY_DOMAIN_ADMIN_GROUP='SSP Admins'
MY_DOMAIN_URL="ldaps://10.21.${MY_HPOC_NUMBER}.40/"

MY_PRIMARY_NET_NAME='Primary'
MY_PRIMARY_NET_VLAN='0'
MY_SECONDARY_NET_NAME='Secondary'
MY_SECONDARY_NET_VLAN="${MY_HPOC_NUMBER}1" # TODO: check this?
SMTP_SERVER_ADDRESS='nutanix-com.mail.protection.outlook.com'

case ${MY_PC_VERSION} in
  5.6 )
    MY_PC_META_URL='http://10.21.250.221/images/ahv/techsummit/euphrates-5.6-stable-prism_central_metadata.json'
    ;;
  5.7 | 5.7.0.1 )
    MY_PC_META_URL='http://download.nutanix.com/pc/one-click-pc-deployment/5.7.0.1/v1/pc-5.7.0.1-stable-prism_central_metadata.json'
    ;;
  *)
    my_log "Errror: unsupported MY_PC_VERSION=${MY_PC_VERSION}!"
    my_log 'Browse to https://portal.nutanix.com/#/page/releases/prismDetails'
    my_log 'then find: Additional Releases (on lower left side)'
    my_log 'Provide the metadata URL from: PC 1-click deploy from PE'
    ;;
esac

# From this point, we assume:
# IP Range: 10.21.${MY_HPOC_NUMBER}.0/25
# Gateway: 10.21.${MY_HPOC_NUMBER}.1
# DNS: 10.21.253.10,10.21.253.11
# Domain: nutanixdc.local
# DHCP Pool: 10.21.${MY_HPOC_NUMBER}.50 - 10.21.${MY_HPOC_NUMBER}.120
#
# DO NOT CHANGE ANYTHING BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING!!
 ATTEMPTS=40
    SLEEP=60

#Dependencies 'install' 'jq' && PC_Download & #attempt at parallelization

Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' \
&& PE_Init \
&& PE_Configure \
&& Network_Configure \
&& AuthenticationServer \
&& PE_Auth \
&& PC_Init \
&& Check_Prism_API_Up 'PC'
# Some parallelization possible to critical path; not much: would require pre-requestite checks.

if (( $? == 0 )) ; then
  PC_Configure && Dependencies 'remove' 'sshpass' && Dependencies 'remove' 'jq';
  my_log "$0: main: done!_____________________"
  echo
  #my_log "Watching logs on PC..."
  #BUG: Dependencies removed! remote_exec 'ssh' 'PC' "tail -f stage_calmhow_pc.log"
else
  my_log "Error in main functional chain, exit!"
  exit 18
fi
