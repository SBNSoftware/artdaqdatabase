#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM}  \
  HOME=${HOME} PATH=${PATH} PWD=${PWD} $(readlink -f $0); exit $?; }
SCRIPT_DIR=$(dirname  $(readlink -f $0))
[[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && \
  { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; [[ $? == 0 ]] || exit 1; } || exit 1
echo;echo "Info: Running script $(basename $0)"
[[ $(type -t setup_mongodb_product) == function ]] && setup_mongodb_product || { echo "Error: Undefined function setup_mongodb_product.";  exit 2; }

export PATH=${SAVED_PATH}
export LD_LIBRARY_PATH=${SAVED_LD_LIBRARY_PATH}

echo "Env: MONGOD_BINDIP=127.0.0.1"
echo "Env: MONGOD_PORT=${MONGOD_PORT}"
#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
${mongo_bin}  127.0.0.1:${MONGOD_PORT} <<EOF
let db_name='${EXPERIMENT}_db';
let db_list=[db_name, db_name+'_archive'];
use admin;
db.createUser({'user': 'admin', 'pwd': '${MONGOD_ADMIN_PASSWORD}', 'roles':[{'role': 'root', 'db': 'admin'}]});
db.createUser({'user': '${EXPERIMENT}daq', 'pwd': '${MONGOD_RW_PASSWORD}', 'roles':[]});
for( var i =0; i< db_list.length; i++) {
  db.grantRolesToUser('${EXPERIMENT}daq',[{'role':'dbOwner', 'db': db_list[i]}]);
}
use admin;
db.getUser('${EXPERIMENT}daq');
EOF
[[ $? -ne $RC_SUCCESS ]] && { echo -e "\e[31;7;5mError: Fix errors and rerun $(basename $0).\e[0m";exit $RC_FAILURE; }
echo -e "\e[0;7;5mInfo: All looks good.\e[0m"
