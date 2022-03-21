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
MONGOD_BASE_DIR=$(dirname $(readlink -f "$0") )
[[ "$(basename ${MONGOD_BASE_DIR})" == "scripts" ]] && MONGOD_BASE_DIR=$(dirname ${MONGOD_BASE_DIR})
BACKUP_DIR="${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/backup/${TIMESTAMP}"
BACKUP_LIST="${EXPERIMENT}_db ${EXPERIMENT}_db_archive"
#BACKUP_LIST="${EXPERIMENT}_db"
(( $# == 1 )) && export MONGOD_DATA_DIR=$1

echo "Backup started: $(date)"
echo "Running: $0 $@"
echo "Env: MONGOD_BASE_DIR=${MONGOD_BASE_DIR}"
echo "Env: MONGOD_DATA_DIR=${MONGOD_DATA_DIR}"
echo "Env: MONGOD_HOSTS=${MONGOD_HOSTS}"
echo "Env: MONGOD_PORT=${MONGOD_PORT}"
echo "Env: MONGOD_ARB_HOST=${MONGOD_ARB_HOST}"
echo "Env: MONGOD_ARB_PORT=$((MONGOD_PORT+1))"
echo "Env: BACKUP_DIR=${BACKUP_DIR}"
echo "Env: BACKUP_LIST=${BACKUP_LIST}"


for dbname in ${BACKUP_LIST}; do
  export_backupdb_uri ${dbname}
  mkdir -p ${BACKUP_DIR}/${dbname}/dump
  ${mongodump_bin} --gzip --quiet --uri=$ARTDAQ_DATABASE_URI --out=${BACKUP_DIR}/${dbname}/dump/
  printf "Info: ${dbname} archive is $(du -hs ${BACKUP_DIR}/${dbname}/dump/${dbname}|awk '{print $1}')"
  printf " and has $(find ${BACKUP_DIR}/${dbname}/dump/${dbname} -type f | wc -l) collections.\n"
done

#[[ ! -d /software/backup/${MONGOD_DATA_DIR}/${TIMESTAMP} ]] && mkdir -p /software/backup/${MONGOD_DATA_DIR}/${TIMESTAMP}

#rsync -av ${BACKUP_DIR} /software/backup/${MONGOD_DATA_DIR}/
echo "Backup ended: $(date)"
echo

