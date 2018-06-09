#!/bin/bash
# -x
# Dependencies: curl, ncli, nuclei, jq #sshpass (removed, needed for remote)

function PC_LDAP
{ # TODO: configure case for each authentication server type?
  if [[ -z ${LDAP_SERVER} || -z ${MY_DOMAIN_FQDN} || -z ${MY_DOMAIN_USER} || -z ${MY_DOMAIN_PASS} ]]; then
    my_log "Error: missing LDAP_SERVER, MY_DOMAIN_[FQDN|USER|PASS] for authentication."
    exit 21
  fi

  my_log "Add Directory ${LDAP_SERVER}"
  HTTP_BODY=$(cat <<EOF
  {
    "name":"${LDAP_SERVER}",
    "domain":"${MY_DOMAIN_FQDN}",
    "directoryUrl":"ldaps://10.21.${MY_HPOC_NUMBER}.40/",
    "directoryType":"ACTIVE_DIRECTORY",
    "connectionType":"LDAP",
    "serviceAccountUsername":"${MY_DOMAIN_USER}",
    "serviceAccountPassword":"${MY_DOMAIN_PASS}"
  }
EOF
  )

  DIR_TEST=$(curl ${CURL_POST_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://localhost:9440/PrismGateway/services/rest/v1/authconfig/directories)
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
    https://localhost:9440/PrismGateway/services/rest/v1/authconfig/directories/${LDAP_SERVER}/role_mappings)
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
  LDAP_UUID=$(PATH=${PATH}:${HOME}; curl ${CURL_POST_OPTS} \
    --user admin:${MY_PE_PASSWORD} -X POST --data "${HTTP_BODY}" \
    https://localhost:9440/api/nutanix/v3/directory_services/list \
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
          "username": "${MY_DOMAIN_USER}",
          "password": "${MY_DOMAIN_PASS}"
        },
        "url": "ldaps://10.21.${MY_HPOC_NUMBER}.40/",
        "directory_type": "ACTIVE_DIRECTORY",
        "admin_user_reference_list": [],
        "domain_name": "${MY_DOMAIN_FQDN}"
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
    https://localhost:9440/api/nutanix/v3/directory_services/${LDAP_UUID})
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
    https://localhost:9440/api/nutanix/v3/services/nucalm)
  my_log "CALM=|${CALM}|"

  if [[ ${MY_PC_VERSION} == '5.7.0.1' ]]; then
    echo https://portal.nutanix.com/#/page/kbs/details?targetId=kA00e000000LJ1aCAG
    echo modify_firewall -o open -i eth0 -p 8090 -a
    echo TOFIX: remote_exec 'SSH' 'PE'
    echo allssh "cat /srv/pillar/iptables.sls |grep 8090"
    echo allssh sudo cat /home/docker/epsilon/conf/karan_hosts.txt
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
    https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
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
    https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
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
    https://localhost:9440/PrismGateway/services/rest/v1/application/user_data)
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
    https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
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
    https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
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
    https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
  my_log "welcome_banner UI_TEST=|${UI_TEST}|"
}

function PC_Init
{ # depends on ncli
  # TODO: PC_Init: NCLI, type 'cluster get-smtp-server' config

  local OLD_PW='nutanix/4u'
  my_log "Reset PC password to PE password, must be done by nci@PC, not API or on PE"
#  sshpass -p ${OLD_PW} ssh ${SSH_OPTS} nutanix@localhost \
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
#     https://localhost:9440/PrismGateway/services/rest/v1/utils/change_default_system_password)
#   my_log "cURL reset password PC_TEST=${PC_TEST}"

  my_log "Configure NTP on PC"
  ncli cluster add-to-ntp-servers servers=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org

  my_log "Validate EULA on PC"
  EULA_TEST=$(curl ${CURL_HTTP_OPTS} --user admin:${MY_PE_PASSWORD} -X POST -d '{
      "username": "SE",
      "companyName": "NTNX",
      "jobTitle": "SE"
  }' https://localhost:9440/PrismGateway/services/rest/v1/eulas/accept)
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
  }' https://localhost:9440/PrismGateway/services/rest/v1/pulse)
  my_log "PULSE_TEST=|${PULSE_TEST}|"

  # Prism Central upgrade
  #my_log "Download PC upgrade image: ${MY_PC_UPGRADE_URL##*/}"
  #cd /home/nutanix/install ; ./bin/cluster -i . -p upgrade
}

function Images
{ # depends on nuclei
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


  for IMG in 'CentOS7-04282018.qcow2 Windows2012R2-04282018.qcow2'; do
    my_log "CentOS7-04282018.qcow2 image..."
    nuclei image.create name=${IMG} \
       description="${0} via stage_calmhow_pc for ${IMG}" \
       source_uri=http://10.21.250.221/images/ahv/techsummit/${IMG}
    if (( $? != 0 )) ; then
      my_log "Warning: Image submission: $?."
      #exit 10
    fi
  done
}

function PC_project {
  PROJECT_NAME=mark.lavi.test

  nuclei project.create name=${PROJECT_NAME} \
      description='test from NuClei!'
      nuclei project.get ${PROJECT_NAME} format=json | jq .metadata.project_reference.uuid | tr -d '"'

    # - project.get mark.lavi.test
    # - project.update mark.lavi.test
    #     spec.resources.account_reference_list.kind= or .uuid
    #     spec.resources.default_subnet_reference.kind=
    #     spec.resources.environment_reference_list.kind=
    #     spec.resources.external_user_group_reference_list.kind=
    #     spec.resources.subnet_reference_list.kind=
    #     spec.resources.user_reference_list.kind=
}
#__main()____________

# Source Nutanix environments (for PATH and other things such as ncli)
. /etc/profile.d/nutanix_env.sh
. common.lib.sh

my_log `basename "$0"`": __main__: PID=$$"

CheckArgsExist 'MY_PE_PASSWORD MY_PC_VERSION LDAP_SERVER MY_DOMAIN_FQDN MY_DOMAIN_USER MY_DOMAIN_PASS'

ATTEMPTS=2
   SLEEP=10

Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq'\
&& PC_Init \
&& PC_UI \
&& PC_LDAP \
&& SSP_Auth \
&& CALM \
&& Images \
&& Check_Prism_API_Up 'PC'
# TODO: Karan

if (( $? == 0 )) ; then
  Dependencies 'remove' 'sshpass' && Dependencies 'remove' 'jq';
  my_log "$0: done!_____________________"
  echo
else
  my_log "Error: failed to reach PC, exit."
  exit 19
fi
