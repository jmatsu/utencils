#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

readonly OUTPUT_DIR="$(mktemp -d)"

usage() {
  cat <<EOF
Usage:

  circleci-artifact-download -h
  circleci-artifact-download [-v] --token <token> --slug <slug> --job-number <job number> --output <diretory path> [--include <glob pattern>] [--exclude <glob pattern>]

Download the artifacts of the job w/ optional filtering.

Options:
-h, --help       Print this help and exit
-v, --verbose    Print script debug info
-j, --job-number A job number
-s, --slug       CircleCI project slug. e.g. github/jmatsu/utencils
-t, --token      An API Token
-e, --exclude    A glob pattern to exclude artifacts
-i, --include    A glob pattern to include artifacts
-o, --output     A path to a directory will contain artifacts
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
  exclude_pattern=''
  include_pattern=''
  job_number=''
  output_path=''
  slug=''

  _CIRCLECI_TOKEN_="${CIRCLECI_TOKEN-}"
  _VERBOSE_=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) _VERBOSE_=1 ;;
    --no-color) NO_COLOR=1 ;;
    -e | --exclude)
      exclude_pattern="${2-}"
      shift
      ;;
    -i | --include)
      include_pattern="${2-}"
      shift
      ;;
    -j | --job[-_]number)
      job_number="${2-}"
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
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  [[ -z "${_CIRCLECI_TOKEN_-}" ]] && die "Missing required parameter: -t or --token"
  [[ -z "${slug-}" ]] && die "Missing required parameter: --slug"
  [[ -z "${job_number}" ]] && die "Missing required parameter: --job-number"
  [[ -z "${output_path}" ]] && die "Missing required parameter: --output"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

# script logic here

list_artifacts() {
  local -r slug="$1" job_number="$2"

  local curl_options=()

  curl_options+=('-H' 'Accept: application/json')
  curl_options+=('-H' 'Content-Type: application/json')

  curl \
    "${curl_options[@]}" \
     -X GET \
    --url "https://circleci.com/api/v2/project/${slug}/${job_number}/artifacts"
}

download_artifact() {
  local -r url="$1" output_dir_path="$2" path="$3" include_pattern="$4" exclude_pattern="$5"
  
  if [[ -n "${include_pattern}" ]]; then
    if ! echo "$path" | grep "${include_pattern}" >/dev/null 2>&1; then
      warn "$path has been rejected because it's not allowed by the specified inclusion filter"
      return 0
    fi
  fi

  if [[ -n "${exclude_pattern}" ]]; then
    if echo "$path" | grep "${exclude_pattern}" >/dev/null 2>&1; then
      warn "$path has been rejected because it's not allowed by the specified exclusion filter"
      return 0
    fi
  fi

  local -r save_to="${output_dir_path}/$path"

  info "Download an artifact from ${url} to ${save_to}"

  mkdir -p "$(dirname "${save_to}")"

  local curl_options=()

  curl_options+=('-o' "${save_to}")
  curl_options+=('-H' 'Accept: application/octet-stream')
  curl_options+=('-H' 'Content-Type: application/json')

  curl \
    "${curl_options[@]}" \
     -X GET \
    --url "${url}"
}

download_artifacts_of_a_job() {
  local -r job_number="$1" output_dir_path="$2" include_pattern="$3" exclude_pattern="$4"
  local artifact_json='' path='' url=''

  while IFS= read -r artifact_json; do
    path="$(echo "${artifact_json}" | jq -r '.path')"
    url="$(echo "${artifact_json}" | jq -r '.url')"

    download_artifact "${url}" "${output_dir_path}" "${path}" "${include_pattern}" "${exclude_pattern}"
  done < <(list_artifacts "${slug}" "${job_number}" | jq -c '.items[]')
}

download_artifacts_of_a_job "${slug}" "${job_number}" "${output_path}" "${include_pattern}" "${exclude_pattern}"