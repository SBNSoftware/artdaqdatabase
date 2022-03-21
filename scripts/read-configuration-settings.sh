#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] || { echo "You should source this script!"; exit 1; }
echo "Info: Running script $(basename $0)"
echo "----------------------------------------------------------------"
#----------------------------------------------------------------
# Current default configuration parameters, which can be
# overriden in $HOME/.mongodb_install.env file if it exits.
# Main program starts at the bottom of this file.
#----------------------------------------------------------------
EXPERIMENT="$(echo $(hostname -s)|cut -d"-" -f1)"

MONGOD_PRODUCTS_DIR="/software/products"
MONGOD_UPS_VER="v4_0_8b"
MONGOD_UPS_QUAL="e17:prof"


MONGOD_HOSTS="${EXPERIMENT}-db01,${EXPERIMENT}-db02"
MONGOD_ARB_HOST="${EXPERIMENT}-db02"
MONGOD_PORT=38047

MONGOD_RW_PASSWORD="change-me"
MONGOD_ADMIN_PASSWORD="change-me${MONGOD_RW_PASSWORD}"

SUBNET_SUFFIX="-daq"

#----------------------------------------------------------------
# Optional configuration parameters, which can be
# overriden in $HOME/.mongodb_install.env file if it exits.
# Main program starts at the bottom of this file.
#----------------------------------------------------------------
unset PATH LD_LIBRARY_PATH PRODUCTS
export PATH=/sbin:/usr/sbin:/bin:/usr/bin

MONGOD_DATA_DIR=${EXPERIMENT}_${MONGOD_UPS_VER%%_*}x_db
MONGODB_ENV_FILE=${MONGODB_ENV_FILE:-"${HOME}/.mongodb_install.env"}

[[ -z ${USE_RUNTIME+x} ]] || {
  [[ -f ${MONGODB_ENV_FILE} ]] || { echo "Error: Missing configuration file ${MONGODB_ENV_FILE}"; return 1; }
  export $(grep '^INSTALL_PREFIX' ${MONGODB_ENV_FILE} | xargs -d '\n');
  echo "Env: INSTALL_PREFIX=${INSTALL_PREFIX}"
  (( $(find ${INSTALL_PREFIX}/ -name mongod.env |wc -l) )) && {
    MONGODB_ENV_FILE=$(find ${INSTALL_PREFIX} -name mongod.env);
    MONGOD_DATA_DIR=$(basename $(dirname ${MONGODB_ENV_FILE}));
    echo "Env: MONGODB_ENV_FILE=${MONGODB_ENV_FILE}"
    echo "Env: MONGOD_DATA_DIR=${MONGOD_DATA_DIR}"
  }
}

required_tools_list=(tar bzip2 gzip curl sed find id basename dirname crontab cut tr \
  uniq tee iperf git timeout envsubst openssl)
#----------------------------------------------------------------
# Implementaion
# Main program starts at the bottom of this file.
#----------------------------------------------------------------
RC_SUCCESS=0
RC_FAILURE=1

TIMESTAMP=$(date -d "today" +"%Y%m%d%H%M%S")

RUN_AS_USER=$(id -u -n)
RUN_AS_GROUP=$(id -g -n ${RUN_AS_USER})

echo "Env: RUN_AS_USER=${RUN_AS_USER}"
echo "Env: RUN_AS_GROUP=${RUN_AS_GROUP}"

script_name=$(basename $(readlink -f $0))
SCRIPT_DIR=$(dirname  $(readlink -f $0))

function read_configuration_settings() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"

  if [[ ! -f ${MONGODB_ENV_FILE} ]]; then
    echo "Error: ${MONGODB_ENV_FILE} not found!"; return $RC_FAILURE ; else
    export $(grep -v '^#' ${MONGODB_ENV_FILE} | xargs -d '\n')
    for vv in $(grep -v '^#'  ${MONGODB_ENV_FILE} | sed -E 's/(.*)=.*/\1/' | xargs); do
      export $vv=$(eval echo -e ${!vv});
    done
  fi
  export RUN_AS_USER RUN_AS_GROUP
  export SUBNET_SUFFIX
  export MONGOD_DATA_DIR
  export SCRIPT_DIR TIMESTAMP
  export RC_FAILURE RC_SUCCESS

  return $RC_SUCCESS
}

function print_configuration_settings(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  echo "Env: Reporting all environment variables:"
  printenv |grep -vE "(PASSWORD|^SHLVL|^_)"|sort

  return $RC_SUCCESS
}

function verify_essential_dependencies() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local missing_dependencies=""
  for tool_name in ${required_tools_list[@]} ; do
    local tool_bin=$(command -v ${tool_name})
    if [[ -z "${tool_bin}" ]] && [[ ! -x ${tool_bin} ]]; then
      missing_dependencies="${missing_dependencies} ${tool_name}"
      echo "Error: '${tool_name}' was not found."
    fi
  done

  [[ ${missing_dependencies} == "" ]] && return $RC_SUCCESS;

  echo "Error: Install missing dependencies ${missing_dependencies}."
  return $RC_FAILURE
}

function setup_mongodb_product() {
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  unset PRODUCTS
  source ${MONGOD_PRODUCTS_DIR}/setup >/dev/null  2>&1
  unsetup_all  >/dev/null 2>&1
  echo "Info: Setting up MongoDB ${MONGOD_UPS_VER} from UPS."
  setup mongodb ${MONGOD_UPS_VER} -q ${MONGOD_UPS_QUAL}
  [[ $? -ne 0 ]] && return $RC_FAILURE;

  mongo_bin=$(command -v mongo)
  if [[ -z "${mongo_bin}" ]] && [[ ! -x ${mongo_bin} ]]; then
    echo "Error: mongo was not found."; return $RC_FAILURE; else
    echo "Info: mongo found: '${mongo_bin}'";
  fi

  mongorestore_bin=$(command -v mongorestore)
  if [[ -z "${mongorestore_bin}" ]] && [[ ! -x ${mongorestore_bin} ]]; then
    echo "Error: mongorestore was not found."; return $RC_FAILURE; else
    echo "Info: mongorestore found: '${mongorestore_bin}'";
  fi

  mongodump_bin=$(command -v mongodump)
  if [[ -z "${mongodump_bin}" ]] && [[ ! -x ${mongodump_bin} ]]; then
    echo "Error: mongodump was not found."; return $RC_FAILURE; else
    echo "Info: mongodump found: '${mongodump_bin}'";
  fi

  mongod_bin=$(command -v mongod)
  if [[ -z "${mongod_bin}" ]] && [[ ! -x ${mongod_bin} ]]; then
    echo "Error: mongod was not found."; return $RC_FAILURE; else
    echo "Info: mongod found: '${mongod_bin}'";
  fi

  export mongod_bin mongorestore_bin mongo_bin mongodump_bin
  export SAVED_PATH=${PATH}
  export SAVED_LD_LIBRARY_PATH=${LD_LIBRARY_PATH}

  return $RC_SUCCESS
}

function configure_ssh(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  #rm -f  ${HOME}/.ssh/config_mongosetup ${HOME}/.ssh/mongosetup_rsa*

  if [[ ! -f  ${HOME}/.ssh/config_mongosetup ]]; then
  cat >  ${HOME}/.ssh/config_mongosetup <<EOF
#https://cdcvs.fnal.gov/redmine/projects/sbndaq/wiki/Setting_up_your_account_for_ssh_access_to_private_network_connections
Host *
    ConnectTimeout 2
    UserKnownHostsFile=/dev/null
    StrictHostKeyChecking no
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
    AddKeysToAgent no
    PasswordAuthentication no
    ForwardAgent yes
    Protocol 2
    AddressFamily inet
    ServerAliveInterval 60
    ForwardX11 no
    LogLevel QUIET
Host *-daq *-dcs *-data *-daq.fnal.gov *-dcs.fnal.gov *-data.fnal.gov
    ConnectTimeout 2
    UserKnownHostsFile=/dev/null
    StrictHostKeyChecking no
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
    AddKeysToAgent no
    IdentityFile ~/.ssh/mongosetup_rsa
    PasswordAuthentication no
    ForwardAgent yes
    Protocol 2
    AddressFamily inet
    ServerAliveInterval 60
    ForwardX11 no
    LogLevel QUIET
EOF
  chmod 600 ${HOME}/.ssh/config_mongosetup
  fi

  if [[ ! -f  ${HOME}/.ssh/mongosetup_rsa ]]; then
    ssh-keygen -t rsa -f ${HOME}/.ssh/mongosetup_rsa -C "mongosetup4${RUN_AS_USER}" -q -N ""
    cat   ${HOME}/.ssh/mongosetup_rsa.pub >> ${HOME}/.ssh/authorized_keys
    chmod 600 ${HOME}/.ssh/mongosetup_rsa*
  fi
}

function select_backup_dir(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  unset BACKUP_DIR
  local back_dir=/software/backup/icarus_v4x_db/backup
  local back_db=$(ls -tr $back_dir/ |tail -1)
  if [[ -f ~/.fzf.bash ]]; then
    source ~/.fzf.bash > /dev/null 2>&1
    back_db=$(for b in $(find $back_dir/* -maxdepth 0 -ctime -15 -type d |sort -r); do
    echo $(du -sm $b)| sed "s|$back_dir/||g";done| awk '{printf("%s  %s MB\n",$2,$1);}' |fzf)
    back_db=${back_db%% *}
  fi
  export BACKUP_DIR=${back_dir}/${back_db}
}

function export_artdaqdb_uri(){
  (( $# != 1 )) && \
    export ARTDAQ_DATABASE_URI="mongodb://${EXPERIMENT}daq:${MONGOD_RW_PASSWORD}@${MONGOD_HOSTS#*,}:${MONGOD_PORT},${MONGOD_HOSTS%,*}:${MONGOD_PORT}/${EXPERIMENT}_db?replicaSet=rs0&authSource=admin"

  [[ "$1" == "admin" ]] && \
    export ARTDAQ_DATABASE_URI="mongodb://admin:${MONGOD_ADMIN_PASSWORD}@${MONGOD_HOSTS#*,}:${MONGOD_PORT},${MONGOD_HOSTS%,*}:${MONGOD_PORT}/${EXPERIMENT}_db?replicaSet=rs0&authSource=admin"
} 

function export_backupdb_uri(){
  if (( $# != 1 )); then
     export ARTDAQ_DATABASE_URI="mongodb://admin:${MONGOD_ADMIN_PASSWORD}@${MONGOD_HOSTS#*,}:${MONGOD_PORT},${MONGOD_HOSTS%,*}:${MONGOD_PORT}/${EXPERIMENT}_db?replicaSet=rs0&authSource=admin"
  else
     export ARTDAQ_DATABASE_URI="mongodb://admin:${MONGOD_ADMIN_PASSWORD}@${MONGOD_HOSTS#*,}:${MONGOD_PORT},${MONGOD_HOSTS%,*}:${MONGOD_PORT}/$1?replicaSet=rs0&authSource=admin"
  fi
} 
#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
read_configuration_settings
#print_configuration_settings
