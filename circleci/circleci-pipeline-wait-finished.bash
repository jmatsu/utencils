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

curl() {
  local curl_options=('-sSfL')

  curl_options+=('-H' "Circle-Token: ${_CIRCLECI_TOKEN_}")

  if [[ -n "${_VERBOSE_}" ]]; then
    curl_options+=('-v')
  fi

  command curl "${curl_options[@]}" "$@"
}

parse_params() {
  pipeline_id=''

  _CIRCLECI_TOKEN_="${CIRCLECI_TOKEN-}"
  _VERBOSE_=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) _VERBOSE_=1 ;;
    --no-color) NO_COLOR=1 ;;
    --pipeline[-_]id)
      pipeline_id="${2-}"
      shift
      ;;
    -t | --token)
      _CIRCLECI_TOKEN_="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac

    shift
  done

  [[ -z "${_CIRCLECI_TOKEN_-}" ]] && die "Missing required parameter: -t or --token"
  [[ -z "${pipeline_id-}" ]] && die "Missing required parameter: --pipeline-id"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

show_workflows() {
  local -r pipeline_id="$1"

  local curl_options=()

  curl_options+=('-H' 'Content-Type: application/json')
  curl_options+=('-H' 'Accept: application/json')

  curl \
    -X GET \
    --url "https://circleci.com/api/v2/pipeline/${pipeline_id}/workflow"
}

wait_pipeline() {
  local -r pipeline_id="$1"
  local workflow_json='' workflow_name='' workflow_id='' workflow_status='' wait_more=''

  while :; do
    wait_more=''

    while IFS= read -r workflow_json; do
      workflow_id="$(echo "${workflow_json}" | jq -r '.id')"
      workflow_name="$(echo "${workflow_json}" | jq -r '.name')"
      workflow_status="$(echo "${workflow_json}" | jq -r '.status')"

      case "$workflow_status" in
        success)
          info "'${workflow_name}' (${workflow_id}) has successfully finished."
          break
          ;;
        canceled)
          die "'${workflow_name}' (${workflow_id}) has been canceled"
          ;;
        failed)
          die "'${workflow_name}' (${workflow_id}) unexpectedly failed"
          ;;
        *)
          warn "Waiting for the completion of '${workflow_name}' (${workflow_id}) but got ${workflow_status}."
          wait_more=1
          ;;
      esac
    done < <(show_workflows "${pipeline_id}" | jq -c '.items[]')

    if [[ -z "${wait_more}" ]]; then
      break
    fi

    warn "Retry in 30 seconds."
    sleep 30
  done

  info "All workflows in ${pipeline_id} have successfully finished."

  return 0
}

wait_pipeline "${pipeline_id}"