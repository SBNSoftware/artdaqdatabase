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

goback_dir=$(pwd)
echo;echo;echo
source ${SCRIPT_DIR}/../setup_database.sh
export_artdaqdb_uri

echo;echo "Running: conftool.py readDatabaseInfo"
conftool.py readDatabaseInfo |grep -vE '(nodename|uri)'
(( ${PIPESTATUS[0]}==0 )) ||\
  { echo -e "\e[31;7;5mError: Can’t query artdaq database info, login into db01 and db02 and verify that services are running.\e[0m";exit $RC_FAILURE; }

echo;echo "Running: conftool.py listDatabases"
conftool.py listDatabases
(( $?==0 )) || { echo -e "\e[31;7;5mError: Can’t query artdaq database info, login into db01 and db02 and verify that services are running.\e[0m";exit $RC_FAILURE; }


suffx=imp
testdir=/tmp/conftoolpytests-${RUN_AS_USER}-${TIMESTAMP}/${suffx}

mkdir -p ${testdir}

for f in ${SCRIPT_DIR}/../testdata/*.data; do
  tar xf ${f} -C ${testdir}
done

error_count=0
for d in $(ls -d ${testdir}/*); do
  echo;echo "Running: conftool.py importConfiguration $(basename ${d})"
  cd  $d
  conftool.py importConfiguration $(basename ${d})| grep -v Imported
  (( ${PIPESTATUS[0]}==0 )) || { echo -e "\e[31;7;5mError: conftool.py control.py returned non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }
done 

echo;echo "Running: conftool.py getListOfAvailableRunConfigurationPrefixes"
conftool.py getListOfAvailableRunConfigurationPrefixes
(( $?==0 ))  || { echo -e "\e[31;7;5mError: conftool.py control.py returned non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }

echo;echo "Running: conftool.py getListOfAvailableRunConfigurations"
conftool.py getListOfAvailableRunConfigurations
(( $?==0 )) || { echo -e "\e[31;7;5mError: conftool.py control.py returned non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }

suffx=exp
testdir=/tmp/conftoolpytests-${RUN_AS_USER}-${TIMESTAMP}/${suffx}
for c in conf00001 conf00002 conf00003; do
  echo;echo "Running: conftool.py exportConfiguration ${c}"
  mkdir -p ${testdir}/${c}
  cd  ${testdir}/${c}
  conftool.py exportConfiguration ${c} | grep -v Exported
  (( ${PIPESTATUS[0]}==0 )) || { echo -e "\e[31;7;5mError: conftool.py control.py returned non-zero exit status, check for errors and re-run tests.\e[0m"; ((error_count+=1)); }
done

rm -rf /tmp/conftoolpytests*

(( error_count==0 )) && { echo -e "\e[0;7;5mInfo: All tests worked run restore-database.sh.\e[0m"; exit $RC_SUCCESS; }

echo -e "\e[31;7;5mError: ${error_count} tests have failed. Try running them again, also review the instructions for control.py\e[0m"
echo "https://cdcvs.fnal.gov/redmine/projects/artdaq-utilities/wiki/Artdaq-config-conftool"
exit $RC_FAILURE
