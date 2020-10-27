#!/usr/bin/env bash
set -euo pipefail

TOKEN="${ADB_TOKEN}"

cmdline() {
	while getopts "s:h:" arg; do
	  case $arg in
	    s) SCOPE=${OPTARG};;
	    h) HOST=${OPTARG};;
		  *) exit 1;;
	  esac
	done

	return 0
}

check_args() {
	if [[ ${#SCOPE} -eq 0 ]]; then
	  echo "Problem with -s SCOPE (=${SCOPE}) argument"
		echo usage
		exit 1
	elif [[ ${#HOST} -eq 0 ]]; then
    echo "Problem with -h HOST (=${HOST}) argument"
		echo usage
		exit 1
	elif [[ ${#TOKEN} -eq 0 ]]; then
    echo "Problem with ADB_TOKEN environment variable"
		echo usage
		exit 1
	fi

	echo "Final values are"
	echo "SCOPE=$SCOPE"
	echo "HOST =$HOST"
}

usage() {
	echo "required option is -s <scope name>"
	echo "required envvar is ADB_TOKEN"
	echo "optional argument is -h <hostname>, which defaults to 'https://australiaeast.azuredatabricks.net'"
}

set_databrickscfg_file() {
	local HOST=$1
	local TOKEN=$2

	## note this overwrites the users .databrickscfg - but as this is automation, that doesnt matter
	## be careful if you run this on your own machine
	cat > ~/.databrickscfg <<-EOF
		[DEFAULT]
		host = ${HOST}
		token = ${TOKEN}
	EOF
}

check_scope() {
  local RESULT
	local SCOPES

  SCOPES=$(databricks secrets list-scopes --output JSON)

	RESULT=$(echo "$SCOPES" | jq -r --arg REQUIRED "${SCOPE}" '.scopes[] | select(.name==$REQUIRED) | .name')

	if [[ ${RESULT} == *"Error 403"* ]]; then
		echo "Possibly bad ADB access token - should you regenerate ? - exiting"
		exit 2
	elif [[ ${RESULT} == *"Failed to establish a new connection"* ]]; then
		echo "Possibly bad network - exiting"
		exit 2
	fi

  # found a scope matching our regex
  if [[ $RESULT =~ $SCOPE ]]; then
    echo "EXISTS"
  else
    echo "MISSING"
  fi
}

# eventually this can replaced with linking to a kv of the same name
create_scope() {
	local SCOPE=$1

  CMD="databricks secrets create-scope --scope \"${SCOPE}\""

  echo "CMD is ${CMD}"

  RESULT=$(${CMD})
}

if [[ "${TYPE,,}" != "standard" ]]; then
  echo "only standard cluster builds scopes, exitting"
  exit 0
fi

echo "raw arguments are $*"
echo "process command line args"
cmdline "$@"

echo "check argument validity"
check_args

echo "create databricks config file"
set_databrickscfg_file "${HOST}" "${TOKEN}"

echo "check if scope ${SCOPE} already exists"
RESULT=$(check_scope "${SCOPE}")

echo "RESULT==${RESULT}"

if [[ ${RESULT} == "EXISTS" ]]; then
	echo "scope ${SCOPE} already exists, no need to create"
	exit 0
fi

echo "scope ${SCOPE} does not exist, create"

create_scope "${SCOPE}" # produces no output

EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "scope creation for ${SCOPE} failed"
else
  echo "scope creation  for ${SCOPE} succeeded"
fi

exit $EXIT_CODE
