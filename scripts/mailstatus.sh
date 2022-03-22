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

logname=`/bin/mktemp`
host=`/bin/hostname`
echo "Date " `/bin/date` > ${logname}
echo "Hostname " `/bin/hostname` >> ${logname}
echo "Uptime " `/usr/bin/uptime` >> ${logname}
echo   >>${logname}
echo   >>${logname}
echo   >>${logname}

echo "Data disk"  >>${logname}
df -h |grep -E "(Filesystem|/data)" >>${logname}

echo   >>${logname}
echo "Last 5 backups" >>${logname}
backups_dir=${INSTALL_PREFIX}/${MONGOD_DATA_DIR}/backup
for d in $(ls ${backups_dir} -t|head -5); do 
 echo $(du -hs ${backups_dir}/$d) $(find ${backups_dir}/$d -type f |wc -l) | \
  awk '{printf("%s size=%s files=%s \n", $2, $1, $3)}'|grep -Eo "202.*"  >>${logname} 
done

echo   >>${logname}
echo "Last 10 configs" >>${logname}
conftool.py getListOfAvailableRunConfigurations |head -10  >>${logname}

echo   >>${logname}
echo "Last 10 run records" >>${logname}
conftool.py getListOfArchivedRunConfigurations |head -12 |tail -10 >>${logname}

echo   >>${logname}
echo   >>${logname}
echo "Mongo DB"  >>${logname}
systemctl status mongo-server\@${MONGOD_DATA_DIR}.service  >>${logname}

echo   >>${logname}
echo "Mongo DB arbiter"  >>${logname}
systemctl status mongo-arbiter\@${MONGOD_DATA_DIR}.service  >>${logname}


/bin/cat - ${logname}  << EOF | /usr/sbin/sendmail -t
To: lukhanin@fnal.gov
Subject: Status ${host}
From: ${RUN_AS_USER}@$(hostname -s).fnal.gov

EOF

/bin/rm ${logname}
