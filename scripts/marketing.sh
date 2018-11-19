#!/usr/bin/env bash
# -x
function pe_image() {
  # https://portal.nutanix.com/#/page/docs/details?targetId=Command-Ref-AOS-v59:acl-acli-image-auto-r.html
  local         _cli='acli'
  local     _command
  local    _complete
  local       _image
  local  _image_type
  local        _name
  local      _source='source_url'

  which "$_cli"
  if (( $? > 0 )); then
         _cli='nuclei'
    _complete=' grep -i complete | '
      _source='source_uri'
  fi

  for _image in "${QCOW2_IMAGES[@]}" ; do
    # log "DEBUG: ${_image} image.create..."

    if [[ -n $(${_cli} image.list 2>&1 | ${_complete} grep "${_image}") ]]; then
      log "Skip: ${_image} already complete on cluster."
    else
      _command=''
         _name="${_image}"

      if (( $(echo "${_image}" | grep -i -e '^http' -e '^nfs' | wc --lines) )); then
        log 'Bypass multiple repo source checks...'
        SOURCE_URL="${_image}"
      else
        repo_source QCOW2_REPOS[@] "${_image}" # IMPORTANT: don't ${dereference}[array]!
      fi

      if [[ -z "${SOURCE_URL}" ]]; then
        _error=30
        log "Warning ${_error}: didn't find any sources for ${_image}, continuing..."
        # exit ${_error}
      fi

      # TODO: TOFIX: ugly override for today...
      if (( $(echo "${_image}" | grep -i 'acs-centos' | wc --lines ) > 0 )); then
        _name=acs-centos
      fi

      if [[ ${_cli} == 'acli' ]]; then
        _image_type='kDiskImage'
        if (( $(echo "${SOURCE_URL}" | grep -i -e 'iso$' | wc --lines ) > 0 )); then
          _image_type='kIsoImage'
        fi

        _command+=" ${_name} annotation=${_image} image_type=${_image_type} \
          container=${MY_IMG_CONTAINER_NAME} architecture=kX86_64 wait=true"
      else
        _command+=" name=${_name} description=\"${_image}\""
      fi

      ${_cli} "image.create ${_command}" ${_source}=${SOURCE_URL} 2>&1
      if (( $? != 0 )); then
        log "Warning: Image submission: $?. Continuing..."
        #exit 10
      fi

      if [[ ${_cli} == 'nuclei' ]]; then
        log "NOTE: image.uuid = RUNNING, but takes a while to show up in:"
        log "TODO: ${_cli} image.list, state = COMPLETE; image.list Name UUID State"
      fi
    fi

  done
}

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

CheckArgsExist 'MY_EMAIL PE_HOST PE_PASSWORD PC_VERSION'

#Dependencies 'install' 'jq' && NTNX_Download 'PC' & #attempt at parallelization

log "Adding key to PE/CVMs..."
SSH_PubKey & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    Dependencies 'install' 'sshpass' && Dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && pe_image \
    && pc_init \
    && Check_Prism_API_Up 'PC'

    if (( $? == 0 )) ; then
      pc_configure #\
      # && Dependencies 'remove' 'sshpass' \
      # && Dependencies 'remove' 'jq'

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
esac
