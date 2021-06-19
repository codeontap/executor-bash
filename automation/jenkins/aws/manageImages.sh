#!/usr/bin/env bash

[[ -n "${AUTOMATION_DEBUG}" ]] && set ${AUTOMATION_DEBUG}
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
. "${AUTOMATION_BASE_DIR}/common.sh"


function usage() {
    cat <<EOF

Manage images corresponding to the current build

Usage: $(basename $0) -c REGISTRY_SCOPE -g CODE_COMMIT -u DEPLOYMENT_UNIT -f IMAGE_FORMATS

where

(o) -c REGISTRY_SCOPE  is the registry scope for the image
(o) -d DOCKERFILE      is the path to a Dockerfile to build a docker image from
(o) -e DOCKER_CONTEXT  is the context directory to run the docker build from
(m) -f IMAGE_FORMATS   is the comma separated list of image formats to manage
(m) -g CODE_COMMIT     to use when defaulting REGISTRY_REPO
(o) -i IMAGE_FILES     is list of paths to image files you want to provide to the registry
(o) -t DOCKER_IMAGE    is a docker tag of a built image to provide to the registry instead of a dockerfile
(m) -u DEPLOYMENT_UNIT is the deployment unit associated with the images

(m) mandatory, (o) optional, (d) deprecated

DEFAULTS:

DEPLOYMENT_UNIT=First entry in DEPLOYMENT_UNIT_LIST
CODE_COMMIT=First entry in CODE_COMMIT_LIST
IMAGE_FORMATS=First entry in IMAGE_FORMAT_LIST
REGISTRY_SCOPE=First entry in REGISTRY_SCOPE_LIST

NOTES:

IMAGE_FILES is optional and instead a fixed filename is used for zip based on the format
    ${AUTOMATION_BUILD_SRC_DIR}/dist/{image_format}.zip

For multiple IMAGE_FORMATS, IMAGE_FILES must be provided in the same order as their corresponding format

To provide multiple images or formats use a separated list based on the separators used by IMAGE_FORMAT_SEPERATORS
    ${IMAGE_FORMAT_SEPARATORS}

EOF
    exit
}

function options() {
    # Parse options
    while getopts ":c:d:e:f:g:hi:s:t:u:" opt; do
        case $opt in
            c)
                REGISTRY_SCOPE="${OPTARG}"
                ;;
            d)
                DOCKERFILE="${OPTARG}"
                ;;
            e)
                DOCKER_CONTEXT="${OPTARG}"
                ;;
            f)
                IMAGE_FORMATS="${OPTARG}"
                ;;
            g)
                CODE_COMMIT="${OPTARG}"
                ;;
            h)
                usage
                ;;
            i)
                IMAGE_FILES="${OPTARG}"
                ;;
            t)
                DOCKER_IMAGE="${OPTARG}"
                ;;
            u)
                DEPLOYMENT_UNIT="${OPTARG}"
                ;;
            \?)
                fatalOption; exit
                ;;
            :)
                fatalOptionArgument; exit
                ;;
        esac
    done

    # Apply defaults
    DEPLOYMENT_UNIT_ARRAY=(${DEPLOYMENT_UNIT_LIST})
    CODE_COMMIT_ARRAY=(${CODE_COMMIT_LIST})
    IMAGE_FORMATS_ARRAY=(${IMAGE_FORMATS_LIST})
    REGISTRY_SCOPE_ARRAY=(${REGISTRY_SCOPE_LIST})

    DEPLOYMENT_UNIT="${DEPLOYMENT_UNIT:-${DEPLOYMENT_UNIT_ARRAY[0]}}"
    CODE_COMMIT="${CODE_COMMIT:-${CODE_COMMIT_ARRAY[0]}}"
    IMAGE_FORMATS="${IMAGE_FORMATS:-${IMAGE_FORMATS_ARRAY[0]}}"
    REGISTRY_SCOPE="${REGISTRY_SCOPE:-${REGISTRY_SCOPE_ARRAY[0]}}"

    # Ensure mandatory arguments have been provided
    exit_on_invalid_environment_variables "DEPLOYMENT_UNIT" "CODE_COMMIT" "IMAGE_FORMATS"

    IFS="${IMAGE_FORMAT_SEPARATORS}" read -ra FORMATS <<< "${IMAGE_FORMATS}"
    IFS="${IMAGE_FORMAT_SEPARATORS}" read -ra FILES <<< "${IMAGE_FILES}"
}


function main() {

    options "$@" || return $?

    # Create temp dir
    if [[ -n "${FILES}" ]]; then
    pushTempDir "${FUNCNAME[0]}_XXXXXX"
    image_dir="$(getTopTempDir)"
    fi

    for index in "${!FORMATS[@]}"; do
        FORMAT="${FORMATS[index]}"
        case ${FORMAT,,} in

            dataset)
                IMAGE_FILENAME="cot_data_file_manifest.json"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"
                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${AUTOMATION_BUILD_SRC_DIR}/${IMAGE_FILENAME}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/manageDataSetS3.sh -s \
                        -u "${DEPLOYMENT_UNIT}" \
                        -g "${CODE_COMMIT}" \
                        -f "${IMAGE_FILE}" \
                        -b "${S3_DATA_STAGE}" \
                        -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "dataset manifest ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return 1
                fi
                ;;

            rdssnapshot)
                ${AUTOMATION_DIR}/manageDataSetRDSSnapshot.sh -s \
                        -u "${DEPLOYMENT_UNIT}" \
                        -g "${CODE_COMMIT}" \
                        -c "${REGISTRY_SCOPE}" || return $?
                ;;

            docker)

                docker_args=()
                if [[ -z "${DOCKERFILE}" ]]; then

                    # Find a dockerfile based on the build src
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    DOCKERFILE="${AUTOMATION_BUILD_SRC_DIR}/Dockerfile"
                    if [[ -f "${AUTOMATION_BUILD_DEVOPS_DIR}/docker/Dockerfile" ]]; then
                        DOCKERFILE="${AUTOMATION_BUILD_DEVOPS_DIR}/docker/Dockerfile"
                    fi
                    if [[ -n "${DOCKER_FILE}" && -f "${AUTOMATION_DATA_DIR}/${DOCKER_FILE}" ]]; then
                        DOCKERFILE="${AUTOMATION_DATA_DIR}/${DOCKER_FILE}"
                    fi
                    docker_args+=("-y" "${DOCKER_FILE}")
                else

                    # Override the standard Dockerfile with your own
                    docker_args+=("-y" "${DOCKERFILE}")

                    if [[ -n "${DOCKER_CONTEXT}" ]]; then
                        docker_args+=("-x" "${DOCKER_CONTEXT}")
                    fi
                    pushd "$(pwd)" > /dev/null
                fi

                # Skip the build process and just use the provided image
                if [[ -n "${DOCKER_IMAGE}" ]]; then
                    docker_args+=("-w" "${DOCKER_IMAGE}")
                fi

                if [[ -f "${DOCKERFILE}" || -n "${DOCKER_IMAGE}" ]]; then
                    ${AUTOMATION_DIR}/manageDocker.sh -b \
                        -s "${DEPLOYMENT_UNIT}" \
                        -g "${CODE_COMMIT}" \
                        -c "${REGISTRY_SCOPE}" \
                        "${docker_args[@]}" || return $?
                    popd > /dev/null
                else
                    fatal "Dockerfile ${DOCKERFILE} missing"
                    return 1
                fi
                ;;

            lambda)
                IMAGE_FILENAME="lambda.zip"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"
                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${AUTOMATION_BUILD_SRC_DIR}/dist/${IMAGE_FILENAME}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/manageLambda.sh -s \
                            -u "${DEPLOYMENT_UNIT}" \
                            -g "${CODE_COMMIT}" \
                            -f "${IMAGE_FILE}" \
                            -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "lambda image ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return 1
                fi
                ;;

            pipeline)
                IMAGE_FILENAME="pipeline.zip"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"
                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${AUTOMATION_BUILD_SRC_DIR}/dist/${IMAGE_FILENAME}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/managePipeline.sh -s \
                            -u "${DEPLOYMENT_UNIT}" \
                            -g "${CODE_COMMIT}" \
                            -f "${IMAGE_FILE}" \
                            -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "pipeline image ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return 1
                fi
                ;;

            scripts)
                IMAGE_FILENAME="scripts.zip"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"

                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${AUTOMATION_BUILD_SRC_DIR}/dist/${IMAGE_FILENAME}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/manageScripts.sh -s \
                            -u "${DEPLOYMENT_UNIT}" \
                            -g "${CODE_COMMIT}" \
                            -f "${IMAGE_FILE}" \
                            -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "scripts image ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return $?
                fi
                ;;

            openapi|swagger)
                IMAGE_FILENAME="${FORMAT,,}.zip"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"
                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${IMAGE_FILE:-${AUTOMATION_BUILD_SRC_DIR}/dist/${IMAGE_FILENAME}}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/manageOpenapi.sh -s \
                            -y "${FORMAT,,}" \
                            -f "${IMAGE_FILE}" \
                            -u "${DEPLOYMENT_UNIT}" \
                            -g "${CODE_COMMIT}" \
                            -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "openapi/swagger image ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return 1
                fi
                ;;

            spa)
                IMAGE_FILENAME="spa.zip"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"
                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${AUTOMATION_BUILD_SRC_DIR}/dist/${IMAGE_FILENAME}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/manageSpa.sh -s \
                            -u "${DEPLOYMENT_UNIT}" \
                            -g "${CODE_COMMIT}" \
                            -f "${IMAGE_FILE}" \
                            -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "spa image ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return 1
                fi
                ;;

            contentnode)
                IMAGE_FILENAME="contentnode.zip"
                if [[ -n "${FILES[index]}" ]]; then
                    pushd "$(pwd)" > /dev/null
                    USER_IMAGE="${FILES[index]}"
                    IMAGE_FILE="${image_dir}/${IMAGE_FILENAME}"
                    if [[ -f "${USER_IMAGE}" ]]; then
                        cp "${USER_IMAGE}" "${IMAGE_FILE}"
                    fi
                else
                    pushd "${AUTOMATION_BUILD_DIR}" > /dev/null
                    IMAGE_FILE="${AUTOMATION_BUILD_SRC_DIR}/dist/${IMAGE_FILENAME}"
                fi

                if [[ -f "${IMAGE_FILE}" ]]; then
                    ${AUTOMATION_DIR}/manageContentNode.sh -s \
                            -u "${DEPLOYMENT_UNIT}" \
                            -g "${CODE_COMMIT}" \
                            -f "${IMAGE_FILE}" \
                            -c "${REGISTRY_SCOPE}" || return $?
                    popd > /dev/null
                else
                    fatal "contentnode image ${USER_IMAGE:-${IMAGE_FILE}} missing"
                    return 1
                fi
                ;;

            *)
                fatal "Unsupported image format \"${FORMAT}\""
                return 1
                ;;
        esac
    done

    return 0
}

main "$@" || { RESULT=$?; exit $?; }
RESULT=$?
