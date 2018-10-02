#!/usr/bin/env bash

# Example use from a Nutanix CVM:
# curl --remote-name --location https://raw.githubusercontent.com/nutanixworkshops/stageworkshop/master/bootstrap.sh && SOURCE=${_} sh ${_##*/}

if [[ -z ${SOURCE} ]]; then
  ORGANIZATION=nutanixworkshops
    REPOSITORY=stageworkshop
        BRANCH=master
else
    URL_SOURCE=(${SOURCE//\// }) # zero index
  ORGANIZATION=${URL_SOURCE[2]}
    REPOSITORY=${URL_SOURCE[3]}
        BRANCH=${URL_SOURCE[4]}
fi

BASE_URL=https://github.com/${ORGANIZATION}/${REPOSITORY}
 ARCHIVE=${BASE_URL}/archive/${BRANCH}.zip

if [[ ${1} == 'clean' ]]; then
 echo "Cleaning up..."
 rm -rf ${ARCHIVE##*/} ${0} ${REPOSITORY}-${BRANCH}/
 exit 0
fi

echo -e "\nFor details, please see: ${BASE_URL}\n"

_ERROR=0

. /etc/profile.d/nutanix_env.sh || _ERROR=1

if (( ${_ERROR} == 1 )); then
  echo "Error: This script should be run on a Nutanix CVM!"
  #echo RESTORE:
  exit ${_ERROR}
fi

CLUSTER_NAME=' '
CLUSTER_NAME+=$(ncli cluster get-params | grep 'Cluster Name' \
              | awk -F: '{print $2}' | tr -d '[:space:]')
EMAIL_DOMAIN=nutanix.com

if [[ -z ${MY_PE_PASSWORD} ]]; then
  _PRISM_ADMIN=admin
  echo
  read -p "Optional: What is this cluster's admin username? [Default: ${_PRISM_ADMIN}] " PRISM_ADMIN
  if [[ -z ${PRISM_ADMIN} ]]; then
    PRISM_ADMIN=${_PRISM_ADMIN}
  fi

  echo -e "\n    Note: Password will not be displayed."
  read -s -p "REQUIRED: What is this${CLUSTER_NAME} cluster's admin password? " -r _PW1 ; echo
  read -s -p " CONFIRM:             ${CLUSTER_NAME} cluster's admin password? " -r _PW2 ; echo

  if [[ ${_PW1} != ${_PW2} ]]; then
    _ERROR=1
    echo "Error ${_ERROR}: passwords do not match."
    exit ${_ERROR}
  else
    MY_PE_PASSWORD=${_PW1}
    unset _PW1 _PW2
  fi
fi

MY_PE_HOST=$(ncli cluster get-params | grep 'External IP' \
  | awk -F: '{print $2}' | tr -d '[:space:]')

if [[ -z ${MY_EMAIL} ]]; then
  echo -e "\n    Note: @${EMAIL_DOMAIN} will be added if domain omitted."
  read -p "REQUIRED: Email address for cluster admin? " MY_EMAIL
fi

_WC_ARG='--lines'
if [[ `uname -s` == "Darwin" ]]; then
  _WC_ARG='-l'
fi
if (( $(echo ${MY_EMAIL} | grep @ | wc ${_WC_ARG}) == 0 )); then
  MY_EMAIL+=@${EMAIL_DOMAIN}
fi

if [[ ! -d ${REPOSITORY}-${BRANCH} ]]; then
  echo -e "\nNo cache: retrieving ${ARCHIVE} ..."
  curl --remote-name --location ${ARCHIVE} \
  && echo "Success: ${ARCHIVE##*/}" \
  && unzip ${ARCHIVE##*/}
fi

echo -e "\nStarting stage_workshop.sh for ${MY_EMAIL} with ${PRISM_ADMIN}:passwordNotShown@${MY_PE_HOST} ...\n"

pushd ${REPOSITORY}-${BRANCH}/ \
  && chmod -R u+x *sh \
  &&  MY_EMAIL=${MY_EMAIL} \
    MY_PE_HOST=${MY_PE_HOST} \
   PRISM_ADMIN=${PRISM_ADMIN} \
MY_PE_PASSWORD=${MY_PE_PASSWORD} \
./stage_workshop.sh -f - \
  && popd

echo -e "\n    DONE: ${0} ran for ${SECONDS} seconds."
cat <<EOM
Optional: Please consider running ${0} clean.

Watch progress with:
          tail -f stage_workshop.log &
or login to PE to see tasks in flight and eventual PC registration:
          https://${MY_PE_HOST}:9440/
EOM

exit

TODO:
- determine if I'm on HPOC nw variant for a local URL, etc.
- local _HTTP_RANGE_ENABLED='--continue-at -'
