#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

readonly OUTPUT_DIR="$(mktemp -d)"

usage() {
  cat <<EOF
Usage:
  
  deploygate-destroy-distribution -h
  deploygate-destroy-distribution [-v] --token <token> --key <key> [--output <path>]

Upload the given app to DeployGate

Options:
-h, --help    Print this help and exit
-v, --verbose Print script debug info
-t, --token   An API Token
-k, --key     A key of a distribution to destroy
-o, --output  A file path to save the raw response
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
  distribution_key=''
  output_path=''
  _DEPLOYGATE_API_TOKEN_="${DEPLOYGATE_API_TOKEN-}"

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) _VERBOSE_=1 ;;
    --no-color) NO_COLOR=1 ;;
    -k | --key)
      distribution_key="${2-}"
      shift
      ;;
    -o | --output)
      output_path="${2-}"
      shift
      ;;
    -t | --token)
      _DEPLOYGATE_API_TOKEN_="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  [[ -z "${_DEPLOYGATE_API_TOKEN_-}" ]] && die "Missing required parameter: -t or --token"
  [[ -z "${distribution_key-}" ]] && die "Missing required parameter: --key"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

# script logic here

destroy_distribution() {
  local -r distribution_key="$1" save_to="${2-}"

  local curl_options=('-sSfL')

  curl_options+=('-A' 'jmatsu/utencils')
  curl_options+=('-H' 'Accept: application/json')
  curl_options+=('-H' "Authorization: token ${_DEPLOYGATE_API_TOKEN_}")

  if [[ -n "${_VERBOSE_}" ]]; then
    curl_options+=('-v')
  fi

  if [[ -n "${save_to}" ]]; then
    curl_options+=('-o' "${save_to}")
  fi

  curl \
    "${curl_options[@]}" \
    -X DELETE \
    --url "https://deploygate.com/api/distributions/${distribution_key}"
}

destroy_distribution "${distribution_key}" "${save_to}"
