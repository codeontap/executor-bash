#!/usr/bin/env bash

[[ -n "${GENERATION_DEBUG}" ]] && set ${GENERATION_DEBUG}
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
. "${GENERATION_BASE_DIR}/execution/common.sh"

function options() {

  # Parse options
  while getopts ":f:hi:o:p:" option; do
      case "${option}" in
          f|i|o|p) TEMPLATE_ARGS="${TEMPLATE_ARGS} -${option} ${OPTARG}" ;;
          h) usage; return 1 ;;
          \?) fatalOption; return 1 ;;
      esac
  done

  return 0
}

function usage() {
  cat <<EOF

DESCRIPTION:
  Creates a blueprint of a segment providing CodeOnTap contextual information about a deployment
  The blueprint is provided as a JSON file generated by the template engine
  Includes:
    - The occurrences of all components in the solution along with their current state
    - Details of the broader contexts which form the segment
        ( tenant, account, product, solution, environment, segment )

USAGE:
  $(basename $0)

PARAMETERS:

(o) -i GENERATION_INPUT_SOURCE is the source of input data to use when generating the template
    -h                         shows this text
(o) -o OUTPUT_DIR              is the directory where the outputs will be saved - defaults to the PRODUCT_STATE_DIR
(o) -p GENERATION_PROVIDER     is a provider to load for template generation - multiple providers can be added with extra arguments
(o) -f GENERATION_FRAMEWORK    is the output framework to use for template generation

  (m) mandatory, (o) optional, (d) deprecated

CONTEXT:

  CMDBS:
    (m) Account CMDB
    (m) Product CMDB

  LOCATION:
    (m) SEGMENT_DIR

  ENVIRONMENT_VARIABLES:
    (m) ACCOUNT

DEFAULTS:

OUTPUTS:

  - File
    - Name: blueprint.json
    - Directory: "PRODUCT_INFRASTRUCTURE_DIR/cot/ENVIRONMENT/SEGMENT"

NOTES:


EOF
}

function main() {

    options "$@" || return $?

    ${GENERATION_DIR}/createTemplate.sh -e blueprint ${TEMPLATE_ARGS}
    RESULT=$?
    return "${RESULT}"
}

main "$@"
