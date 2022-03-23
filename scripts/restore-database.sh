#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM}  \
  HOME=${HOME} PATH=${PATH} PWD=${PWD} $(readlink -f $0); exit $?; }
SCRIPT_DIR=$(dirname  $(readlink -f $0))
[[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && \
  { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; [[ $? == 0 ]] || exit 1; } || exit 1
echo;echo "Info: Running script $(basename $0)"
[[ $(type -t setup_mongodb_product) == function ]] && setup_mongodb_product || { echo "Error: Undefined function setup_mongodb_product.";  exit 2; }

start=$(date +%s)

export PATH=${SAVED_PATH}
export LD_LIBRARY_PATH=${SAVED_LD_LIBRARY_PATH}
echo "Env: MONGOD_HOSTS=${MONGOD_HOSTS}"
echo "Env: MONGOD_PORT=${MONGOD_PORT}"
echo "Env: MONGOD_ARB_HOST=${MONGOD_ARB_HOST}"
echo "Env: MONGOD_ARB_PORT=$((MONGOD_PORT+1))"

set -e

select_backup_dir
[[ -d  ${BACKUP_DIR} ]] || { echo "Error: MongoDB backup directory was not selected."; exit 3; }

backup_db_dir=${BACKUP_DIR}/${EXPERIMENT}_db/dump/${EXPERIMENT}_db
backup_db_archive_dir=${BACKUP_DIR}/${EXPERIMENT}_db_archive/dump/${EXPERIMENT}_db_archive

export_artdaqdb_uri "admin"
echo "Info: Restoring ${EXPERIMENT}_db from ${BACKUP_DIR}."
${mongorestore_bin} --drop --noIndexRestore --maintainInsertionOrder --uri=${ARTDAQ_DATABASE_URI} \
 --objcheck --stopOnError --preserveUUID --gzip --db=${EXPERIMENT}_db --dir=${backup_db_dir}
(( $?==0 )) || { echo -e "\e[31;7;5mError: Failed restoring ${EXPERIMENT}_db, try re-running $(basename $0).\e[0m";exit $RC_FAILURE; }

echo "Info: Rebuilding indexes in ${EXPERIMENT}_db."
${mongo_bin} ${ARTDAQ_DATABASE_URI}  <<EOF
db.getCollectionNames().forEach( function(collname) {
  db[collname].createIndex( { "configurations.name": 1 }, { name: "idx_configurations_name"} );
  db[collname].createIndex( { "entities.name": 1 }, { name: "idx_entities_name"} );
  db[collname].createIndex( { "version": 1 }, { name: "idx_version"} );
  db[collname].createIndex( { "configurations.name": 1, "entities.name": 1 },
    { name: "idx_configuration_name_vs_entities_name"}  );
});
EOF
(( $?==0 )) || { echo -e "\e[31;7;5mError: Failed restoring ${EXPERIMENT}_db, try re-running $(basename $0).\e[0m";exit $RC_FAILURE; }

ARTDAQ_DATABASE_URI=$(echo  ${ARTDAQ_DATABASE_URI}|sed "s/${EXPERIMENT}_db/${EXPERIMENT}_db_archive/g")
echo "Info: Restoring ${EXPERIMENT}_db_archive from ${BACKUP_DIR}."
# --excludeCollection=RunHistory \
${mongorestore_bin} --drop --noIndexRestore --maintainInsertionOrder --uri=${ARTDAQ_DATABASE_URI} \
 --objcheck --stopOnError --preserveUUID --gzip --db=${EXPERIMENT}_db_archive --dir=${backup_db_archive_dir}
(( $?==0 )) || { echo -e "\e[31;7;5mError: Failed restoring ${EXPERIMENT}_db_archive, try re-running $(basename $0).\e[0m";exit $RC_FAILURE; }


echo "Info: Rebuilding indexes in ${EXPERIMENT}_db."
${mongo_bin} ${ARTDAQ_DATABASE_URI} <<EOF
db.getCollectionNames().forEach( function(collname) {
  db[collname].createIndex( { "configurations.name": 1 }, { name: "idx_configurations_name"} );
  db[collname].createIndex( { "entities.name": 1 }, { name: "idx_entities_name"} );
  db[collname].createIndex( { "version": 1 }, { name: "idx_version"} );
  db[collname].createIndex( { "configurations.name": 1, "entities.name": 1 },
    { name: "idx_configuration_name_vs_entities_name"}  );
});
EOF
(( $?==0 )) || { echo -e "\e[31;7;5mError: Failed restoring ${EXPERIMENT}_db_archive, try re-running $(basename $0).\e[0m";exit $RC_FAILURE; }

error_count=0
set +e
goback_dir=$(pwd)
source ${SCRIPT_DIR}/../setup_database.sh
export_artdaqdb_uri
cd ${SCRIPT_DIR}/../
echo;echo "Running: conftool.py readDatabaseInfo"
conftool.py readDatabaseInfo |grep -vE '(nodename|uri)'
(( ${PIPESTATUS[0]}==0 )) ||\
  { echo -e "\e[31;7;5mError: Can’t query artdaq database info, login into db01 and db02 and verify that services are running.\e[0m"; ((error_count+=1));  }

echo;echo "Running: conftool.py listDatabases"
conftool.py listDatabases
(( $?==0 )) || { echo -e "\e[31;7;5mError: Can’t query artdaq database info, login into db01 and db02 and verify that services are running.\e[0m"; ((error_count+=1)); }
echo;echo
echo  "Info: Found $(conftool.py getListOfAvailableRunConfigurationsSubtractMasked  flags.fcl|wc -l && rc=${PIPESTATUS[0]}) active run configs."
(( ${rc}==0 )) || { echo -e "\e[31;7;5mError: conftool.py returned a non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }

echo "Info: Listing 10 most recent configs."
conftool.py getListOfAvailableRunConfigurationsSubtractMasked  flags.fcl |head -10 && rc=${PIPESTATUS[0]}
(( ${rc}==0 )) || { echo -e "\e[31;7;5mError: conftool.py returned a non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }
echo;echo

echo "Info: Found $(conftool.py getListOfArchivedRunConfigurations|wc -l && rc=${PIPESTATUS[0]}) run history records."
(( ${rc}==0 )) || { echo -e "\e[31;7;5mError: conftool.py returned a non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }

echo "Info: Listing 10 most recent run history records."
conftool.py getListOfArchivedRunConfigurations > /tmp/conftool-${TIMESTAMP}.txt && rc=$? && cat /tmp/conftool-${TIMESTAMP}.txt |head -12 |tail -10
(( ${rc}==0 )) || { echo -e "\e[31;7;5mError: conftool.py returned a non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }
echo;echo
rm -rf /tmp/conftool*
cd ${goback_dir}
end=$(date +%s)
runtime=$((end-start))

(( error_count==0 )) && {
  echo -e "\e[0;7;5mInfo: Artdaq database was restored from backup $(basename ${BACKUP_DIR}), and basic tests worked.\e[0m";
  echo "Info: Restored artdaq_database in $(( (runtime % 3600) / 60 )) minutes and $(( (runtime % 3600) % 60 )) seconds."
  echo;echo
  echo "https://cdcvs.fnal.gov/redmine/projects/artdaq-utilities/wiki/Artdaq-config-conftool"
  echo;echo
  echo "Info: Update ARTDAQ_DATABASE_URI in setup_database.sh."
  echo
  echo ARTDAQ_DATABASE_URI=${ARTDAQ_DATABASE_URI}
  exit $RC_SUCCESS; }

echo -e "\e[31;7;5mError: ${error_count} tests have failed. Try running them again, also review the instructions for control.py\e[0m"
echo;echo
echo "https://cdcvs.fnal.gov/redmine/projects/artdaq-utilities/wiki/Artdaq-config-conftool"
exit $RC_FAILURE
