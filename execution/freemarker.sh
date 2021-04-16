#!/usr/bin/env bash

[[ -n "${GENERATION_DEBUG}" ]] && set ${GENERATION_DEBUG}
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
. "${GENERATION_BASE_DIR}/execution/common.sh"

# Defaults

function usage() {
    cat <<EOF

Generate a document using the Freemarker template engine

Usage: $(basename $0) -t TEMPLATE (-d TEMPLATEDIR)+ -o OUTPUT (-v VARIABLE=VALUE)* (-g CMDB=PATH)* -b CMDB (-c CMDB)* -l LOGLEVEL

where

(o) -b CMDB           base cmdb
(o) -c CMDB           cmdb to be included
(m) -d TEMPLATEDIR    is a directory containing templates
(o) -g CMDB=PATH      defines a cmdb and the corresponding path
(o) -g PATH           finds all cmdbs under PATH based on a .cmdb marker file
    -h                shows this text
(o) -l LOGLEVEL       required log level
(m) -o OUTPUT         is the path of the resulting document
(o) -r VARIABLE=VALUE defines a variable and corresponding value to be made available in the template
(m) -t TEMPLATE       is the filename of the Freemarker template to use
(o) -v VARIABLE=VALUE defines a variable and corresponding value to be made available in the template

(m) mandatory, (o) optional, (d) deprecated

DEFAULTS:

NOTES:

1. If the value of a variable defines a path to an existing file, the contents of the file are provided to the engine
2. Values that do not correspond to existing files are provided as is to the engine
3. Values containing spaces need to be quoted to ensure they are passed in as a single argument
4. -r and -v are equivalent except that -r will not check if the provided value
   is a valid filename
5. For a cmdb located via a .cmdb marker file, cmdb name = the containing directory name

EOF
    exit
}

TEMPLATEDIRS=()
RAW_VARIABLES=()
VARIABLES=()
CMDBS=()
CMDB_MAPPINGS=()
ENGINE_OUTPUT="/dev/stdout"

# Parse options
while getopts ":b:c:d:e:g:hl:o:r:t:v:" opt; do
    case $opt in
        b)
            BASE_CMDB="${OPTARG}"
            ;;
        c)
            CMDBS+=("${OPTARG}")
            ;;
        d)
            TEMPLATEDIRS+=("${OPTARG}")
            ;;
        e)
            ENGINE_OUTPUT="${OPTARG}"
            ;;
        g)
            CMDB_MAPPINGS+=("${OPTARG}")
            ;;
        h)
            usage
            ;;
        l)
            LOGLEVEL="${OPTARG}"
            ;;
        o)
            OUTPUT="${OPTARG}"
            ;;
        r)
            RAW_VARIABLES+=("${OPTARG}")
            ;;
        t)
            TEMPLATE="${OPTARG}"
            ;;
        v)
            VARIABLES+=("${OPTARG}")
            ;;
        \?)
            fatalOption
            ;;
        :)
            fatalOptionArgument
            ;;
    esac
done

# Defaults


# Ensure mandatory arguments have been provided
exit_on_invalid_environment_variables "TEMPLATE" "OUTPUT"
[[ ("${#TEMPLATEDIRS[@]}" -eq 0) ]] && fatalMandatory "TEMPLATEDIRS" && exit 1

if [[ "${#TEMPLATEDIRS[@]}" -gt 0 ]]; then
  TEMPLATEDIRS=("-d" "${TEMPLATEDIRS[@]}")
fi

if [[ "${#VARIABLES[@]}" -gt 0 ]]; then
  VARIABLES=("-v" "${VARIABLES[@]}")
fi

if [[ "${#RAW_VARIABLES[@]}" -gt 0 ]]; then
  RAW_VARIABLES=("-r" "${RAW_VARIABLES[@]}")
fi

if [[ "${#CMDBS[@]}" -gt 0 ]]; then
  CMDBS=("-c" "${CMDBS[@]}")
fi

if [[ "${#CMDB_MAPPINGS[@]}" -gt 0 ]]; then
  CMDB_MAPPINGS=("-g" "${CMDB_MAPPINGS[@]}")
fi

java -jar "${GENERATION_ENGINE_DIR}/bin/freemarker-wrapper-1.13.0.jar" \
    -i $TEMPLATE "${TEMPLATEDIRS[@]}" \
    -o $OUTPUT \
    "${VARIABLES[@]}" \
    "${RAW_VARIABLES[@]}" \
    "${CMDB_MAPPINGS[@]}" \
    ${BASE_CMDB:+-b "${BASE_CMDB}"} \
    ${LOGLEVEL:+--${LOGLEVEL}} \
    "${CMDBS[@]}" &> ${ENGINE_OUTPUT}
RESULT=$?
