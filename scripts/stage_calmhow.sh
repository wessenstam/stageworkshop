#!/bin/bash
# -x
# Dependencies: acli, ncli, jq, sshpass, wget, md5sum
# Please configure according to your needs

function Stage1
{
  if [[ `ncli cluster get-smtp-server | grep -v From | grep Address \
      | awk -F: '{print $2}' | tr -d '[:space:]'` == "${SMTP_SERVER_ADDRESS}" ]]; then
    my_log "[Stage1.IDEMPOTENCY]: SMTP already set, skipping!"
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
        && echo "Container ${MY_IMG_CONTAINER_NAME} already exists" \
        || ncli container create name="${MY_IMG_CONTAINER_NAME}" sp-name="${MY_SP_NAME}"

    # Set external IP address:
    #ncli cluster edit-params external-ip-address=10.21.${MY_HPOC_NUMBER}.37

    my_log "Set Data Services IP address to 10.21.${MY_HPOC_NUMBER}.38"
    ncli cluster edit-params external-data-services-ip-address=10.21.${MY_HPOC_NUMBER}.38
  fi
}

function Networking
{
  if [[ ! -z `acli net.list | grep Primary` ]]; then
    my_log "[Networking.IDEMPOTENCY]: Primary network set, skipping!"
  else
    my_log "Removing Rx-Automation-Network if it exists"
    acli -y net.delete Rx-Automation-Network

    my_log "Create primary network:"
    my_log "Name: ${MY_PRIMARY_NET_NAME}"
    my_log "VLAN: ${MY_PRIMARY_NET_VLAN}"
    my_log "Subnet: 10.21.${MY_HPOC_NUMBER}.1/25"
    my_log "Domain: ${MY_DOMAIN_NAME}"
    my_log "Pool: 10.21.${MY_HPOC_NUMBER}.50 to 10.21.${MY_HPOC_NUMBER}.125"
    acli net.create ${MY_PRIMARY_NET_NAME} vlan=${MY_PRIMARY_NET_VLAN} ip_config=10.21.${MY_HPOC_NUMBER}.1/25
    acli net.update_dhcp_dns ${MY_PRIMARY_NET_NAME} servers=10.21.${MY_HPOC_NUMBER}.40,10.21.253.10 domains=${MY_DOMAIN_NAME}
    acli net.add_dhcp_pool ${MY_PRIMARY_NET_NAME} start=10.21.${MY_HPOC_NUMBER}.50 end=10.21.${MY_HPOC_NUMBER}.125

    if [[ ${MY_SECONDARY_NET_NAME} ]]; then
      my_log "Create secondary network:"
      my_log "Name: ${MY_SECONDARY_NET_NAME}"
      my_log "VLAN: ${MY_SECONDARY_NET_VLAN}"
      my_log "Subnet: 10.21.${MY_HPOC_NUMBER}.129/25"
      my_log "Domain: ${MY_DOMAIN_NAME}"
      my_log "Pool: 10.21.${MY_HPOC_NUMBER}.132 to 10.21.${MY_HPOC_NUMBER}.253"
      acli net.create ${MY_SECONDARY_NET_NAME} vlan=${MY_SECONDARY_NET_VLAN} ip_config=10.21.${MY_HPOC_NUMBER}.129/25
      acli net.update_dhcp_dns ${MY_SECONDARY_NET_NAME} servers=10.21.${MY_HPOC_NUMBER}.40,10.21.253.10 domains=${MY_DOMAIN_NAME}
      acli net.add_dhcp_pool ${MY_SECONDARY_NET_NAME} start=10.21.${MY_HPOC_NUMBER}.132 end=10.21.${MY_HPOC_NUMBER}.253
    fi
  fi
}

function AuthenticationServer()
{
  if [[ -z ${1} ]]; then
    echo "AuthenticationServer Error: please provide a choice."
    exit 13;
  else
    MY_IMAGE=${1}
  fi

  case "${MY_IMAGE}" in
    'ActiveDirectory')
      echo "Manual setup = http://www.nutanixworkshops.com/en/latest/setup/active_directory/active_directory_setup.html"
      ;;
    'AutoDC')
      if [[ -z $(ncli vm list name=${MY_IMAGE} | grep '\[None\]') ]]; then
        # TODO: weak detection, conditional on text API.
        my_log "[AuthenticationServer.IDEMPOTENCY]: VM ${MY_IMAGE} exists, skipping!"
      else
        retries=1
        my_log "Importing ${MY_IMAGE} image..."
        until [[ $(acli image.create ${MY_IMAGE} \
          container="${MY_IMG_CONTAINER_NAME}" image_type=kDiskImage \
          source_url=http://10.21.250.221/images/ahv/techsummit/AutoDC.qcow2 wait=true) =~ "complete" ]]; do

          let retries++
          if [ $retries -gt 5 ]; then
            my_log "${MY_IMAGE} failed to upload after 5 attempts. This cluster may require manual remediation."
            acli vm.create STAGING-FAILED-${MY_IMAGE}
            break
          fi
          my_log "acli image.create ${MY_IMAGE} FAILED. Retrying upload (${retries} of 5)..."
          sleep 5
        done

        my_log "Create ${MY_IMAGE} VM based on ${MY_IMAGE} image"
        acli vm.create ${MY_IMAGE} num_vcpus=2 num_cores_per_vcpu=1 memory=2G
        # vmstat --wide --unit M --active # suggests 2G sufficient, was 4G
        acli vm.disk_create ${MY_IMAGE} cdrom=true empty=true
        acli vm.disk_create ${MY_IMAGE} clone_from_image=${MY_IMAGE}
        acli vm.nic_create ${MY_IMAGE} network=${MY_PRIMARY_NET_NAME} ip=10.21.${MY_HPOC_NUMBER}.40
        my_log "Power on ${MY_IMAGE} VM"
        acli vm.on ${MY_IMAGE}

        LOOP=0;
        DC_TEST=0;
        while [[ ${DC_TEST} != "/usr/bin/samba-tool" ]]; do
          ((LOOP++))
          if (( ${LOOP} > ${ATTEMPTS} )) ; then
            my_log "${MY_IMAGE} VM stated: giving up after ${LOOP} tries."
            exit 12;
          fi

          DC_TEST=$(sshpass -p nutanix/4u ssh ${SSH_OPTS} \
            root@10.21.${MY_HPOC_NUMBER}.40 "which samba-tool")

          echo -e "\n__DC_TEST ${LOOP}=${DC_TEST}: sleeping ${SLEEP} seconds..."
          sleep ${SLEEP};
        done

        my_log "Creating Reverse Lookup Zone on ${MY_IMAGE} VM"
        sshpass -p nutanix/4u ssh ${SSH_OPTS} \
          root@10.21.${MY_HPOC_NUMBER}.40 \
          "samba-tool dns zonecreate dc1 ${MY_HPOC_NUMBER}.21.10.in-addr.arpa; service samba-ad-dc restart"
      fi
      ;;
    'OpenLDAP')
      echo "To be documented, see https://drt-it-github-prod-1.eng.nutanix.com/mark-lavi/openldap"
      ;;
  esac
}

function PE_Auth
{
  if [[ -z `ncli authconfig list-directory name=${MY_DOMAIN_NAME} | grep Error` ]]; then
    my_log "[PE_Auth.IDEMPOTENCY]: ${MY_DOMAIN_NAME} directory already set, skipping!"
  else
    my_log "Configure PE external authentication"
    ncli authconfig add-directory \
      directory-type=ACTIVE_DIRECTORY \
      connection-type=LDAP directory-url="${MY_DOMAIN_URL}" \
      domain="${MY_DOMAIN_FQDN}" \
      name="${MY_DOMAIN_NAME}" \
      service-account-username="${MY_DOMAIN_USER}" \
      service-account-password="${MY_DOMAIN_PASS}"

    my_log "Configure PE role mapping"
    ncli authconfig add-role-mapping \
      role=ROLE_CLUSTER_ADMIN \
      entity-type=group name="${MY_DOMAIN_NAME}" \
      entity-values="${MY_DOMAIN_ADMIN_GROUP}"
  fi
}

function PE_Configuration
{
  PC_TEST=$(curl ${CURL_OPTS} -X POST --data "${HTTP_BODY}" \
   https://10.21.${MY_HPOC_NUMBER}.39:9440/api/nutanix/v3/clusters/list \
   | tr -d \") # wonderful addition of "" around HTTP status code by cURL

  if (( ${PC_TEST} == 200 )) ; then
    my_log "[PE_Configuration.IDEMPOTENCY]: PC API responds, skipping!"
  else
    my_log "Get UUIDs from cluster:"
    MY_NET_UUID=$(acli net.get ${MY_PRIMARY_NET_NAME} | grep "uuid" | cut -f 2 -d ':' | xargs)
    my_log "${MY_PRIMARY_NET_NAME} UUID is ${MY_NET_UUID}"
    MY_CONTAINER_UUID=$(ncli container ls name=${MY_CONTAINER_NAME} | grep Uuid | grep -v Pool | cut -f 2 -d ':' | xargs)
    my_log "${MY_CONTAINER_NAME} UUID is ${MY_CONTAINER_UUID}"

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

    echo; my_log "PE_Configuration complete"
  fi
}

function PC_Init
{
  PC_TEST=$(curl ${CURL_OPTS} -X POST --data "${HTTP_BODY}" \
   https://10.21.${MY_HPOC_NUMBER}.39:9440/api/nutanix/v3/clusters/list \
   | tr -d \") # wonderful addition of "" around HTTP status code by cURL

  if (( ${PC_TEST} == 200 )) ; then
    my_log "[PC_Init.IDEMPOTENCY]: PC API responds, skipping!"
  else
    my_log "Download Prism Central metadata JSON"
    wget --continue --no-verbose ${MY_PC_META_URL}

    MY_PC_SRC_URL=$(cat ${MY_PC_META_URL##*/} | jq -r .download_url_cdn)
    MY_PC_RELEASE=$(cat ${MY_PC_META_URL##*/} | jq -r .version_id)
    my_log "Download Prism Central tarball: ${MY_PC_SRC_URL}"
    wget --continue --no-verbose ${MY_PC_SRC_URL}

    if (( $? > 0 )) ; then
      my_log "PC_Init: error, couldn't download PC. Exiting."
      exit 1;
    elif [[ `cat ${MY_PC_META_URL##*/} | jq -r .hex_md5` \
         != `md5sum ${MY_PC_SRC_URL##*/} | awk '{print $1}'` ]; then
      my_log "PC_Init: error, md5sum does't match! Exiting."
      exit 1;
    fi

    my_log "Downloaded and passed MD5sum, staging Prism Central upload..."
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

function PC_API_Up
{
  my_log "Waiting for PC deployment to complete..."

       LOOP=0;
    PC_TEST=0;
  HTTP_BODY=$(cat <<EOF
{
  "kind": "cluster"
}
EOF
  )

  while (( LOOP++ )) ; do

    PC_TEST=$(curl ${CURL_OPTS} -X POST --data "${HTTP_BODY}" \
     https://10.21.${MY_HPOC_NUMBER}.39:9440/api/nutanix/v3/clusters/list \
     | tr -d \") # wonderful addition of "" around HTTP status code by cURL

    if (( ${PC_TEST} == 200 )) ; then
      break;
    elif (( ${LOOP} > ${ATTEMPTS} )) ; then
      echo "Giving up after ${LOOP} tries."
      exit 11;
    else
      echo -e "\n__PC_TEST ${LOOP}=${PC_TEST}: sleeping ${SLEEP} seconds..."
      sleep ${SLEEP};
    fi

  done
  # if [[ ${PCTEST} != "200" ]]; then
  #   echo -e "\e[1;31m${MY_PE_HOST} - Prism Central staging FAILED\e[0m"
  #   echo ${MY_PE_HOST} - Review logs at ${MY_PE_HOST}:/home/nutanix/stage_calmhow.log \
  #    and 10.21.${MY_HPOC_NUMBER}.39:/home/nutanix/stage_calmhow_pc.log
  # elif [[ $(acli vm.list) =~ "STAGING-FAILED" ]]; then
  #   echo -e "\e[1;31m${MY_PE_HOST} - Image staging FAILED\e[0m"
  #   echo ${MY_PE_HOST} - Review log at ${MY_PE_HOST}:stage_calmhow.log
  # fi
  my_log "PC_API_Up: successful!"

  PC_FILES='common.lib.sh stage_calmhow_pc.sh'
  my_log "Send configuration scripts to PC and remove: ${PC_FILES}"
  sshpass -p 'nutanix/4u' scp ${SSH_OPTS} ${PC_FILES} nutanix@10.21.${MY_HPOC_NUMBER}.39: \
   && rm -f ${PC_FILES};

  # Execute that file asynchroneously remotely (script keeps running on CVM in the background)
  my_log "Launching PC configuration script"
  sshpass -p 'nutanix/4u' ssh ${SSH_OPTS} nutanix@10.21.${MY_HPOC_NUMBER}.39 \
   "MY_PE_PASSWORD=${MY_PE_PASSWORD} nohup bash /home/nutanix/stage_calmhow_pc.sh >> stage_calmhow_pc.log 2>&1 &"
  my_log "PC Configuration complete: try Validate Staged Clusters now."

}

#__main()__________

# Source Nutanix environments (for PATH and other things)
. /etc/profile.d/nutanix_env.sh
. common.lib.sh # source common routines

MY_SCRIPT_NAME=`basename "$0"`
my_log "__main(${MY_SCRIPT_NAME})__: PID=$$"

if [[ -z ${MY_PE_PASSWORD+x} ]]; then
    my_log "MY_PE_PASSWORD not provided, exiting"
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
    SLEEP=10

Dependencies 'install';

Stage1 && Networking && AuthenticationServer 'AutoDC' \
&& PE_Configuration && PE_Auth \
&& PC_Init && PC_API_Up \
&& Dependencies 'remove';
# Some parallelization possible for critical path above, but not much.
# Image uploads moved to stage_calmhow_pc
