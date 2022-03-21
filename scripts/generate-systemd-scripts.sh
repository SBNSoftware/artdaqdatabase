#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM} \
  KRB5CCNAME=$(klist 2>&1 |grep cache |grep -Eo '/tmp/[a-z0-9_]+')  \
  HOME=${HOME} PATH=${PATH} PWD=${PWD} $(readlink -f $0); exit $?; }
SCRIPT_DIR=$(dirname  $(readlink -f $0))
[[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && \
  { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; [[ $? == 0 ]] || exit 1; } || exit 1
echo;echo "Info: Running script $(basename $0)"
echo "----------------------------------------------------------------"
#----------------------------------------------------------------
# Implementaion
# Main program starts at the bottom of this file.
#----------------------------------------------------------------
function generate_systemd_services(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local templates_dir=$(dirname $SCRIPT_DIR)/templates

  for t in $(ls ${templates_dir}/{*service,install*.sh}.template |sort); do
    envsubst <  $t | grep -v "^$" > ${INSTALL_PREFIX}/$(basename ${t%*.template})
    echo "********************************************************************************"
    echo "Info: Created $(basename ${t%*.template})"
    echo "--------------------------------------------------------------------------------"
    cat ${INSTALL_PREFIX}/$(basename ${t%*.template})
    echo "********************************************************************************"
    echo
  done

  chmod a+x ${INSTALL_PREFIX}/*.sh

  for h in $(echo ${MONGOD_HOSTS},${MONGOD_ARB_HOST}| sed 's/,/\n/g' |grep -v $(hostname -s)|sort -u); do
    scp -q -F ${HOME}/.ssh/config_mongosetup ${INSTALL_PREFIX}/{*.service,install*.sh} ${RUN_AS_USER}@${h}:${INSTALL_PREFIX}/
    [[ $? -ne $RC_SUCCESS ]] && { printf "Error: Failed SCP-ing directory ${INSTALL_PREFIX} to ${h}; check SSH connectivity.\n"; return $RC_FAILURE; }
  done

  cp $(dirname ${SCRIPT_DIR})/{flags.fcl,setup_database.sh} ${INSTALL_PREFIX}/

  for h in $(echo ${MONGOD_HOSTS},${MONGOD_ARB_HOST}| sed 's/,/\n/g' |grep -v $(hostname -s)|sort -u); do
    scp -q -F ${HOME}/.ssh/config_mongosetup ${INSTALL_PREFIX}/{flags.fcl,setup_database.sh} ${RUN_AS_USER}@${h}:${INSTALL_PREFIX}/
    [[ $? -ne $RC_SUCCESS ]] && { printf "Error: Failed SCP-ing directory ${INSTALL_PREFIX} to ${h}; check SSH connectivity.\n"; return $RC_FAILURE; }
  done

  return $RC_SUCCESS
}

function main_program(){
  generate_systemd_services
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Fix artdaq user permissions for $(dirname ${INSTALL_PREFIX}) on ${MONGOD_HOSTS}, and rerun ${script_name}.\e[0m"; return $RC_FAILURE
  fi

  echo;echo;
  echo -e "\e[0;7;5mInfo: Execute ${INSTALL_PREFIX}/install-systemd-services.sh as ROOT on ${MONGOD_HOSTS}.\e[0m"

  return $RC_SUCCESS
}

#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
main_program
