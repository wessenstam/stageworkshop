#!/usr/bin/env bash

function Determine_PE {
  local _HOLD=$(nuclei cluster.list format=json \
    | jq '.entities[] | select(.status.state == "COMPLETE")' \
    | jq '. | select(.status.resources.network.external_ip != null)')

  if (( $? > 0 )); then
    log "Error: couldn't resolve clusters $?"
    exit 10
  else
    export CLUSTER_NAME=$(echo ${_HOLD} | jq .status.name | tr -d \")
    export   MY_PE_HOST=$(echo ${_HOLD} | jq .status.resources.network.external_ip | tr -d \")

    log "Success: ${CLUSTER_NAME} PE external IP=${MY_PE_HOST}"
  fi
}

export PATH=${PATH}:${HOME}
. /etc/profile.d/nutanix_env.sh
. common.lib.sh

Dependencies 'install' 'jq'

log `basename "$0"`": __main__: PID=$$"

Determine_PE || log 'Error: cannot Determine_PE' && exit 13

#  CLUSTER_NAME=Specialty02
# MY_PE_HOST=$(nuclei cluster.get ${CLUSTER_NAME} format=json \
#   | jq .spec.resources.network.external_ip \
#   | tr -d \") # NuCLEI
if [[ -z "${1}" ]]; then
  VM_NAME=centos7-ml
else
  VM_NAME=${1}
fi

#nuclei vm.get ${VM_NAME} format=json \
#   | jq '.spec.resources.disk_list[] | select(.device_properties.device_type == "DISK") | .uuid' \
#   | tr -d \" # NuCLEI output example = logs/cb.json

log "Powering ${VM_NAME} off ..."
nuclei vm.update ${VM_NAME} power_state=OFF

VM_UUID=$(acli -H ${MY_PE_HOST} -o json vm.list \
  | jq '.data[] | select(.name == "'${VM_NAME}'") | .uuid' \
  | tr -d \") # acli output example = logs/cb2.pretty.json
if (( $? > 0 )) || [[ -z "${VM_UUID}" ]]; then
  log "Error: couldn't resolve VM_UUID: $?"
  exit 11
else
  log "VM_UUID: ${VM_UUID}"
fi

VMDISK_NFS_PATH=$(acli -H ${MY_PE_HOST} -o json vm.get ${VM_NAME} include_vmdisk_paths=true \
  | jq .data.\"${VM_UUID}\".config.disk_list[].vmdisk_nfs_path \
  | grep -v null | tr -d \") # leading /, acli output example = logs/vm.list.pretty.json
if (( $? > 0 )) || [[ -z "${VMDISK_NFS_PATH}" ]]; then
  log "Error: couldn't resolve VMDISK_NFS_PATH: $?"
  exit 12
else
  echo "VMDISK_NFS_PATH: nfs://${MY_PE_HOST}${VMDISK_NFS_PATH}"
fi

IMG=${VM_NAME}_$(date +%Y%m%d-%H:%M)
log "Image upload: ${IMG}..."
nuclei image.create name=${IMG} \
  description="${IMG} updated with centos password and cloud-init" \
  source_uri=nfs://${MY_PE_HOST}${VMDISK_NFS_PATH}

if (( $? != 0 )); then
  log "Warning: Image submission: $?."
  #exit 10
fi
log "NOTE: image.uuid = RUNNING, but takes a while to show up in:"
log "TODO: nuclei image.list, state = COMPLETE; image.list Name UUID State"
