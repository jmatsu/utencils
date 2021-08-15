#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

readonly OUTPUT_DIR="$(mktemp -d)"

usage() {
  cat <<EOF >&2
Usage:

  circleci-pipeline-execute -h
  circleci-pipeline-execute [-v] --token <personal token> --slug <slug> --branch <branch> [--parameters-file <file>] [--output <path>|--wait]

Execute the pipeline of the specified branch in the repository. Support executions with parameters by passing a file that declare them.

Options:
-h, --help        Print this help and exit
-v, --verbose     Print script debug info
-t, --token       An API Token. Personal Token is required to execute the pipeline. 
-s, --slug        CircleCI project slug. e.g. github/jmatsu/utencils
-b, --branch      A branch name
--parameters-file A file that contains parameters as JSON object.
-o, --output      A file path to save the raw response
--wait            Wait the execution
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT

  rm -fr "${OUTPUT_DIR}"
}

initialize_colors() {
  NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

info() {
  msg "${GREEN}$1${NOFORMAT}"
}

warn() {
  msg "${YELLOW}$1${NOFORMAT}"
}

err() {
  msg "${RED}$1${NOFORMAT}"
}

die() {
  err "${1-}"
  exit "${2-1}"
}

curl() {
  local curl_options=('-sSfL')

  curl_options+=('-H' "Circle-Token: ${_CIRCLECI_TOKEN_}")

  if [[ -n "${_VERBOSE_}" ]]; then
    curl_options+=('-v')
  fi

  command curl "${curl_options[@]}" "$@"
}

parse_params() {
  branch=''
  parameters_file=''
  output_path=''
  slug=''
  with_wait=''

  _CIRCLECI_TOKEN_="${CIRCLECI_TOKEN-}"
  _VERBOSE_=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) _VERBOSE_=1 ;;
    --no-color) NO_COLOR=1 ;;
    -b | --branch)
      branch="${2-}"
      shift
      ;;
    --parameters[-_]file)
      parameters_file="${2-}"
      shift
      ;;
    -o | --output)
      output_path="${2-}"
      shift
      ;;
    -s | --slug)
      slug="${2-}"
      shift
      ;;
    -t | --token)
      _CIRCLECI_TOKEN_="${2-}"
      shift
      ;;
    --wait) with_wait=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac

    shift
  done

  [[ -z "${_CIRCLECI_TOKEN_:-}" ]] && die "Missing required parameter: -t or --token"
  [[ -z "${slug:-}" ]] && die "Missing required parameter: --slug"
  [[ -z "${branch:-}" ]] && die "Missing required parameter: --branch"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

resolve_path() {
  pushd . >/dev/null 2>&1

  if \cd "$(dirname "$1")" >/dev/null 2>&1; then
    printf "%s/%s" "$(pwd)" "$(basename "$1")"
  else
    die "could not resolve $1"
  fi

  popd >/dev/null 2>&1
}

run_pipeline() {
  local -r slug="$1" branch="$2"
  local parameters_file="$3"

  if [[ -z "${parameters_file}" ]]; then
    parameters_file="${OUTPUT_DIR}/parameters_file.json"
    echo "{}" > "${parameters_file}"
  else
    parameters_file="$(resolve_path "${parameters_file}")"
  fi

  if [[ ! -f "${parameters_file}" ]]; then
    die "${parameters_file} does not exist"
  fi

  local -r save_to="${4-}"

  local curl_options=()

  curl_options+=('-H' 'Content-Type: application/json')
  curl_options+=('-H' 'Accept: application/json')

  if [[ -n "${save_to}" ]]; then
    curl_options+=('-o' "${save_to}")
  fi

  local -r json_path="${OUTPUT_DIR}/request_body.json"

  jq -n \
    --arg branch "$branch" \
    --slurpfile parameters "${parameters_file}" \
    '{"branch": $branch } * { "parameters": $parameters[0] }' | \
    tee "${json_path}" >&2

  curl \
    "${curl_options[@]}" \
    -X POST \
    --url "https://circleci.com/api/v2/project/${slug}/pipeline" \
    -d @"${json_path}"
}

if [[ -n "${with_wait}" ]]; then
  if ! type circleci-pipeline-wait-finished >/dev/null 2>&1; then
    die 'circleci-pipeline-wait-finished is not found, which is required to wait the execution'
  fi

  run_pipeline "${slug}" "${branch}" "${parameters_file}" "${output_path}" | jq -r .id | xargs -I{} circleci-pipeline-wait-finished --token "${_CIRCLECI_TOKEN_}" --pipeline-id '{}'
else
  run_pipeline "${slug}" "${branch}" "${parameters_file}" "${output_path}"
fi
