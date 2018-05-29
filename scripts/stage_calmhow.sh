#!/bin/bash
# -x
# Dependencies: acli, ncli, jq, sshpass, wget, md5sum
# Please configure according to your needs

function PE_Init
{
  if [[ `ncli cluster get-params | grep 'External Data' | \
         awk -F: '{print $2}' | tr -d '[:space:]'` == "10.21.${MY_HPOC_NUMBER}.38" ]]; then
    my_log "[${FUNCNAME[0]}.IDEMPOTENCY]: Data Services IP set, skip"
  else
    my_log "${FUNCNAME[0]}.Configure SMTP"
    ncli cluster set-smtp-server address=${SMTP_SERVER_ADDRESS} from-email-address=cluster@nutanix.com port=25

    my_log "${FUNCNAME[0]}.Configure NTP"
    ncli cluster add-to-ntp-servers servers=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org

    my_log "${FUNCNAME[0]}.Rename default container to ${MY_CONTAINER_NAME}"
    default_container=$(ncli container ls | grep -P '^(?!.*VStore Name).*Name' | cut -d ':' -f 2 | sed s/' '//g | grep '^default-container-')
    ncli container edit name="${default_container}" new-name="${MY_CONTAINER_NAME}"

    my_log "${FUNCNAME[0]}.Rename default storage pool to ${MY_SP_NAME}"
    default_sp=$(ncli storagepool ls | grep 'Name' | cut -d ':' -f 2 | sed s/' '//g)
    ncli sp edit name="${default_sp}" new-name="${MY_SP_NAME}"

    my_log "${FUNCNAME[0]}.Check if there is a container named ${MY_IMG_CONTAINER_NAME}, if not create one"
    (ncli container ls | grep -P '^(?!.*VStore Name).*Name' | cut -d ':' -f 2 | sed s/' '//g | grep "^${MY_IMG_CONTAINER_NAME}" 2>&1 > /dev/null) \
        && my_log "${FUNCNAME[0]}.Container ${MY_IMG_CONTAINER_NAME} exists" \
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
    my_log "[Network_Configure.IDEMPOTENCY]: ${MY_SECONDARY_NET_NAME} network set, skip"
  else
    my_log "Remove Rx-Automation-Network if it exists"
    acli "-y net.delete Rx-Automation-Network"

    my_log "Create primary network:"
    my_log "Name: ${MY_PRIMARY_NET_NAME}"
    my_log "VLAN: ${MY_PRIMARY_NET_VLAN}"
    my_log "Subnet: 10.21.${MY_HPOC_NUMBER}.1/25"
    my_log "Domain: ${MY_DOMAIN_NAME}"
    my_log "Pool: 10.21.${MY_HPOC_NUMBER}.50 to 10.21.${MY_HPOC_NUMBER}.125"
    acli "net.create ${MY_PRIMARY_NET_NAME} vlan=${MY_PRIMARY_NET_VLAN} ip_config=10.21.${MY_HPOC_NUMBER}.1/25"
    acli "net.update_dhcp_dns ${MY_PRIMARY_NET_NAME} servers=10.21.${MY_HPOC_NUMBER}.40,10.21.253.10 domains=${MY_DOMAIN_NAME}"
    acli "net.add_dhcp_pool ${MY_PRIMARY_NET_NAME} start=10.21.${MY_HPOC_NUMBER}.50 end=10.21.${MY_HPOC_NUMBER}.125"

    if [[ ${MY_SECONDARY_NET_NAME} ]]; then
      my_log "Create secondary network:"
      my_log "Name: ${MY_SECONDARY_NET_NAME}"
      my_log "VLAN: ${MY_SECONDARY_NET_VLAN}"
      my_log "Subnet: 10.21.${MY_HPOC_NUMBER}.129/25"
      my_log "Domain: ${MY_DOMAIN_NAME}"
      my_log "Pool: 10.21.${MY_HPOC_NUMBER}.132 to 10.21.${MY_HPOC_NUMBER}.253"
      acli "net.create ${MY_SECONDARY_NET_NAME} vlan=${MY_SECONDARY_NET_VLAN} ip_config=10.21.${MY_HPOC_NUMBER}.129/25"
      acli "net.update_dhcp_dns ${MY_SECONDARY_NET_NAME} servers=10.21.${MY_HPOC_NUMBER}.40,10.21.253.10 domains=${MY_DOMAIN_NAME}"
      acli "net.add_dhcp_pool ${MY_SECONDARY_NET_NAME} start=10.21.${MY_HPOC_NUMBER}.132 end=10.21.${MY_HPOC_NUMBER}.253"
    fi
  fi
}

function AuthenticationServer()
{
  if [[ -z ${1} ]]; then
    my_log "AuthenticationServer Error: please provide a choice. Exitskip."
    exit 13;
  else
    MY_IMAGE=${1}
  fi

  case "${MY_IMAGE}" in
    'ActiveDirectory')
      my_log "Manual setup = http://www.nutanixworkshops.com/en/latest/setup/active_directory/active_directory_setup.html"
      ;;
    'AutoDC')
      if [[ `dig +short @10.21.${MY_HPOC_NUMBER}.40 dc1.ntnxlab.local` == "10.21.${MY_HPOC_NUMBER}.40" ]]; then
        my_log "[AuthenticationServer.${MY_IMAGE}.IDEMPOTENCY]: Samba dc1.ntnxlab.local set, skip"
      else
        my_log "Import ${MY_IMAGE} image..."
        local AUTH_SERVER_CREATE=0;
        local               LOOP=0;
        while true ; do
          (( LOOP++ ))
          AUTH_SERVER_CREATE=$(acli "image.create ${MY_IMAGE} \
            container="${MY_IMG_CONTAINER_NAME}" image_type=kDiskImage \
            source_url=http://10.21.250.221/images/ahv/techsummit/AutoDC.qcow2 wait=true")

          if [[ ${AUTH_SERVER_CREATE} =~ 'complete' ]]; then
            break;
          elif (( ${LOOP} > ${ATTEMPTS} )) ; then
            acli "vm.create STAGING-FAILED-${MY_IMAGE}"
            my_log "${MY_IMAGE} failed to upload after ${LOOP} attempts. This cluster may require manual remediation."
            exit 13;
          else
            my_log "__AUTH_SERVER_CREATE ${LOOP}=${AUTH_SERVER_CREATE}: ${MY_IMAGE} failed. Sleep ${SLEEP} seconds..."
            sleep ${SLEEP};
          fi
        done

        my_log "Create ${MY_IMAGE} VM based on ${MY_IMAGE} image"
        acli "vm.create ${MY_IMAGE} num_vcpus=2 num_cores_per_vcpu=1 memory=2G"
        # vmstat --wide --unit M --active # suggests 2G sufficient, was 4G
        acli "vm.disk_create ${MY_IMAGE} cdrom=true empty=true"
        acli "vm.disk_create ${MY_IMAGE} clone_from_image=${MY_IMAGE}"
        acli "vm.nic_create ${MY_IMAGE} network=${MY_PRIMARY_NET_NAME} ip=10.21.${MY_HPOC_NUMBER}.40"
        my_log "Power on ${MY_IMAGE} VM"
        acli "vm.on ${MY_IMAGE}"

        local AUTH_SERVER_TEST=0; # TODO: candidate for remote_exec
        local             LOOP=0;
        while true ; do
          (( LOOP++ ))
          # TODO: hardcoded p/w
          AUTH_SERVER_TEST=$(sshpass -p nutanix/4u ssh ${SSH_OPTS} \
            root@10.21.${MY_HPOC_NUMBER}.40 "which samba-tool")
          if (( $? > 0 )); then
            echo
          fi

          if [[ ${AUTH_SERVER_TEST} == "/usr/bin/samba-tool" ]]; then
            break;
          elif (( ${LOOP} > ${ATTEMPTS} )) ; then
            my_log "${MY_IMAGE} VM running: giving up after ${LOOP} tries."
            exit 12;
          else
            my_log "__AUTH_SERVER_TEST ${LOOP}=${AUTH_SERVER_TEST}: sleep ${SLEEP} seconds..."
            sleep ${SLEEP};
          fi
        done

        my_log "Create Reverse Lookup Zone on ${MY_IMAGE} VM" # TODO: candidate for remote_exec
        sshpass -p nutanix/4u ssh ${SSH_OPTS} \
          root@10.21.${MY_HPOC_NUMBER}.40 \
          "samba-tool dns zonecreate dc1 ${MY_HPOC_NUMBER}.21.10.in-addr.arpa; service samba-ad-dc restart"
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
    my_log "[PE_Auth.IDEMPOTENCY]: ${MY_DOMAIN_NAME} directory set, skip"
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
  my_log "Get NET_UUID,MY_CONTAINER_UUID from cluster: PC_Init dependency."
  MY_NET_UUID=$(acli "net.get ${MY_PRIMARY_NET_NAME}" | grep "uuid" | cut -f 2 -d ':' | xargs)
  my_log "${MY_PRIMARY_NET_NAME} UUID is ${MY_NET_UUID}"
  MY_CONTAINER_UUID=$(ncli container ls name=${MY_CONTAINER_NAME} | grep Uuid | grep -v Pool | cut -f 2 -d ':' | xargs)
  my_log "${MY_CONTAINER_NAME} UUID is ${MY_CONTAINER_UUID}"

  Check_Prism_API_Up 'PC' 0
  if (( $? == 0 )) ; then
    my_log "[PE_Configure.IDEMPOTENCY]: PC API responds, skip"
  else
    my_log "Validate EULA on PE"
    curl ${CURL_OPTS} -X POST --data '{
      "username": "SE with stage_calmhow.sh",
      "companyName": "Nutanix",
      "jobTitle": "SE"
    }' https://127.0.0.1:9440/PrismGateway/services/rest/v1/eulas/accept

    echo; my_log "Disable Pulse in PE"
    curl ${CURL_OPTS} -X PUT --data '{
      "defaultNutanixEmail": null,
      "emailContactList": null,
      "enable": false,
      "enableDefaultNutanixEmail": false,
      "isPulsePromptNeeded": false,
      "nosVersion": null,
      "remindLater": null,
      "verbosityType": null
    }' https://127.0.0.1:9440/PrismGateway/services/rest/v1/pulse

    #echo; my_log "Create PE Banner Login" # TODO: for PC, login banner
    # https://portal.nutanix.com/#/page/docs/details?targetId=Prism-Central-Guide-Prism-v56:mul-welcome-banner-configure-pc-t.html
    # curl ${CURL_OPTS} -X POST --data \
    #  '{type: "welcome_banner", key: "welcome_banner_status", value: true}' \
    #  https://127.0.0.1:9440/PrismGateway/services/rest/v1/application/system_data
    #curl ${CURL_OPTS} -X POST --data
    #  '{type: "welcome_banner", key: "welcome_banner_content", value: "HPoC '${MY_HPOC_NUMBER}' password = '${MY_PE_PASSWORD}'"}' \
    #  https://127.0.0.1:9440/PrismGateway/services/rest/v1/application/system_data

    echo; my_log "PE_Configure complete"
  fi
}

function PC_Init
{
  Check_Prism_API_Up 'PC' 0
  if (( $? == 0 )) ; then
    my_log "[PC_Init.IDEMPOTENCY]: PC API responds, skip."
  else
    my_log "Download PC-metadata.json"
    wget --continue --no-verbose ${MY_PC_META_URL}

    MY_PC_SRC_URL=$(cat ${MY_PC_META_URL##*/} | jq -r .download_url_cdn)
    MY_PC_RELEASE=$(cat ${MY_PC_META_URL##*/} | jq -r .version_id)
    my_log "Download PC.tar: ${MY_PC_SRC_URL}"
    wget --continue --no-verbose ${MY_PC_SRC_URL}

    if (( $? > 0 )) ; then
      my_log "PC_Init: error, couldn't download PC. Exit."
      exit 1;
    elif [[ `cat ${MY_PC_META_URL##*/} | jq -r .hex_md5` \
            != `md5sum ${MY_PC_SRC_URL##*/} | awk '{print $1}'` ]]; then
      my_log "PC_Init: error, md5sum does't match. Exit."
      exit 1;
    fi

    my_log "Downloaded and passed MD5sum, stage Prism Central upload..."
    ncli software upload file-path=/home/nutanix/${MY_PC_SRC_URL##*/} \
      meta-file-path=/home/nutanix/${MY_PC_META_URL##*/} \
      software-type=PRISM_CENTRAL_DEPLOY

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
    PCD_TEST=$(curl ${CURL_OPTS} -X POST --data "${HTTP_BODY}" \
      https://127.0.0.1:9440/api/nutanix/v3/prism_central)
    my_log "PCD_TEST=|${PCD_TEST}|"
  fi
}

function PC_Configure {
  local PC_FILES='common.lib.sh stage_calmhow_pc.sh'
  my_log "Send configuration scripts to PC and remove: ${PC_FILES}"
  remote_exec 'scp' 'PC' "${PC_FILES}" && rm -f ${PC_FILES}

  # Execute that file asynchroneously remotely (script keeps running on CVM in the background)
  my_log "Launch PC configuration script"
  remote_exec 'ssh' 'PC' \
   "MY_PE_PASSWORD=${MY_PE_PASSWORD} nohup bash /home/nutanix/stage_calmhow_pc.sh >> stage_calmhow_pc.log 2>&1 &"
  my_log "PC Configuration complete: try Validate Staged Clusters now."
}

#__main()__________

# Source Nutanix environments (for PATH and other things)
. /etc/profile.d/nutanix_env.sh
. common.lib.sh # source common routines

my_log `basename "$0"`": __main__: PID=$$"

if [[ -z ${MY_PE_PASSWORD+x} ]]; then
    my_log "MY_PE_PASSWORD not provided, exit"
    exit -1
fi

# Derive HPOC number from IP 3rd byte
#MY_CVM_IP=$(ip addr | grep inet | cut -d ' ' -f 6 | grep ^10.21 | head -n 1)
MY_CVM_IP=$(/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2}')
array=(${MY_CVM_IP//./ })
MY_HPOC_NUMBER=${array[2]}
# HPOC Password (if commented, we assume we get that from environment)
#MY_PE_PASSWORD='nx2TechXXX!'
MY_SP_NAME='SP01'
MY_CONTAINER_NAME='Default'
MY_IMG_CONTAINER_NAME='Images'
MY_DOMAIN_FQDN='ntnxlab.local'
MY_DOMAIN_NAME='NTNXLAB'
MY_DOMAIN_USER='administrator@ntnxlab.local'
MY_DOMAIN_PASS='nutanix/4u'
MY_DOMAIN_ADMIN_GROUP='SSP Admins'
MY_DOMAIN_URL="ldaps://10.21.${MY_HPOC_NUMBER}.40/"
MY_PRIMARY_NET_NAME='Primary'
MY_PRIMARY_NET_VLAN='0'
MY_SECONDARY_NET_NAME='Secondary'
MY_SECONDARY_NET_VLAN="${MY_HPOC_NUMBER}1"
MY_PC_VERSION="5.6"
#MY_PC_SRC_URL='http://10.21.250.221/images/ahv/techsummit/euphrates-5.6-stable-prism_central.tar'
MY_PC_META_URL='http://10.21.250.221/images/ahv/techsummit/euphrates-5.6-stable-prism_central_metadata.json'
# https://portal.nutanix.com/#/page/releases/prismDetails
# > Additional Releases (on lower left side)
# Choose the URLs from: PC 1-click deploy from PE
MY_PC_VERSION="5.7"
MY_PC_META_URL='http://download.nutanix.com/pc/one-click-pc-deployment/5.7.0.1/v1/pc-5.7.0.1-stable-prism_central_metadata.json'
SMTP_SERVER_ADDRESS='nutanix-com.mail.protection.outlook.com'

# From this point, we assume:
# IP Range: 10.21.${MY_HPOC_NUMBER}.0/25
# Gateway: 10.21.${MY_HPOC_NUMBER}.1
# DNS: 10.21.253.10,10.21.253.11
# Domain: nutanixdc.local
# DHCP Pool: 10.21.${MY_HPOC_NUMBER}.50 - 10.21.${MY_HPOC_NUMBER}.120
#
# DO NOT CHANGE ANYTHING BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING!!
 ATTEMPTS=40
CURL_OPTS="${CURL_OPTS} --user admin:${MY_PE_PASSWORD}"
#CURL_OPTS="${CURL_OPTS} --verbose"
    SLEEP=60

Dependencies 'install' \
&& PE_Init \
&& Network_Configure \
&& AuthenticationServer 'AutoDC' \
&& PE_Configure \
&& PE_Auth \
&& PC_Init \
&& Check_Prism_API_Up 'PC'
# Some parallelization possible for critical path above, but not much.

if (( $? == 0 )) ; then
  PC_Configure && Dependencies 'remove';
  my_log "$0: main: done!_____________________"
  echo
  my_log "Watching logs on PC..."
  remote_exec 'ssh' 'PC' "tail -f stage_calmhow_pc.log"
else
  my_log "main:Check_Prism_API_Up: Error, couldn't reach PC, exit."
  exit 18
fi
