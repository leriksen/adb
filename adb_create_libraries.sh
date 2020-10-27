#!/usr/bin/env bash

set -euo pipefail

function cmdline() {
	while getopts "l:h:" arg; do
	  case $arg in
	    l) LIBRARIES=${OPTARG};;
	    h) HOST=${OPTARG};;
		  *) exit 1;;
	  esac
	done

	return 0
}

function check_args() {
	if [[ ${#LIBRARIES} -eq 0 ]]; then
		echo "Problem with -l LIBRARIES (=${LIBRARIES}) argument"
		usage
		exit 1
	elif [[ ${#CLUSTER_ID} -eq 0 ]]; then
		echo "Problem with CLUSTER_ID (=${CLUSTER_ID}) environment argument"
		usage
		exit 1
	elif [[ ${#HOST} -eq 0 ]]; then
		echo "Problem with -h HOST (=${HOST}) argument"
		usage
		exit 1
	elif [[ ${#ADB_TOKEN} -eq 0 ]]; then
		echo "Problem with ADB_ADB_TOKEN environment argument"
		usage
		exit 1
	fi

	echo "Final values are"
	echo "LIBRARIES  = ${LIBRARIES}"
	echo "CLUSTER_ID = ${CLUSTER_ID^^}"
	echo "HOST       = ${HOST}"
}

function usage() {
	echo "required options are -l <libraries> -h <hostname>"
	echo "databricks cluster id is passed in via envvar CLUSTER_ID"
	echo "databricks secret token is passed in via envvar ADB_ADB_TOKEN"
}

function set_databrickscfg_file() {
	local HOST=$1
	local TOKEN=$2

	## note this overwrites the users .databrickscfg - but as this is automation, that doesnt matter
	## be careful if you run this on your own env
	cat > ~/.databrickscfg <<-EOF
		[DEFAULT]
		host = ${HOST}
		token = ${TOKEN}
	EOF
}

function get_cluster_state() {
  local CLUSTER_ID=$1

  RESULT=$(databricks clusters get --cluster-id "${CLUSTER_ID}" | jq -r '.state')

  echo "${RESULT}"
}

function start_cluster() {
	local CLUSTER_ID=$1

  RESULT=$(get_cluster_state "${CLUSTER_ID}")

  if [[ "${RESULT}" != "RUNNING" ]]; then

    echo "cluster in state ${RESULT} - start"

    databricks clusters start --cluster-id "${CLUSTER_ID}"

    RESULT=$(get_cluster_state "${CLUSTER_ID}")

    while [[ "${RESULT}" != "RUNNING" ]]; do
      sleep 5
      RESULT=$(get_cluster_state "${CLUSTER_ID}")
      echo "waiting - current state ${RESULT}"
    done
  else
    echo "Already running, continue"
  fi
}

function install_library() {
	local LIBRARY=$1
	local CLUSTER_ID=$2

  databricks libraries install --cluster-id "${CLUSTER_ID}" --pypi-package "${LIBRARY}"
}

echo "raw arguments are $*"
echo "process command line args"
cmdline "$@"

echo "check argument validity"
check_args

echo "create ADB config file"
set_databrickscfg_file "${HOST}" "${ADB_TOKEN}"

# libraries wont install if cluster is terminated, start
echo "starting cluster in case it was terminated"
RESULT=$(start_cluster "${CLUSTER_ID}")
echo "start cluster result = ${RESULT}"

# assume all libs in PyPI for now
# split the LIBRARIES into an array of entries
IFS=',' read -ra LIBS <<< "${LIBRARIES}"

# install each lib in turn
for library in "${LIBS[@]}"; do
    echo "install PyPI library ${library}"
    install_library "${library}" "${CLUSTER_ID}"
done

EXIT_CODE=$?

echo "EXIT_CODE is ${EXIT_CODE}"

exit "${EXIT_CODE}"