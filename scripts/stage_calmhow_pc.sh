#!/bin/bash
# -x
# Dependencies: curl, ncli, nuclei, jq #sshpass (removed, needed for remote)

function PC_LDAP
{
  my_log "Add Directory ${LDAP_SERVER}"
  HTTP_BODY=$(cat <<EOF
  {
    "name":"${LDAP_SERVER}",
    "domain":"ntnxlab.local",
    "directoryUrl":"ldaps://10.21.${MY_HPOC_NUMBER}.40/",
    "directoryType":"ACTIVE_DIRECTORY",
    "connectionType":"LDAP",
    "serviceAccountUsername":"administrator@ntnxlab.local",
    "serviceAccountPassword":"nutanix/4u"
  }
EOF
  )

  DIR_TEST=$(curl ${CURL_POST_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/authconfig/directories)
  my_log "DIR_TEST=|${DIR_TEST}|"

  my_log "Add Roles"
  HTTP_BODY=$(cat <<EOF
  {
    "directoryName":"${LDAP_SERVER}",
    "role":"ROLE_CLUSTER_ADMIN",
    "entityType":"GROUP",
    "entityValues":["SSP Admins"]
  }
EOF
  )
  ROLE_TEST=$(curl ${CURL_POST_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/authconfig/directories/${LDAP_SERVER}/role_mappings)
  my_log "Cluster Admin=SSP Admins, ROLE_TEST=|${ROLE_TEST}|"
}

function SSP_Auth {
  my_log "Find ${LDAP_SERVER} uuid"
  HTTP_BODY=$(cat <<EOF
  {
    "kind": "directory_service"
  }
EOF
  )
  LDAP_UUID=$(PATH=${PATH}:${HOME}; curl ${CURL_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/api/nutanix/v3/directory_services/list \
    | jq -r .entities[0].metadata.uuid)
  my_log "LDAP_UUID=|${LDAP_UUID}|"

  # TODO: test ldap connection

  my_log "Connect SSP Authentication (spec-ssp-authrole.json)..."
  HTTP_BODY=$(cat <<EOF
  {
    "spec": {
      "name": "${LDAP_SERVER}",
      "resources": {
        "admin_group_reference_list": [
          {
            "name": "cn=ssp developers,cn=users,dc=ntnxlab,dc=local",
            "uuid": "3933a846-fe73-4387-bb39-7d66f222c844",
            "kind": "user_group"
          }
        ],
        "service_account": {
          "username": "administrator@ntnxlab.local",
          "password": "nutanix/4u"
        },
        "url": "ldaps://10.21.${MY_HPOC_NUMBER}.40/",
        "directory_type": "ACTIVE_DIRECTORY",
        "admin_user_reference_list": [],
        "domain_name": "ntnxlab.local"
      }
    },
    "metadata": {
      "kind": "directory_service",
      "spec_version": 0,
      "uuid": "${LDAP_UUID}",
      "categories": {}
    },
    "api_version": "3.1.0"
  }
EOF
  )
  SSP_CONNECT=$(curl ${CURL_POST_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X PUT --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/api/nutanix/v3/directory_services/${LDAP_UUID})
  my_log "SSP_CONNECT=|${SSP_CONNECT}|"

  # TODO: SSP Admin assignment, cluster, networks (default project?) = spec-project-config.json
}

function CALM
{
  my_log "Enable Nutanix Calm..."
  HTTP_BODY=$(cat <<EOF
  {
    "state": "ENABLE",
    "enable_nutanix_apps": true
  }
EOF
  )
  CALM=$(curl ${CURL_POST_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/api/nutanix/v3/services/nucalm)
  my_log "CALM=|${CALM}|"

  if [[ ${MY_PC_VERSION} == '5.7.0.1' ]]; then
    echo https://portal.nutanix.com/#/page/kbs/details?targetId=kA00e000000LJ1aCAG
    echo modify_firewall -o open -i eth0 -p 8090 -a
    remote_exec 'PE' 'SSH' 'allssh "cat /srv/pillar/iptables.sls |grep 8090"'
    remote_exec 'PE' 'SSH' 'allssh sudo cat /home/docker/epsilon/conf/karan_hosts.txt'
  fi
}

function PC_UI
{
  HTTP_BODY=$(cat <<EOF
  {
    "type":"welcome_banner",
    "key":"disable_video",
    "value": true}
  }
EOF
  )
  UI_TEST=$(curl ${CURL_HTTP_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/application/system_data)
  my_log "welcome_banner UI_TEST=|${UI_TEST}|"

  HTTP_BODY=$(cat <<EOF
  {
    "type":"disable_2048",
    "key":"disable_video",
    "value": true}
  }
EOF
  )
  UI_TEST=$(curl ${CURL_HTTP_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/application/system_data)
  my_log "disable_2048 UI_TEST=|${UI_TEST}|"

  HTTP_BODY=$(cat <<EOF
  {
    "type":"UI_CONFIG",
    "key":"autoLogoutTime",
    "value": 3600000}
  }
EOF
  )
  UI_TEST=$(curl ${CURL_HTTP_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/application/user_data)
  my_log "autoLogoutTime UI_TEST=|${UI_TEST}|"

  HTTP_BODY=$(cat <<EOF
  {
    "type":"UI_CONFIG",
    "key":"autoLogoutGlobal",
    "value": 7200000}
  }
EOF
  )
  UI_TEST=$(curl ${CURL_HTTP_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/application/system_data)
  my_log "autoLogoutGlobal UI_TEST=|${UI_TEST}|"

  HTTP_BODY=$(cat <<EOF
  {
    "type":"UI_CONFIG",
    "key":"autoLogoutOverride",
    "value": 0}
  }
EOF
  )
  UI_TEST=$(curl ${CURL_HTTP_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/application/system_data)
  my_log "autoLogoutOverride UI_TEST=|${UI_TEST}|"

  HTTP_BODY=$(cat <<EOF
  {
    "type":"UI_CONFIG",
    "key":"welcome_banner",
    "value": "PoC ${MY_HPOC_NUMBER}"}
  }
EOF
  )
  UI_TEST=$(curl ${CURL_HTTP_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/application/system_data)
  my_log "welcome_banner UI_TEST=|${UI_TEST}|"
}

function PC_Init
{
  # TODO: PC_Init depends on ncli
  # TODO: PC_Init: NCLI, type 'cluster get-smtp-server' config
  # TODO: resolve/ack issues for cleanliness?

  local OLD_PW='nutanix/4u'
  my_log "Reset PC password to PE password, must be done by nci@PC, not API or on PE"
#  sshpass -p ${OLD_PW} ssh ${SSH_OPTS} nutanix@10.21.${MY_HPOC_NUMBER}.39 \
#   'source /etc/profile.d/nutanix_env.sh && ncli user reset-password user-name=admin password='${MY_PE_PASSWORD}
  ncli user reset-password user-name=admin password=${MY_PE_PASSWORD}
  if (( $? != 0 )) ; then
   my_log "Password not reset, error: $?.";# Exit."   exit 10;
  fi
#   HTTP_BODY=$(cat <<EOF
# {
#   "oldPassword": "${OLD_PW}",
#   "newPassword": "${MY_PE_PASSWORD}"
# }
# EOF
#   )
#   PC_TEST=$(curl ${CURL_HTTP_OPTS} --user "admin:${OLD_PW}" -X POST --data "${HTTP_BODY}" \
#     https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/utils/change_default_system_password)
#   my_log "cURL reset password PC_TEST=${PC_TEST}"

  my_log "Configure NTP on PC"
  ncli cluster add-to-ntp-servers servers=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org

  my_log "Validate EULA on PC"
  EULA_TEST=$(curl ${CURL_HTTP_OPTS} --user admin:${MY_PE_PASSWORD} -X POST -d '{
      "username": "SE",
      "companyName": "NTNX",
      "jobTitle": "SE"
  }' https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/eulas/accept)
  my_log "EULA_TEST=|${EULA_TEST}|"

  my_log "Disable Pulse on PC"
  PULSE_TEST=$(curl ${CURL_HTTP_OPTS} --user admin:${MY_PE_PASSWORD} -X PUT -d '{
      "emailContactList":null,
      "enable":false,
      "verbosityType":null,
      "enableDefaultNutanixEmail":false,
      "defaultNutanixEmail":null,
      "nosVersion":null,
      "isPulsePromptNeeded":false,
      "remindLater":null
  }' https://10.21.${MY_HPOC_NUMBER}.39:9440/PrismGateway/services/rest/v1/pulse)
  my_log "PULSE_TEST=|${PULSE_TEST}|"

  # Prism Central upgrade
  #my_log "Download PC upgrade image: ${MY_PC_UPGRADE_URL##*/}"
  #cd /home/nutanix/install ; ./bin/cluster -i . -p upgrade
}

function Images
{
  # TOFIX: https://jira.nutanix.com/browse/FEAT-7112
  # https://jira.nutanix.com/browse/ENG-115366
  # once PC image service takes control, rejects PE image uploads. Move to PC, not critical path.
  # KB 4892 = https://portal.nutanix.com/#/page/kbs/details?targetId=kA00e000000XePyCAK
  # v3 API = http://developer.nutanix.com/reference/prism_central/v3/#images two steps:
  # 1. POST /images to create image metadata and get UUID
    #   {
    #   "spec": {
    #     "name": "string",
    #     "resources": {
    #       "image_type": "string",
    #       "checksum": {
    #         "checksum_algorithm": "string",
    #         "checksum_value": "string"
    #       },
    #       "source_uri": "string",
    #       "version": {
    #         "product_version": "string",
    #         "product_name": "string"
    #       },
    #       "architecture": "string"
    #     },
    #     "description": "string"
    #   },
    #   "api_version": "3.1.0",
    #   "metadata": {
    #     "last_update_time": "2018-05-20T16:45:50.090Z",
    #     "kind": "image",
    #     "uuid": "string",
    #     "project_reference": {
    #       "kind": "project",
    #       "name": "string",
    #       "uuid": "string"
    #     },
    #     "spec_version": 0,
    #     "creation_time": "2018-05-20T16:45:50.090Z",
    #     "spec_hash": "string",
    #     "owner_reference": {
    #       "kind": "user",
    #       "name": "string",
    #       "uuid": "string"
    #     },
    #     "categories": {},
    #     "name": "string"
    #   }
    # }
  # 2.  PUT images/uuid/file: upload uuid, body, checksum and checksum type: sha1, sha256
  # or nuclei, only on PCVM or in container
  # nuclei image.create name=CentOS7-04282018.qcow2 source_uri=http://10.21.250.221/images/ahv/techsummit/CentOS7-04282018.qcow2
  #CentOS7-04282018.qcow2  b6d95c0d-2d8d-4a26-b16a-8c1c1c84b62b  RUNNING
  # nuclei image.create name=Windows2012R2-04282018.qcow2 source_uri=http://10.21.250.221/images/ahv/techsummit/Windows2012R2-04282018.qcow2
  #Windows2012R2-04282018.qcow2  28753cfc-2203-448e-9020-7c38466e39ab  RUNNING
  # Takes a while to show up in: nuclei image.list, state = COMPLETE
  # image.list Name UUID State
  # https://jira.nutanix.com/browse/ENG-78322 <nuclei>
    # app_blueprint
    # availability_zone
    # available_extension
    # available_extension_images
    # catalog_item
    # category
    # certificate
    # changed_regions
    # client_auth
    # cloud_credentials
    # cluster
    # container
    # core                          CLI control.
    # diag                          Diagnostic tools.
    # directory_service
    # disk
    # docker_image
    # docker_registry
    # exit                          Exits the CLI.
    # extension
    # get                           Gets the current value of the given configuration options.
    # help                          Provides help text for the named object.
    # host
    # image
    # network_function_chain
    # network_security_rule
    # oauth_client
    # oauth_token
    # permission
    # project
    # protection_rule
    # quit                          Exits the CLI.
    # recovery_plan
    # recovery_plan_job
    # remote_connection
    # report_config
    # report_instance
    # role
    # set                           Sets the value of the given configuration options.
    # ssh_user
    # subnet
    # user
    # version                       NuCLEI Version Information.
    # virtual_network
    # vm
    # vm_backup
    # vm_snapshot
    # volume_group
    # volume_group_backup
    # volume_group_snapshot
    # webhook
  local OLD_PW='nutanix/4u'
  # TODO: Images depends on nuclei

  my_log "CentOS7-04282018.qcow2 image..."
#  sshpass -p ${OLD_PW} ssh ${SSH_OPTS} nutanix@10.21.${MY_HPOC_NUMBER}.39 \
#   "source /etc/profile.d/nutanix_env.sh \
#   && nuclei image.create name=CentOS7-04282018.qcow2 \
  nuclei image.create name=CentOS7-04282018.qcow2 \
     description='stage_calmhow_pc' \
     source_uri=http://10.21.250.221/images/ahv/techsummit/CentOS7-04282018.qcow2
  if (( $? != 0 )) ; then
   my_log "Image submission error: $?.";# Exit."   exit 10;
  fi

  my_log "Windows2012R2-04282018.qcow2 image..."
#  sshpass -p ${OLD_PW} ssh ${SSH_OPTS} nutanix@10.21.${MY_HPOC_NUMBER}.39 \
#   "source /etc/profile.d/nutanix_env.sh \
#   && nuclei image.create name=Windows2012R2-04282018.qcow2 \
  nuclei image.create name=Windows2012R2-04282018.qcow2 \
     description='stage_calmhow_pc' \
     source_uri=http://10.21.250.221/images/ahv/techsummit/Windows2012R2-04282018.qcow2
  if (( $? != 0 )) ; then
   my_log "Image submission error: $?.";# Exit."   exit 10;
  fi

  # MY_IMAGE="CentOS"
  # retries=1
  # echo; my_log "Import ${MY_IMAGE} image"
  # until [[ $(acli image.create ${MY_IMAGE} container="${MY_IMG_CONTAINER_NAME}" image_type=kDiskImage source_url=http://10.21.250.221/images/ahv/techsummit/CentOS7-04282018.qcow2 wait=true) =~ "complete" ]]; do
  #   # acli image.create CentOS container="Images" image_type=kDiskImage source_url=http://10.21.250.221/images/ahv/CentOSv2.qcow2 wait=true
  #   let retries++
  #   if [ $retries -gt 5 ]; then
  #     my_log "${MY_IMAGE} failed to upload after 5 attempts. This cluster may require manual remediation."
  #     acli vm.create STAGING-FAILED-${MY_IMAGE}
  #     break
  #   fi
  #   my_log "acli image.create ${MY_IMAGE} FAILED. Retry upload (${retries} of 5)..."
  #   sleep 5
  # done
  #
  # MY_IMAGE="Windows2012"
  # retries=1
  # echo; my_log "Import ${MY_IMAGE} image"
  # until [[ $(acli image.create ${MY_IMAGE} container="${MY_IMG_CONTAINER_NAME}" image_type=kDiskImage source_url=http://10.21.250.221/images/ahv/techsummit/Windows2012R2-04282018.qcow2 wait=true) =~ "complete" ]]; do
  #   let retries++
  #   if [ $retries -gt 5 ]; then
  #     my_log "${MY_IMAGE} failed to upload after 5 attempts. This cluster may require manual remediation."
  #     acli vm.create STAGING-FAILED-${MY_IMAGE}
  #     break
  #   fi
  #   my_log "acli image.create ${MY_IMAGE} FAILED. Retry upload (${retries} of 5)..."
  #   sleep 5
  # done

  # Remove existing VMs, if any (Mark says: unlikely for a new cluster)
  # my_log "Removing \"Windows 2012\" VM if it exists"
  # acli -y vm.delete Windows\ 2012\ VM delete_snapshots=true
  # my_log "Removing \"Windows 10\" VM if it exists"
  # acli -y vm.delete Windows\ 10\ VM delete_snapshots=true
  # my_log "Removing \"CentOS\" VM if it exists"
  # acli -y vm.delete CentOS\ VM delete_snapshots=true
}

#__main()____________

# Source Nutanix environments (for PATH and other things such as ncli)
. /etc/profile.d/nutanix_env.sh
. common.lib.sh

my_log `basename "$0"`": __main__: PID=$$"

if [[ -z ${MY_PE_PASSWORD} ]]; then
  my_log "Error: MY_PE_PASSWORD environment variable not provided, exit."
  exit 10;
fi
if [[ -z ${MY_PC_VERSION} ]]; then
  my_log "Error: MY_PC_VERSION not provided, exit."
  exit -1
fi
if [[ -z ${MY_HPOC_NUMBER} ]]; then
  # Derive HPOC number from IP 3rd byte
  #MY_CVM_IP=$(ip addr | grep inet | cut -d ' ' -f 6 | grep ^10.21 | head -n 1)
  MY_CVM_IP=$(/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2}')
  array=(${MY_CVM_IP//./ })
  MY_HPOC_NUMBER=${array[2]}
fi

   ATTEMPTS=2
#  CURL_OPTS="${CURL_OPTS} --verbose"
LDAP_SERVER='AutoDC'
      SLEEP=10

Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq'\
&& PC_Init \
&& PC_UI \
&& PC_LDAP \
&& SSP_Auth \
&& CALM \
&& Images \
&& Check_Prism_API_Up 'PC'

if (( $? == 0 )) ; then
  Dependencies 'remove' 'sshpass' && Dependencies 'remove' 'jq';
  my_log "$0: main: done!_____________________"
  echo
else
  my_log "Error: failed to reach cluster PE, exit."
  exit 19
fi
