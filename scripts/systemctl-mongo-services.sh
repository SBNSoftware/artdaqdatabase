#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM} \
  KRB5CCNAME=$(klist 2>&1 |grep cache |grep -Eo '/tmp/[a-zA-Z0-9_]+')  \
  HOME=${HOME} PATH=${PATH} PWD=${PWD} $(readlink -f $0) "$@"; exit $?; }
SCRIPT_DIR=$(dirname  $(readlink -f $0))
[[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && \
  { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; [[ $? == 0 ]] || exit 1; } || exit 1
echo;echo "Info: Running script $(basename $0)"
echo "----------------------------------------------------------------"
#----------------------------------------------------------------
# Implementaion
# Main program starts at the bottom of this file.
#----------------------------------------------------------------
function stop_mongo_services() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0
  for h in $(echo ${MONGOD_HOSTS}| sed 's/,/\n/g'); do
    echo "Stopping MongoDB Server on ${h}"
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "systemctl stop mongo-server@${MONGOD_DATA_DIR}.service"
    (( $? == 0 )) || { echo "Error: Failed stopping MongoDB Server service on $h."; ((error_count+=1)); }
  done
  for h in $(echo ${MONGOD_ARB_HOST}| sed 's/,/\n/g'); do
    echo "Stopping MongoDB Arbiter on ${h}"
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "systemctl stop mongo-arbiter@${MONGOD_DATA_DIR}.service"
    (( $? == 0 )) || { echo "Error: Failed stopping MongoDB Arbiter service on $h."; ((error_count+=1)); }
  done

  (( error_count==0 )) &&  { return $RC_SUCCESS; }
  echo "Info: Execute the following commands as root on ${MONGOD_HOSTS}"
  echo "   systemctl stop mongo-arbiter@${MONGOD_DATA_DIR}.service"
  echo "   systemctl stop mongo-server@${MONGOD_DATA_DIR}.service"

  return $RC_FAILURE
}

function start_mongo_services() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0
  local ignore_once=1
  for h in $(echo ${MONGOD_ARB_HOST}| sed 's/,/\n/g'); do
    echo "Starting MongoDB Arbiter on ${h}"
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "systemctl start mongo-arbiter@${MONGOD_DATA_DIR}.service"
    (( $? == 0 )) || { echo "Error: Failed starting MongoDB Arbiter service on $h."; ((error_count+=1)); }
  done
  for h in $(echo ${MONGOD_HOSTS}| sed 's/,/\n/g'); do
    echo "Starting MongoDB Server on ${h}"
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "systemctl start mongo-server@${MONGOD_DATA_DIR}.service"
    (( $? == 0 )) || { echo "Error: Failed starting MongoDB Server service on $h."; ((error_count+=1)); }
  done

  (( error_count==0 )) &&  { return $RC_SUCCESS; }
  echo "Info: Execute the following commands as root on ${MONGOD_HOSTS}"
  echo "   systemctl start mongo-arbiter@${MONGOD_DATA_DIR}.service"
  echo "   systemctl start mongo-server@${MONGOD_DATA_DIR}.service"

  return $RC_FAILURE
}

function status_mongo_services() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0
  echo
  for h in $(echo ${MONGOD_HOSTS}| sed 's/,/\n/g'); do
    echo "Checking MongoDB Server status on ${h}"
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "systemctl --no-pager status mongo-server@${MONGOD_DATA_DIR}.service |head -5"
    (( $? == 0 )) || { echo "Error: Failed status check for MongoDB Arbiter service on $h."; ((error_count+=1)); }
    echo
  done
  for h in $(echo ${MONGOD_ARB_HOST}| sed 's/,/\n/g'); do
    echo "Checking MongoDB Arbiter status on ${h}"
    ssh -F ${HOME}/.ssh/config_mongosetup root@${h} "systemctl --no-pager status mongo-arbiter@${MONGOD_DATA_DIR}.service |head -5"
    (( $? == 0 )) || { echo "Error: Failed status check for MongoDB Arbiter service on $h."; ((error_count+=1)); }
    echo
  done

  (( error_count==0 )) &&  { return $RC_SUCCESS; }
  echo "Info: Execute the following commands as root on ${MONGOD_HOSTS}."
  echo "   systemctl status mongo-arbiter@${MONGOD_DATA_DIR}.service"
  echo "   systemctl status mongo-server@${MONGOD_DATA_DIR}.service"

  return $RC_FAILURE
}

function conftool_quick_check() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  source ${SCRIPT_DIR}/../setup_database.sh
  export_artdaqdb_uri

  echo;echo "Running: conftool.py readDatabaseInfo"
  conftool.py readDatabaseInfo |grep -vE '(nodename|uri)'

  echo;echo "Running: conftool.py listDatabases"
  conftool.py listDatabases
}

#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
echo "Info: This script controlls MongoDB services on ${MONGOD_HOSTS}."
runcmd=status

(( $# == 1 )) && runcmd=$1
 echo;echo
if [[ "${runcmd}" == "stop" ]]; then
  stop_mongo_services
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed stopping services, try SSH-ing into ${MONGOD_HOSTS} as root and stop them manually.\e[0m"; exit $RC_FAILURE
  fi
  status_mongo_services
elif [[ "${runcmd}" == "start" ]]; then
  start_mongo_services
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed starting services, try SSH-ing into ${MONGOD_HOSTS} as root and stop them manually.\e[0m"; exit $RC_FAILURE
  fi
  status_mongo_services
elif [[ "${runcmd}" == "conftool" ]]; then
  conftool_quick_check
else
  status_mongo_services
  if [[ $? -ne $RC_SUCCESS ]]; then
    echo -e "\e[31;7;5mError: Failed running status checks, try SSH-ing into ${MONGOD_HOSTS} as root and run status checks manually.\e[0m"; exit $RC_FAILURE
  fi
fi

