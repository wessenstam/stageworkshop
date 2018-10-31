#!/usr/bin/env bash

if [[ ${USER} != 'root' ]]; then
  echo "Error in assumption: execute as user root."
  exit 1
fi

if [[ -n ${_autodc_conf} || -n ${_autodc_patch} ]]; then
  echo "Warning: _autodc_* environment variables not populated."
   _autodc_conf=/etc/samba/smb.conf
  _autodc_patch='ldap server require strong auth = no'
fi

if (( $(grep "${_autodc_patch}" ${_autodc_conf} | wc --lines) == 0 )); then
  cat ${_autodc_conf} | sed "s/\\[global\\]/\\[global\\]\n\t${_autodc_patch}/" \
    > ${_autodc_conf}.patched && mv ${_autodc_conf}.patched ${_autodc_conf}
  service smbd restart && sleep 2
fi

exit

curl --remote-name --location \
https://raw.githubusercontent.com/mlavi/stageworkshop/master/scripts/autodc_patch.sh \
  && export _autodc_conf=${_autodc_conf} \
  && export _autodc_patch=\"${_autodc_patch}\" \
  && sh ${_##*/}
