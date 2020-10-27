#!/usr/bin/env bash

# copies all secrets from ADB_KV_NAME, from var group, to databricks backed scope of same name
set -euo pipefail

function isElementOf(){
  local entry required="$1"
  shift # drop first arg, for without an 'in' iterates over args
  for entry; do
    [[ "${entry}" == "${required}" ]] && return
  done
  false
}

# determine if the scope we are updating is a ADB-backed scope, in which case we proceed,
# or a AKV-backed scope, in which case we do not need to proceed
function getScopeBacking() {
  local REQUIRED_SCOPE=$1
  
  BACKEND_TYPE=$(databricks secrets list-scopes --output json | jq -r -c --arg SCOPE "${REQUIRED_SCOPE}" '.scopes[] | select(.name==$SCOPE) | .backend_type')

  echo "${BACKEND_TYPE}"
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

function checkArgs() {
  # ENVIRONMENT envvar can be one of the entries in the "ENV" array below, in upper, lower or mixed-case
  : "${ENVIRONMENT?Need to set ENVIRONMENT}"
  : "${ADB_TOKEN?Need to set ADB_TOKEN}"
  : "${WRITE_KEYS}?Need to set WRITE_KEYS"
  : "${HOST}?Need to set HOST"
  : "${ADB_SCOPE_NAME}?Need to set output scope name"
  : "${ADB_KV_NAME}?Need to set input KV name"

  declare -a ENVS=("DEV" "PRD")

  if ! isElementOf "${ENVIRONMENT^^}" "${ENVS[@]}" ; then
  echo "ENVIRONMENT must be one of ${ENVS[*]}" && exit 1
  fi

  echo "Args ok"
  echo "ENVIRONMENT    == ${ENVIRONMENT}"
  echo "WRITE_KEYS     == ${WRITE_KEYS}"
  echo "HOST           == ${HOST}"
  echo "ADB_SCOPE_NAME == ${ADB_SCOPE_NAME}"
  echo "ADB_KV_NAME    == ${ADB_KV_NAME}"
}

if [[ "${WRITE_KEYS}" == "false" ]]; then
  echo "no keys need to be written, exitting"
  exit 0
fi

echo "raw arguments are $*"

echo "check argument validity"
checkArgs

echo "create ADB config file"
set_databrickscfg_file "${HOST}" "${ADB_TOKEN}"

echo "Determine scope backing"
BACKING=$(getScopeBacking "${ADB_SCOPE_NAME}")

echo "BACKING=${BACKING}"

if [[ "${BACKING}" == "AZURE_KEYVAULT" ]]; then
  echo "keyvault backed scope, no secret population required"
  exit 0
elif [[ "${#BACKING}" -eq 0 ]]; then
  echo "error - no scope found in ADB, exiting"
  exit 1
else
  echo "Databricks-backed scope found, populate"
fi

echo "Copy secrets from key vault ${ADB_KV_NAME} to databricks-backed scope ${ADB_SCOPE_NAME}"

# copy all the secrets from the KV to the scope
for secret_key in $(az keyvault secret list --vault-name "${ADB_KV_NAME}" --query '[].name' | jq -r '.[]'); do
  secret_val=$(az keyvault secret show --vault-name "${ADB_KV_NAME}" --name "${secret_key}" --output json | jq -r '.value')

  echo "secret is ${secret_key}"
  databricks secrets put --scope "${ADB_SCOPE_NAME}" --key "${secret_key}" --string-value "${secret_val}"
done
