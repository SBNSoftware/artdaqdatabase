#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM}  \
  HOME=${HOME} PATH=${PATH} PWD=${PWD} $(readlink -f $0) "$@"; exit $?; }
SCRIPT_DIR=$(dirname  $(readlink -f $0))/scripts
[[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; } || exit 1
echo "Info: Running script $(basename $0)"
[[ $(type -t setup_mongodb_product) == function ]] && setup_mongodb_product || { echo "Error: Undefined function setup_mongodb_product.";  exit 2; }

MONGOD_BASE_DIR=${INSTALL_PREFIX:-"$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)"}
[[ -z ${MONGOD_BINDIP+x} ]] && MONGOD_BINDIP="$(/sbin/ip addr |grep -E -o "inet 132\.([0-9]{1,3}[\.]){2}[0-9]{1,3}"|cut -d" " -f2)"
[[ -f ${MONGOD_BASE_DIR}/initd_functions ]] && source ${MONGOD_BASE_DIR}/initd_functions || { echo "Error: ${MONGOD_BASE_DIR}/initd_functions is missing."; exit 3; }
THISHOSTNAME=$(hostname -s)

export PATH=${SAVED_PATH}
export LD_LIBRARY_PATH=${SAVED_LD_LIBRARY_PATH}

echo "Env: MONGOD_BASE_DIR=${MONGOD_BASE_DIR}"
echo "Env: MONGOD_DATA_DIR=${MONGOD_DATA_DIR}"
echo "Env: MONGOD_BINDIP=${MONGOD_BINDIP}"
echo "Env: PATH=${PATH}"
echo "Env: LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"

LOGS_DIR=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/logs
[[ -d ${LOGS_DIR} ]] ||  mkdir -p ${LOGS_DIR} >/dev/null 2>&1
TEMP_DIR=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/tmp
[[ -d ${TEMP_DIR} ]] ||  mkdir -p ${TEMP_DIR} >/dev/null 2>&1

MONGOD_PID=${TEMP_DIR}/mongod-${THISHOSTNAME}.pid
MONGOD_LOCK=${TEMP_DIR}/mongod-${THISHOSTNAME}.lock
MONGOD_LOG=${LOGS_DIR}/mongod-${THISHOSTNAME}-${TIMESTAMP}.log
MONGOD_KEY=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/mongod.keyfile

if [[ ! -f ${MONGOD_KEY} ]]; then
   echo "Warning: Mongod key file not found. Generating a new key file."
   openssl rand -base64 756 > ${MONGOD_KEY}
   chmod 400 ${MONGOD_KEY}
fi

function start() {
  echo "Logfile: ${MONGOD_LOG}"
  echo -n $"Info: Starting MongoDB: "
  DATA_DIR=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/data-${THISHOSTNAME}
  [[ -d ${DATA_DIR} ]] || mkdir -p ${DATA_DIR} >/dev/null 2>&1

  ${MONGOD_NUMA_CTRL} ${mongod_bin}          \
        --dbpath=${DATA_DIR}                 \
        --pidfilepath=${MONGOD_PID}          \
        --port=${MONGOD_PORT}                \
        --wiredTigerCacheSizeGB=2            \
        --bind_ip=${MONGOD_BINDIP}           \
        --logpath=${MONGOD_LOG}              \
        --logappend                          \
        --fork                               \
        --replSet rs0                        \
        --keyFile ${MONGOD_KEY}
  RETVAL=$?
  echo
  [[ $RETVAL -eq 0 ]] && touch ${MONGOD_LOCK}
}

function  start_configure(){
  echo "Logfile: ${MONGOD_LOG}"
  echo -n $"Info: Starting MongoDB in configure mode: "
  DATA_DIR=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/data-${THISHOSTNAME}
  [[ -d ${DATA_DIR} ]] || mkdir -p ${DATA_DIR} >/dev/null 2>&1

  ${MONGOD_NUMA_CTRL} ${mongod_bin}          \
        --dbpath=${DATA_DIR}                 \
        --pidfilepath=${MONGOD_PID}          \
        --port=${MONGOD_PORT}                \
        --wiredTigerCacheSizeGB=2            \
        --bind_ip=127.0.0.1                  \
        --logpath=${MONGOD_LOG}              \
        --logappend                          \
        --fork
  RETVAL=$?
  echo
  [[ $RETVAL -eq 0 ]] && touch ${MONGOD_LOCK}
}

function start_arbiter(){
  echo "Logfile: ${MONGOD_LOG%.*}-arb.log"
  echo -n $"Info: Starting MongoDB Arbiter: "
  DATA_DIR=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/arbt-${THISHOSTNAME}
  [[ -d ${DATA_DIR} ]] || mkdir -p ${DATA_DIR} >/dev/null 2>&1

  ${MONGOD_NUMA_CTRL} ${mongod_bin}             \
        --dbpath=${DATA_DIR}                    \
        --pidfilepath=${MONGOD_PID%.*}-arb.pid  \
        --port=$(( ${MONGOD_PORT} + 1 ))        \
        --bind_ip=${MONGOD_BINDIP}              \
        --wiredTigerCacheSizeGB=2               \
        --logpath=${MONGOD_LOG%.*}-arb.log      \
        --logappend                             \
        --fork                                  \
        --replSet rs0                           \
        --keyFile ${MONGOD_KEY}

  RETVAL=$?
  echo
  [[ $RETVAL -eq 0 ]] && touch ${MONGOD_LOCK%.*}-arb.lock
}

function stop(){
  echo "Logfile: $(ls -t  ${LOGS_DIR}/mongod-${THISHOSTNAME}-*.log|grep -v "arb.log" |head -1)"
  echo -n $"Info: Stopping MongoDB: "
  _killproc ${MONGOD_PID} ${mongod_bin}
  RETVAL=$?
  echo
  [[ $RETVAL -eq 0 ]] && rm -f ${MONGOD_LOCK}
}

function stop_arbiter(){
  echo "Logfile: $(ls -t  ${LOGS_DIR}/mongod-${THISHOSTNAME}-*arb.log |head -1)"
  echo -n $"Info: Stopping MongoDB Arbiter: "
  _killproc ${MONGOD_PID%.*}-arb.pid ${mongod_bin}
  RETVAL=$?
  echo
  [[ $RETVAL -eq 0 ]] && rm -f ${MONGOD_LOCK%.*}-arb.lock
}

function restart() { stop; start; }

_killproc()
{
  local pid_file=$1
  local procname=$2
  local -i delay=300
  local -i duration=10
  local pid=`pidofproc -p "${pid_file}" ${procname}`

  kill -TERM $pid >/dev/null 2>&1
  usleep 100000
  local -i x=0
  while [ $x -le $delay ] && checkpid $pid; do
    sleep $duration
    x=$(( $x + $duration))
  done

  kill -KILL $pid >/dev/null 2>&1
  usleep 100000

  checkpid $pid # returns 0 only if the process exists
  local RC=$?
  [[ "$RC" -eq 0 ]] && failure "${procname} shutdown" || rm -f "${pid_file}"; success "${procname} shutdown"
  RC=$((! $RC)) # invert return code so we return 0 when process is dead.
  return $RC
}


RETVAL=0

case "$1" in
  start)
    start
    ;;
  start_arbiter)
    start_arbiter
    ;;
  configure)
    start_configure
    ;;
  stop)
    stop
    ;;
  stop_arbiter)
    stop_arbiter
    ;;
  restart)
    restart
    ;;
  status)
    echo "Logfile: $(ls -t  ${LOGS_DIR}/mongod-${THISHOSTNAME}-*.log|grep -v "arb.log" |head -1)"
    echo -n $"Info: MongoDB Server status: "
    status -p ${MONGOD_PID} ${mongod_bin}
    RETVAL=$?
    ;;
  status_arbiter)
    echo "Logfile: $(ls -t  ${LOGS_DIR}/mongod-${THISHOSTNAME}-*arb.log |head -1)"
    echo -n $"Info: MongoDB Arbiter status: "
    status -p ${MONGOD_PID%.*}-arb.pid ${mongod_bin}
    RETVAL=$?
    ;;
  *)
    echo "Usage: $0 {start|stop|status|restart|configure|start_arbiter|stop_arbiter}"
    RETVAL=1
esac

exit $RETVAL

