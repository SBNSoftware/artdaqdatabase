#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM}  \
  KRB5CCNAME=$(klist 2>&1 |grep cache |grep -Eo '/tmp/[a-zA-Z0-9_]+')  \
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
function setup_running_area(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local this_hostname="$(echo ${MONGOD_HOSTS},${MONGOD_ARB_HOST}|grep -Eo "$(hostname -s)"|sort -u )"
  local this_ip=$(ping -c 1 -t 1 ${this_hostname} |grep PING |cut -d" " -f3 |grep -Eo '[0-9\.]+')
  echo "Info: Setting up a new running area on ${this_hostname}."
  if [[ -d ${INSTALL_PREFIX} ]]; then
      rm -rf ${INSTALL_PREFIX}
      if [[ $? -ne $RC_SUCCESS ]]; then
        echo "Error: Failed removing directory ${INSTALL_PREFIX}; delete it manually."; return $RC_FAILURE
      fi
  fi

  mkdir -p ${INSTALL_PREFIX}/{${MONGOD_DATA_DIR},scripts}
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo "Error: Failed creating directory ${INSTALL_PREFIX}/${MONGOD_DATA_DIR}; \
 artdaq user does not have write permissions for $(dirname ${INSTALL_PREFIX})."; return $RC_FAILURE
  fi

  set -e
  cp ${SCRIPT_DIR}/*.js ${SCRIPT_DIR}/*.sh ${INSTALL_PREFIX}/scripts/
  cp -r ${SCRIPT_DIR}/../{templates,initd_functions,mongod-ctrl.sh}  ${INSTALL_PREFIX}/
  chown -R ${run_as_user}:${run_as_group} ${INSTALL_PREFIX}
  chmod a+rx ${INSTALL_PREFIX}/scripts/*.sh
  chmod a+rx ${INSTALL_PREFIX}/*.sh
  chmod a+r ${INSTALL_PREFIX}/templates/*

  local MONGOD_KEY=${INSTALL_PREFIX}/${MONGOD_DATA_DIR}/mongod.keyfile

  if [ ! -f ${MONGOD_KEY} ]; then
    echo "Info: Mongod key file not found. Generating a new key file ${MONGOD_KEY}."
    openssl rand -base64 756 > ${MONGOD_KEY}
    chmod 400 ${MONGOD_KEY}
  fi

cat > ${INSTALL_PREFIX}/${MONGOD_DATA_DIR}/mongod.env <<EOF
EXPERIMENT="${EXPERIMENT}"
MONGOD_PRODUCTS_DIR="${MONGOD_PRODUCTS_DIR}"
MONGOD_UPS_VER="${MONGOD_UPS_VER}"
MONGOD_UPS_QUAL="${MONGOD_UPS_QUAL}"
MONGOD_BINDIP="${this_ip}"
MONGOD_PORT=${MONGOD_PORT}
MONGOD_HOSTS="${MONGOD_HOSTS}"
MONGOD_ARB_HOST="${MONGOD_ARB_HOST}"
MONGOD_RW_PASSWORD="${MONGOD_RW_PASSWORD}"
MONGOD_ADMIN_PASSWORD="${MONGOD_ADMIN_PASSWORD}"
EOF

  set +e
  cat ${INSTALL_PREFIX}/${MONGOD_DATA_DIR}/mongod.env

  for h in $(echo ${MONGOD_HOSTS},${MONGOD_ARB_HOST}| sed 's/,/\n/g' |grep -v $(hostname -s)|sort -u); do
    echo;echo
    echo "Info: Setting up a new running area on ${h}."
    if [[ $(ssh -F ${HOME}/.ssh/config_mongosetup artdaq@$h \
      "[[ -d ${INSTALL_PREFIX} ]] && rm -rf ${INSTALL_PREFIX}; mkdir -p ${INSTALL_PREFIX} && echo WORKED") != "WORKED" ]]; then
        echo "Error: Failed creating directory ${INSTALL_PREFIX}/${MONGOD_DATA_DIR}; \
 artdaq user does not have write permissions for $(dirname ${INSTALL_PREFIX})."; return $RC_FAILURE
    fi

    scp -q -r -F ${HOME}/.ssh/config_mongosetup ${INSTALL_PREFIX}/*  artdaq@$h:${INSTALL_PREFIX}/
    [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed SCP-ing directory ${INSTALL_PREFIX} to $h; check SSH connectivity."; return $RC_FAILURE; }

    local remote_ip=$(ping -c 1 -t 1 ${h} |grep PING |cut -d" " -f3 |grep -Eo '[0-9\.]+')

    cat  <<EOF | ssh -F ${HOME}/.ssh/config_mongosetup artdaq@$h "cat > ${INSTALL_PREFIX}/${MONGOD_DATA_DIR}/mongod.env"
EXPERIMENT="${EXPERIMENT}"
MONGOD_PRODUCTS_DIR="${MONGOD_PRODUCTS_DIR}"
MONGOD_UPS_VER="${MONGOD_UPS_VER}"
MONGOD_UPS_QUAL="${MONGOD_UPS_QUAL}"
MONGOD_BINDIP="${remote_ip}"
MONGOD_PORT=${MONGOD_PORT}
MONGOD_HOSTS="${MONGOD_HOSTS}"
MONGOD_ARB_HOST="${MONGOD_ARB_HOST}"
MONGOD_RW_PASSWORD="${MONGOD_RW_PASSWORD}"
MONGOD_ADMIN_PASSWORD="${MONGOD_ADMIN_PASSWORD}"
EOF
   [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed piping mongod.env to $h; check SSH connectivity."; return $RC_FAILURE; }
   ssh -F ${HOME}/.ssh/config_mongosetup artdaq@$h "cat ${INSTALL_PREFIX}/${MONGOD_DATA_DIR}/mongod.env"
  done
}

function create_users(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  ${INSTALL_PREFIX}/mongod-ctrl.sh configure
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed launching MongoDB in configuration mode.";
                                ${INSTALL_PREFIX}/mongod-ctrl.sh stop; return $RC_FAILURE; }

  echo "Info: Creating admin and ${EXPERIMENT}daq users."
  ${INSTALL_PREFIX}/scripts/create-users.sh
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed creating admin and ${EXPERIMENT}daq users.";
                                ${INSTALL_PREFIX}/mongod-ctrl.sh stop; return $RC_FAILURE; }

  echo "Info: Stopping MongoDB."
  ${INSTALL_PREFIX}/mongod-ctrl.sh stop

  (( $(ps -ef |grep -v grep | grep ${INSTALL_PREFIX}|wc -l) == 0 )) ||\
    { echo "Error: Failed stopping MongoDB; kill manually any remaining mongod processes launched from ${INSTALL_PREFIX}.";
             return $RC_FAILURE ; }

  echo "Info: Done.n"
  return $RC_SUCCESS
}


function start_rs0() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  ${INSTALL_PREFIX}/mongod-ctrl.sh start
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed launching MongoDB on $(hostname -s)."; stop_rs0 ; return $RC_FAILURE; }

  ${INSTALL_PREFIX}/mongod-ctrl.sh start_arbiter
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed launching MongoDB arbiter on $(hostname -s)."; stop_rs0 ; return $RC_FAILURE; }

  for h in $(echo ${MONGOD_HOSTS}| sed 's/,/\n/g' |grep -v $(hostname -s)|sort -u); do
    ssh -F ${HOME}/.ssh/config_mongosetup artdaq@$h "${INSTALL_PREFIX}/mongod-ctrl.sh start"
    [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed launching MongoDB on $h."; stop_rs0 ; return $RC_FAILURE; }
  done

  echo "Info: Done."
  return $RC_SUCCESS
}


function stop_rs0() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0

  for h in $(echo ${MONGOD_HOSTS}| sed 's/,/\n/g' |grep -v $(hostname -s)|sort -u); do
    ssh -F ${HOME}/.ssh/config_mongosetup artdaq@$h "${INSTALL_PREFIX}/mongod-ctrl.sh stop"
    [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed stopping MongoDB on $h.\n"; ((error_count+=1)); }
  done

  ${INSTALL_PREFIX}/mongod-ctrl.sh stop_arbiter
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed stopping MongoDB arbiter on $(hostname -s)."; ((error_count+=1)); }

  ${INSTALL_PREFIX}/mongod-ctrl.sh stop
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed stopping MongoDB on $(hostname -s)."; ((error_count+=1)); }

  (( error_count==0 )) && { echo "Info: Done.";  return $RC_SUCCESS; }

  echo "Error: Failed stopping MongoDB; kill manually any remaining mongod processes launched from ${INSTALL_PREFIX}."

  return $RC_FAILURE
}

function configure_rs0() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  start_rs0
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed starting MongoDB rs0."; stop_rs0; return $RC_FAILURE; }
  echo "Info: Sleeping for 5 seconds."
  sleep 5

  ${INSTALL_PREFIX}/scripts/configure-rs0.sh
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed configuring MongoDB rs0."; stop_rs0; return $RC_FAILURE; }

  stop_rs0
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed stopping MongoDB rs0."; return $RC_FAILURE; }

  return $RC_SUCCESS
}

function restore_database() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  start_rs0
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed starting MongoDB rs0."; stop_rs0; return $RC_FAILURE; }
  echo "Info: Sleeping for 10 seconds."
  sleep 10

  ${INSTALL_PREFIX}/scripts/restore-database.sh
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed restoring MongoDB rs0."; stop_rs0; return $RC_FAILURE; }
  echo "Info: Sleeping for 30 seconds."
  sleep 30

  stop_rs0
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed stopping MongoDB rs0."; return $RC_FAILURE; }

  return $RC_SUCCESS
}

function generate_systemd_scripts() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  ${SCRIPT_DIR}/generate-systemd-scripts.sh
  [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed generating SystemD scripts for MongoDB rs0."; return $RC_FAILURE; }

  return $RC_SUCCESS
}

function deploy_systemd_scripts() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0
  local ignore_once=1
  for h in $(echo ${MONGOD_HOSTS}| sed 's/,/\n/g'); do
    #(( $ignore_once )) && ignore_once=0 || { echo "Info: Sleeping for 5 seconds."; sleep 5; }
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "${INSTALL_PREFIX}/install-systemd-services.sh"
    [[ $? -ne $RC_SUCCESS ]] && { echo "Error: Failed deploying SystemD services on ${h}."; ((error_count+=1)); }
  done

  (( error_count==0 )) && \
    { echo "Info: Run a database test with conftool.py. All test data will be wiped out by the database restore script.";
      return $RC_SUCCESS; }

  return $RC_FAILURE
}

#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
function main_program(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  echo;echo
  setup_running_area
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Fix artdaq user permissions for $(dirname ${INSTALL_PREFIX}) on ${MONGOD_HOSTS}, and rerun ${script_name}.\e[0m"; return $RC_FAILURE
  fi

  generate_systemd_scripts
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed generating SystemD scripts; kill manually any remaining mongod processes launched from ${INSTALL_PREFIX}, and rerun ${script_name}.\e[0m"; return $RC_FAILURE
  fi

  [[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; } || return  $RC_FAILURE

  create_users
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed creating admin and icarusdaq users, and rerun ${script_name}.\e[0m"; return $RC_FAILURE
  fi

  configure_rs0
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed configuring rs0; kill manually any remaining mongod processes launched from ${INSTALL_PREFIX}, and rerun ${script_name}.\e[0m"; return $RC_FAILURE
  fi

  deploy_systemd_scripts
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed deploying SystemD services to run MongoDB replica set.\e[0m";
    echo "Info: You don't have root login privileges, please ask members of SLAM or DAQ groups to run \
${INSTALL_PREFIX}/install-systemd-services.sh as root on db01 first, wait 30 seconds for \
services to warm up and then run ${INSTALL_PREFIX}/install-systemd-services.sh on db02."; return $RC_FAILURE
  fi


#  restore_database
#  if [[ $? -ne $RC_SUCCESS ]]; then
#    echo -e "\e[31;7;5mError: Failed restoring MongoDB form a backup; kill manually any remaining mongod processes launched from ${INSTALL_PREFIX}, and rerun ${script_name}.\e[0m"; return $RC_FAILURE
#  fi

  echo;echo;
  echo -e "\e[0;7;5mInfo: All done, please run conftoolpy-tests.sh.\e[0m"
}

#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
main_program
