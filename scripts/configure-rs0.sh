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

echo "Env: MONGOD_HOSTS=${MONGOD_HOSTS}"
echo "Env: MONGOD_PORT=${MONGOD_PORT}"
echo "Env: MONGOD_ARB_HOST=${MONGOD_ARB_HOST}"
echo "Env: MONGOD_ARB_PORT=$((MONGOD_PORT+1))"

#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
${mongo_bin} -u admin -p ${MONGOD_ADMIN_PASSWORD} --authenticationDatabase admin ${MONGOD_BINDIP}:${MONGOD_PORT}  <<EOF
let db_list=['${MONGOD_HOSTS#*,}:${MONGOD_PORT}','${MONGOD_HOSTS%,*}:${MONGOD_PORT}'];
let arb_host='${MONGOD_ARB_HOST}:$((MONGOD_PORT+1))';
rs.initiate({_id : 'rs0', members: [ { '_id': 0, 'host':db_list[0] } ] });
rs.addArb(arb_host);
rs.add(db_list[1]);
rs.conf();
rs.status();
EOF
[[ $? -ne $RC_SUCCESS ]] && { echo -e "\e[31;7;5mError: Fix errors and rerun $(basename $0).\e[0m";exit $RC_FAILURE; }
echo -e "\e[0;7;5mInfo: All looks good.\e[0m"
