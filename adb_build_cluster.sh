#!/usr/bin/env bash

set -euo pipefail

TOKEN="${ADB_TOKEN}"

function cmdline() {
	while getopts "j:n:e:h:t:" arg; do
	  case $arg in
	    j) JSON_FILE=${OPTARG};;
	    n) NAME=${OPTARG^^};;
	    e) ENVIRONMENT=${OPTARG^^};;
	    h) HOST=${OPTARG};;
		  *) exit 1;;
	  esac
	done

	return 0
}

function check_args() {
	if [[ ${#JSON_FILE} -eq 0 ]]; then
		echo "Problem with -j JSON_FILE (=${JSON_FILE}) argument"
		usage
		exit 1
	elif [[ ${#HOST} -eq 0 ]]; then
		echo "Problem with -h HOST (=${HOST}) argument"
		usage
		exit 1
	elif [[ ${#ENVIRONMENT} -eq 0 ]]; then
		echo "Problem with -e ENVIRONMENT (=${ENVIRONMENT}) argument"
    	usage
    	exit 1
	elif [[ ${#TOKEN} -eq 0 ]]; then
		echo "Problem with ADB_TOKEN environment argument"
		usage
		exit 1
	fi

	echo "Final values are"
	echo "JSON_FILE     = ${JSON_FILE}"
	echo "ENVIRONMENT   = ${ENVIRONMENT}"
	echo "NAME          = ${NAME}"
	echo "HOST          = ${HOST}"
}

function usage() {
	echo "required options are -j <json_file> -e <environment> -h <hostname>"
	echo "optional arguments are -n <cluster name>"
	echo "databricks secret token is passed in via envvar ADB_TOKEN"
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

function check_clusters() {
	local CLUSTERNAME=$1
	local RESULT
	local RE

	RESULT="$(databricks clusters list)"

	if [[ ${RESULT} == *"Error 403"* ]]; then
		echo "Possibly bad ADB access token - should you regenerate ? - exiting"
		exit 2
	elif [[ ${RESULT} == *"Failed to establish a new connection"* ]]; then
		echo "Possibly bad network - exiting"
		exit 2
	else
		RE="^.* ${CLUSTERNAME} .*$"

		if [[ "$RESULT" =~ $RE ]]; then
			echo "found"
    else
      echo "missing"
		fi
	fi
}

function set_cluster_name() {
	local ENV=$1
	local NAME=$2

	if [[ $# -eq 2 && ${#NAME} -gt 0 ]]; then
		echo "${NAME^^}"
	else
		echo "EDP_${ENV^^}_ADB_CLUSTER1"
	fi
}

function build_cluster() {
	local CLUSTERNAME=$1
	local JSON_FILE=$2

	rm -f ~/adb_cluster_output.json
	sed "s/CLUSTERNAME/${CLUSTERNAME}/" "${JSON_FILE}" > ~/adb_cluster_output.json

	RESULT=$(databricks clusters create --json-file ~/adb_cluster_output.json)
  STATUS=$?

	if [[ $STATUS -ne 0 ]]; then
	  echo "create cluster failed - ${RESULT}"
	  exit 1
	fi

	CLUSTERID=$(echo "${RESULT}" | jq '.cluster_id' | sed 's/"//g')

	echo "$CLUSTERID"
}

function get_cluster_id() {
  local CLUSTERNAME=$1
  local CLUSTERID

  CLUSTERID=$(databricks clusters list --output json | jq -r -c --arg CLUSTERNAME "${CLUSTERNAME}" '.clusters[] | select(.cluster_name==$CLUSTERNAME) | .cluster_id')

  echo "${CLUSTERID}"
}

function update_cluster_id_secret() {
	echo "Update cluster secret"
	local CLUSTERID=$1
	local KEY_NAME=${2,,}
	local VAULT=$3

	if secret=$(az keyvault secret show --name "${KEY_NAME}" --vault-name "${VAULT}" --output json | jq -r '.value'); then
    echo "existing secret, check it"
    if [[ "${secret}" == "${CLUSTERID}" ]]; then
        echo "current secret matches CLUSTER_ID, no need to set"
      else
        echo "current secret is different to cluster id, save"
        set_secret "${CLUSTERID}" "${KEY_NAME}" "${VAULT}"
      fi
  else
    echo "no existing secret - set it"
    set_secret "${CLUSTERID}" "${KEY_NAME}" "${VAULT}"
  fi
}

function set_secret() {
	echo "Update cluster secret"
	local CLUSTERID=$1
	local KEY_NAME=${2,,}
	local VAULT=$3
  local result

   if result=$(az keyvault secret set --name "${KEY_NAME}" --value "${CLUSTERID}" --vault-name "${VAULT}" --disabled false); then
      echo "setting key ${KEY_NAME} to CLUSTER_ID ${CLUSTERID} succeeded"
    else
      echo "setting key ${KEY_NAME} to CLUSTER_ID ${CLUSTERID} failed - ${result}"
      exit 3
    fi
}

function show_clusters() {
	databricks clusters list
}

echo "raw arguments are $*"
echo "process command line args"
cmdline "$@"

echo "check argument validity"
check_args

echo "create ADB config file"
set_databrickscfg_file "${HOST}" "${TOKEN}"

echo "current workspaces"
WORKSPACES=$(databricks workspace list)
echo "${WORKSPACES}"

echo "determine clustername from ENVIRONMENT(=${ENVIRONMENT}) and NAME(=${NAME})"

CLUSTERNAME=$(set_cluster_name "${ENVIRONMENT}" "${NAME}")

echo "clustername set to ${CLUSTERNAME}"

echo "show current clusters"
CLUSTERS=$(show_clusters "${ENVIRONMENT}")
echo "current clusters are ${CLUSTERS}"

echo "check if cluster ${CLUSTERNAME} exists"
RESULT=$(check_clusters "${CLUSTERNAME}")

echo "RESULT = ${RESULT}"

if [[ ${RESULT} == "found" ]]; then
	echo "cluster ${CLUSTERNAME} already exists, create not required"

  echo "obtain the cluster_id for ${CLUSTERNAME}"

  CLUSTERID=$(get_cluster_id "${CLUSTERNAME}")
else
  echo "cluster ${CLUSTERNAME} does not exist, create"

  CLUSTERID=$(build_cluster "${CLUSTERNAME}" "${JSON_FILE}")
  EXIT_CODE=$?

  echo "Cluster creation result is ${EXIT_CODE}"
  echo "cluster_id - |${CLUSTERID}|"
  EXIT_CODE=$?
fi

echo "SAVE_CLUSTER==${SAVE_CLUSTER}"

if [[ "${SAVE_CLUSTER,,}" == "true" ]]; then
  echo "save cluster-id secret ${CLUSTERID} to key vault"
  update_cluster_id_secret "${CLUSTERID}" "cluster-id" "${ADB_KV_NAME}"
  EXIT_CODE=$?
  echo "save cluster exit code is ${EXIT_CODE}"
else
  EXIT_CODE="unrequired"
fi

echo "EXIT_CODE is ${EXIT_CODE}"

exit 0