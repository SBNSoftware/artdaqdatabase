#!/usr/bin/env bash
[[ "$0" != "$BASH_SOURCE" ]] && { echo "You should run this script!"; return 1; }
[[ -z ${SUBSHELL+x} ]] && { env -i SUBSHELL='TRUE' LANG='en_US.UTF-8' TERM=${TERM} \
  KRB5CCNAME=$(klist 2>&1 |grep cache |grep -Eo '/tmp/[a-z0-9_]+')  \
  HOME=${HOME} PATH=${PATH} PWD=${PWD} $(readlink -f $0); exit $?; }
SCRIPT_DIR=$(dirname  $(readlink -f $0))
[[ -f ${SCRIPT_DIR}/read-configuration-settings.sh ]] && \
  { USE_RUNTIME='TRUE' && source ${SCRIPT_DIR}/read-configuration-settings.sh; [[ $? == 0 ]] || exit 1; } || exit 1
echo;echo "Info: Running script $(basename $0)"
echo "----------------------------------------------------------------"
#----------------------------------------------------------------
# Optional configuration parameters, which can be
# overriden in $HOME/.mongodb_reinstall.env file if it exits.
# Main program starts at the bottom of this file.
#----------------------------------------------------------------

#----------------------------------------------------------------
# Implementaion
# Main program starts at the bottom of this file.
#----------------------------------------------------------------
function ping_hosts(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0
  for h in $(echo  "${MONGOD_HOSTS},${MONGOD_ARB_HOST}"| tr ',' ' '); do
    for hh in $h{,-daq,.fnal.gov,-daq.fnal.gov};do
      printf "Info: Pinging ${hh}: "
      ping -c 1 -t 1 $hh > /dev/null 2>&1
      [[ $? -ne 0 ]] && { printf "Failure.\n";((error_count++)); } ||  printf "Success.\n"
    done
  done

  (( error_count==0 )) && return $RC_SUCCESS

  return $RC_FAILURE
}

function check_ssh(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  configure_ssh
  local error_count=0
  for h in $(echo  "${MONGOD_HOSTS},${MONGOD_ARB_HOST}"| tr ',' ' '); do
    for hh in $h{,-daq,.fnal.gov,-daq.fnal.gov};do
      printf "Info: SSH-ing ${hh} as ${RUN_AS_USER}: "
      local result=$(ssh -F ${HOME}/.ssh/config_mongosetup ${RUN_AS_USER}@${hh} date)
      [[ ${result} == "" ]] && { printf "Failure.\n"; ((error_count++)); continue; } || printf "Success. Remote time is ${result}.\n"
    done
  done

  (( error_count==0 )) && return $RC_SUCCESS

  echo "Error: Verify your Kerberos ticket!"
  return $RC_FAILURE
}

function check_ssh_root(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  configure_ssh
  local error_count=0
  for h in $(echo  "${MONGOD_HOSTS},${MONGOD_ARB_HOST}"| tr ',' ' '); do
    for hh in $h{,.fnal.gov};do
      printf "Info: SSH-ing ${hh} as ROOT: "
      local result=$(ssh -F ${HOME}/.ssh/config_mongosetup root@${hh} whoami)
      [[ ${result} == "" ]] && { printf "Failure.\n"; ((error_count++)); continue; } || printf "Success. I'm ${result}.\n"
    done
  done

  (( error_count==0 )) && return $RC_SUCCESS

  echo "Error: You are not allowed to ssh as ROOT into one of the following hosts ${MONGOD_HOSTS}, or ${MONGOD_ARB_HOST}."
  return $RC_FAILURE
}

function check_selinux(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  configure_ssh
  local error_count=0
  for h in $(echo  "${MONGOD_HOSTS},${MONGOD_ARB_HOST}"| tr ',' ' '); do
    for hh in $h{,-daq,.fnal.gov,-daq.fnal.gov};do
      printf "Info: SELinux on ${hh} is set to "
      local result=$(ssh -F ${HOME}/.ssh/config_mongosetup ${RUN_AS_USER}@${hh} /usr/sbin/getenforce)
      [[ ${result} == "Enforcing" ]] && { printf "${result}.\n"; ((error_count++)); continue; } \
        || printf "${result}.\n"
    done
  done

  (( error_count==0 )) && return $RC_SUCCESS

  return $RC_FAILURE
}

function run_iperf_test(){
  echo "Info: Calling function ${FUNCNAME[0]}() from $(basename $0)"
  local error_count=0
  local iperf_out=/tmp/iperf-${TIMESTAMP}
  local server_hostname="$(echo ${MONGOD_HOSTS},${MONGOD_ARB_HOST}|grep -Eo "$(hostname -s)"|sort -u )"
  local server_ip=$(ping -c 1 -t 1 ${server_hostname} |grep PING |cut -d" " -f3 |grep -Eo '[0-9\.]+')

  for p in $(echo "${MONGOD_PORT} $((MONGOD_PORT+1))");do
    for client_hostname in $(echo ${MONGOD_HOSTS},${MONGOD_ARB_HOST}| sed 's/,/\n/g' |grep -v $(hostname -s)|sort -u); do
      local client_ip=$(ping -c 1 -t 1 ${client_hostname} |grep PING |cut -d" " -f3 |grep -Eo '[0-9\.]+')
      echo
      printf "Info: Running iperf between ${server_hostname}[$server_ip:$p] and ${client_hostname}[$client_ip:$p]\n"
      nohup timeout 7 iperf --server --time=6 --interval=1 --port=$p --bind=$server_ip >${iperf_out} &
      ssh -F ${HOME}/.ssh/config_mongosetup artdaq@$client_hostname${SUBNET_SUFFIX} iperf --time=5 --client=$server_ip --interval=1 --dualtest --port=$p
      cat ${iperf_out}
      (( $(cat ${iperf_out}|grep $client_ip |wc -l) == 2 )) || ((error_count+1))
    done
  done

  (( error_count==0 )) && return $RC_SUCCESS
  return $RC_FAILURE
}

function main_program(){
  verify_essential_dependencies
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: Install missing dependencies and rerun ${script_name}.\e[0m"; return $RC_FAILURE;
  }

  echo;echo
  setup_mongodb_product
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: Install MongoDB ${MONGOD_UPS_VER} into ${MONGOD_PRODUCTS_DIR} and rerun ${script_name}.\e[0m"; 
    return $RC_FAILURE; }

  echo;echo
  ping_hosts
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: Fix /etc/hosts and/or DNS records for ${MONGOD_HOSTS}, and ${MONGOD_ARB_HOST}; and rerun ${script_name}.\e[0m"; 
    return $RC_FAILURE; }

  echo;echo
  check_ssh
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: Fix SSH connectivity to ${MONGOD_HOSTS}, and ${MONGOD_ARB_HOST}; and rerun ${script_name}.\e[0m"; 
     return $RC_FAILURE;}

     echo;echo
  check_selinux
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: Ask SLAM to set the SELInux mode to permissive or disabled on ${MONGOD_HOSTS}, and ${MONGOD_ARB_HOST}.\e[0m"; 
     return $RC_FAILURE;}

  echo;echo
  check_ssh_root
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: You don’t have root login privilege on ${MONGOD_HOSTS}, and ${MONGOD_ARB_HOST}.\e[0m";
    echo -e "\e[0;7;5mInfo: Ask SLAM to run the ${INSTALL_PREFIX}/reinstall-systems.sh as root on ${MONGOD_HOSTS}.\e[0m"; }

  echo;echo
  run_iperf_test
  [[ $? -ne $RC_SUCCESS ]] && {
    echo -e "\e[31;7;5mError: Allow TCP ports ${MONGOD_PORT} and $((MONGOD_PORT+1)) thru the firewall on ${MONGOD_HOSTS}, and ${MONGOD_ARB_HOST}.\e[0m";
    return $RC_FAILURE; }

  echo
  echo -e "\e[0;7;5mInfo: All connectivity tests succeeded.\e[0m"
}

#----------------------------------------------------------------
# Main program starts here.
#----------------------------------------------------------------
main_program
