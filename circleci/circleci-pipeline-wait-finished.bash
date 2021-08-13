#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

readonly OUTPUT_DIR="$(mktemp -d)"

usage() {
  cat <<EOF >&2
Usage:

  circleci-pipeline-wait-finished -h
  circleci-pipeline-wait-finished [-v] --token <personal token> --pipeline-id <pipeline id>

Wait for the completion of the pipeline. The completion means success, failure, and canceled.

Options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-t, --token     An API Token. Personal Token is required to execute the pipeline. 
--pipeline-id   A pipeline id
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

parse_params() {
  branch=''
  file=''
  output_path='/dev/stdout'
  pipeline_id=''
  slug=''
  token=''
  verbose=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) verbose=1 ;;
    --no-color) NO_COLOR=1 ;;
    -b | --branch)
      branch="${2-}"
      shift
      ;;
    -f | --file)
      file="${2-}"
      shift
      ;;
    -o | --output)
      output_path="${2-}"
      shift
      ;;
    --pipeline[-_]id)
      pipeline_id="${2-}"
      shift
      ;;
    -s | --slug)
      slug="${2-}"
      shift
      ;;
    -t | --token)
      token="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac

    shift
  done

  [[ -z "${token-}" ]] && die "Missing required parameter: -t or --token"
  [[ -z "${pipeline_id-}" ]] && die "Missing required parameter: --pipeline-id"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

show_workflows() {
  local -r pipeline_id="$1"

  local curl_options=('-sSfL')

  curl_options+=('-H' 'Content-Type: application/json')
  curl_options+=('-H' 'Accept: application/json')
  curl_options+=('-H' "Circle-Token: ${token}")

  if [[ -n "${verbose}" ]]; then
    curl_options+=('-v')
  fi

  curl \
    -X GET \
    --url "https://circleci.com/api/v2/pipeline/${pipeline_id}/workflow"
}

wait_pipeline() {
  local -r pipeline_id="$1"
  local -r save_to="${OUTPUT_DIR}/wait_pipeline.json"
  local status=

  while :; do
    status="$(show_workflows "${pipeline_id}" | jq -r '.items[].status' | sort | uniq)"

    case "$status" in
      success)
        info "The workflow has successfully finished."
        break
        ;;
      *canceled*)
        die 'The workflow has been canceled.'
        ;;
      *failed*)
        die 'The workflow unexpectedly failed'
        ;;
      *)
        warn "Waiting for the completion of ${pipeline_id} but got [${status}]. Retry in 30 seconds."
        sleep 30
        ;;
    esac
  done

  return 0
}

wait_pipeline "${pipeline_id}"