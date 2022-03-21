#!/bin/bash
MONGOD_BASE_DIR=$(dirname $(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P))
MONGOD_DATA_DIR=$(basename $(dirname $(realpath $(find $MONGOD_BASE_DIR -name mongod.env))))

MONGOD_ENV_FILE=${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/mongod.env

if [[ ! -f ${MONGOD_ENV_FILE} ]]; then
        echo "Error: ${MONGOD_ENV_FILE} not found! Aborting."; exit 1 ; else
        source ${MONGOD_ENV_FILE}
fi

for d in $(ls -d ${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/{logs,data}-$(hostname -s){,-arb} 2>/dev/null); do echo rm -rf $d; done
echo rm -rf ${MONGOD_BASE_DIR}/${MONGOD_DATA_DIR}/var

