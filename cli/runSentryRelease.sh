#!/usr/bin/env bash

[[ -n "${GENERATION_DEBUG}" ]] && set ${GENERATION_DEBUG}
trap '. ${GENERATION_BASE_DIR}/execution/cleanupContext.sh' EXIT SIGHUP SIGINT SIGTERM
. "${GENERATION_BASE_DIR}/execution/common.sh"

#Defaults
DEFAULT_SENTRY_CLI_VERSION="1.67.1"
DEFAULT_RUN_SETUP="false"
DEFAULT_SENTRY_URL_PREFIX="~/"
DEFAULT_DEPLOYMENT_GROUP="application"

function env_setup() {

    # yarn install
    yarn global add \
        @sentry/cli@"${SENTRY_CLI_VERSION}" || return $?

	# make sure yarn global bin is on path
    export PATH="$(yarn global bin):$PATH"
}

function usage() {
    cat <<EOF

Upload sourcemap files to sentry for a specific release for SPA and mobile apps. DEPLOYMENT_UNIT is required to build a blueprint
to get the configuration file location. Sentry cli configuration is read from the configuration file, but for the expo
SENTRY_SOURCE_MAP_S3_URL and SENTRY_URL_PREFIX are set in the runExpoPublish script and passed as chain properties.

Usage: $(basename $0) -m SENTRY_SOURCE_MAP_S3_URL -r SENTRY_RELEASE -s -u DEPLOYMENT_UNIT

where

(o) -a APP_TYPE                     the app framework being used
(m) -u DEPLOYMENT_UNIT              deployment unit for a build blueprint
(o) -g DEPLOYMENT_GROUP             the deployment group the unit belongs to
    -h                              shows this text
(o) -m SENTRY_SOURCE_MAP_S3_URL     s3 link to sourcemap files
(o) -p SENTRY_URL_PREFIX            prefix for sourcemap files
(o) -r SENTRY_RELEASE               sentry release name
(o) -s RUN_SETUP              		run setup installation to prepare

(m) mandatory, (o) optional, (d) deprecated

DEFAULTS:
DEPLOYMENT_GROUP = ${DEFAULT_DEPLOYMENT_GROUP}

NOTES:
    Available options for APP_TYPE:
        - react-native - Updates the bundle files to align with the required format


EOF
    exit
}

function options() {

    # Parse options
    while getopts ":a:hg:m:p:r:su:" opt; do
        case $opt in
            a)
                APP_TYPE="${OPTARG}"
                ;;
            g)
                DEPLOYMENT_GROUP="${OPTARG}"
                ;;
            h)
                usage
                ;;
            m)
                SENTRY_SOURCE_MAP_S3_URL="${OPTARG}"
                ;;
            p)
                SENTRY_URL_PREFIX="${OPTARG}"
                ;;
            r)
                SENTRY_RELEASE="${OPTARG}"
                ;;
            s)
                RUN_SETUP="true"
                ;;
            u)
                DEPLOYMENT_UNIT="${OPTARG}"
                ;;
            \?)
                fatalOption
                ;;
            :)
                fatalOptionArgument
                ;;
        esac
    done

    #Defaults
    DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP:-${DEFAULT_DEPLOYMENT_GROUP}}"
    RUN_SETUP="${RUN_SETUP:-${DEFAULT_RUN_SETUP}}"
    SENTRY_CLI_VERSION="${SENTRY_CLI_VERSION:-${DEFAULT_SENTRY_CLI_VERSION}}"
    SENTRY_URL_PREFIX="${SENTRY_URL_PREFIX:-${DEFAULT_SENTRY_URL_PREFIX}}"

}


function main() {

  options "$@" || return $?

  if [[ "${RUN_SETUP}" == "true" ]]; then
    env_setup || return $?
  fi

  # Ensure mandatory arguments have been provided
  [[ -z "${DEPLOYMENT_UNIT}" ]] && fatalMandatory

  # Get the generation context so we can run template generation
  . "${GENERATION_BASE_DIR}/execution/setContext.sh"
  . "${GENERATION_BASE_DIR}/execution/setCredentials.sh"

  # Generate a build blueprint so that we can find out the source S3 bucket
  info "Generating blueprint to find details..."
  tmpdir="$(getTempDir "cote_inf_XXX")"
  ${GENERATION_DIR}/createTemplate.sh -e "buildblueprint" -p "aws" -l "${DEPLOYMENT_GROUP}" -u "${DEPLOYMENT_UNIT}" -o "${tmpdir}"
  BUILD_BLUEPRINT="${tmpdir}/buildblueprint-${DEPLOYMENT_GROUP}-${DEPLOYMENT_UNIT}-config.json"

  if [[ ! -f "${BUILD_BLUEPRINT}" || -z "$(cat ${BUILD_BLUEPRINT} )" ]]; then
      fatal "Could not generate blueprint for task details"
      return 255
  fi

  SOURCE_MAP_PATH="${AUTOMATION_DATA_DIR}/source_map"
  OPS_PATH="${AUTOMATION_DATA_DIR}/ops"

  mkdir -p "${SOURCE_MAP_PATH}"
  mkdir -p "${OPS_PATH}"

  # get config file
  CONFIG_BUCKET="$( jq -r '.Occurrence.State.Attributes.CONFIG_BUCKET' < "${BUILD_BLUEPRINT}" )"
  CONFIG_KEY="$( jq -r '.Occurrence.State.Attributes.CONFIG_FILE' < "${BUILD_BLUEPRINT}" )"
  CONFIG_FILE="${OPS_PATH}/config.json"

  info "Gettting configuration file from s3://${CONFIG_BUCKET}/${CONFIG_KEY}"
  aws --region "${AWS_REGION}" s3 cp "s3://${CONFIG_BUCKET}/${CONFIG_KEY}" "${CONFIG_FILE}" || return $?

  # attempting to read sentry configuration parameter from the configuration file if it is not passed as an argument
  # configuration file for expo builds contains .AppConfig element
  # Note: for the expo builds SENTRY_SOURCE_MAP_S3_URL and SENTRY_URL_PREFIX are passed as arguments
  # because the sources and maps are uploaded to the OTA_ARTEFACT_BUCKET considering expo sdk version, which is set in app.json
  # there is no point duplicate expo sdk version as a setting in CMDB and it doesn't make sense to checkout the code to read it at this stage
  [[ -z "${SENTRY_SOURCE_MAP_S3_URL}" ]] && SENTRY_SOURCE_MAP_S3_URL="$( jq -r '.SENTRY_SOURCE_MAP_S3_URL' <"${CONFIG_FILE}" )"
  [[ -z "${SENTRY_URL_PREFIX}" ]] && SENTRY_URL_PREFIX="$( jq -r '.SENTRY_URL_PREFIX' <"${CONFIG_FILE}" )"
  [[ -z "${SENTRY_RELEASE}" ]] && SENTRY_RELEASE="$( jq -r 'if .AppConfig? then .AppConfig.SENTRY_RELEASE else .SENTRY_RELEASE end' <"${CONFIG_FILE}" )"
  [[ -z "${SENTRY_PROJECT}" ]] && SENTRY_PROJECT="$( jq -r 'if .AppConfig? then .AppConfig.SENTRY_PROJECT else .SENTRY_PROJECT end' <"${CONFIG_FILE}" )"
  [[ -z "${SENTRY_URL}" ]] && SENTRY_URL="$( jq -r 'if .AppConfig? then .AppConfig.SENTRY_URL else .SENTRY_URL end' <"${CONFIG_FILE}" )"
  [[ -z "${SENTRY_ORG}" ]] && SENTRY_ORG="$( jq -r 'if .AppConfig? then .AppConfig.SENTRY_ORG else .SENTRY_ORG end' <"${CONFIG_FILE}" )"

  [[ "${SENTRY_SOURCE_MAP_S3_URL}" == "null" || -z "${SENTRY_SOURCE_MAP_S3_URL}" ]] && fatal "SENTRY_SOURCE_MAP_S3_URL is required but was not defined"
  [[ "${SENTRY_RELEASE}" == "null" || -z "${SENTRY_RELEASE}" ]] &&  fatal "SENTRY_RELEASE is required but was not defined"
  [[ "${SENTRY_URL_PREFIX}" == "null" || -z "${SENTRY_URL_PREFIX}" ]] &&  fatal "SENTRY_URL_PREFIX is required but was not defined"
  [[ "${SENTRY_PROJECT}" == "null" || -z "${SENTRY_PROJECT}" ]] &&  fatal "SENTRY_PROJECT is required but was not defined"
  [[ "${SENTRY_URL}" == "null" || -z "${SENTRY_URL}" ]] &&  fatal "SENTRY_URL is required but was not defined"
  [[ "${SENTRY_ORG}" == "null" || -z "${SENTRY_ORG}" ]] &&  fatal "SENTRY_ORG is required but was not defined"

  #making sure sentry config is available to sentry cli
  export SENTRY_PROJECT=$SENTRY_PROJECT
  export SENTRY_URL=$SENTRY_URL
  export SENTRY_ORG=$SENTRY_ORG

  info "Getting source code from from ${SENTRY_SOURCE_MAP_S3_URL}"
  aws --region "${AWS_REGION}" s3 cp --recursive "${SENTRY_SOURCE_MAP_S3_URL}" "${SOURCE_MAP_PATH}" || return $?

  info "Creating a new release ${SENTRY_RELEASE}"
  sentry-cli releases new "${SENTRY_RELEASE}" || return $?

  info "Uploading source maps for the release ${SENTRY_RELEASE}"

  upload_args=()

  case "${APP_TYPE}" in
    "react-native")

        android_bundle="$( find "${SOURCE_MAP_PATH}" -type f -name "android-*.js" )"
        if [[ -n "${android_bundle}" ]]; then
            mv "${android_bundle}" "${SOURCE_MAP_PATH}/index.android.bundle"
        fi

        android_map="$( find "${SOURCE_MAP_PATH}" -type f -name "android-*.map" )"
        if [[ -n "${android_map}" ]]; then
            mv "${android_map}" "${SOURCE_MAP_PATH}/index.android.bundle.map"
        fi

        ios_bundle="$( find "${SOURCE_MAP_PATH}" -type f -name "ios-*.js" )"
        if [[ -n "${ios_bundle}" ]]; then
            mv "${ios_bundle}" "${SOURCE_MAP_PATH}/main.jsbundle"
        fi

        ios_map="$( find "${SOURCE_MAP_PATH}" -type f -name "ios-*.map" )"
        if [[ -n "${ios_map}" ]]; then
            mv "${ios_map}" "${SOURCE_MAP_PATH}/main.jsbundle.map"
        fi
    ;;

  esac

  if [[ -n "${SENTRY_URL_PREFIX}" ]]; then
    upload_args+=("--url-prefix" "${SENTRY_URL_PREFIX}")
  fi

  pushd "${SOURCE_MAP_PATH}"
  sentry-cli releases files "${SENTRY_RELEASE}" upload-sourcemaps "${SOURCE_MAP_PATH}" --rewrite --validate "${upload_args[@]}" || return $?
  popd

  info "Finalising the release ${SENTRY_RELEASE}"
  sentry-cli releases finalize "${SENTRY_RELEASE}" || return $?

  DETAIL_MESSAGE="${DETAIL_MESSAGE} Source map files uploaded for the release ${SENTRY_RELEASE}."
  echo "DETAIL_MESSAGE=${DETAIL_MESSAGE}" >> ${AUTOMATION_DATA_DIR}/context.properties

  # All good
  return 0
}

main "$@" || exit $?
