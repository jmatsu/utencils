#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

readonly OUTPUT_DIR="$(mktemp -d)"

usage() {
  cat <<EOF
Usage:
  
  deploygate-app-upload -h
  deploygate-app-upload [-v] --app-owner <name> --file <path> [--message <message>] [--public] [--disable-ios-notification] [--output <path>]

Upload the given app to DeployGate

Options:
-h, --help                  Print this help and exit
-v, --verbose               Print script debug info
-t, --token                 An API Token
--app-owner                 An app owner name (either user name or group name)
-f, --file                  A file path to application to upload
-m, --message               A short message linked to the revision
--public                    Use public visibility (only for free users)
--disable-ios-notification  Disable notifications (only for ios apps)
-o, --output                A file path to save the raw response
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
  app_owner_name=''
  file_path=''
  disable_ios_notification=''
  distribution_key=''
  distribution_name=''
  message=''
  public=''
  output_path=''
  token=''
  verbose=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    --disable[-_]ios[-_]notification) disable_ios_notification=1 ;;
    --public) public=1 ;;
    --app[-_]owner)
      app_owner_name="${2-}"
      shift
      ;;
    --distribution[-_]key)
      distribution_key="${2-}"
      shift
      ;;
    --distribution[-_]name)
      distribution_name="${2-}"
      shift
      ;;
    -f | --file)
      file_path="${2-}"
      shift
      ;;
    -m | --message)
      message="${2-}"
      shift
      ;;
    -o | --output)
      output_path="${2-}"
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
  [[ -z "${app_owner_name}" ]] && die "Missing required parameter: --app-owner"
  [[ -z "${file_path}" ]] && die "Missing required parameter: --file"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

# script logic here

resolve_path() {
  pushd . >/dev/null 2>&1

  if \cd "$(dirname "$1")" >/dev/null 2>&1; then
    printf "%s/%s" "$(pwd)" "$(basename "$1")"
  else
    die "could not resolve $1"
  fi

  popd >/dev/null 2>&1
}

upload() {
  local -r app_owner_name="$1" app_file="$(resolve_path "$2")" mesasge="$3" public="$4" disable_ios_notification="$5" save_to="${6-}"

  if [[ ! -f "${app_file}" ]]; then
    die "${app_file} is not found"
  fi

  local curl_options=('-sSfL')

  curl_options+=('-A' 'jmatsu/utencils')
  curl_options+=('-H' 'Accept: application/json')
  curl_options+=('-H' "Authorization: token ${token}")
  curl_options+=('-F' "file=@${app_file}")

  if [[ -n "${verbose}" ]]; then
    curl_options+=('-v')
  fi

  if [[ -n "${mesasge}" ]]; then
    curl_options+=('-F' "message=${message}")
  fi

  if [[ -n "${public}" ]]; then
    curl_options+=('-F' "visibility=public")
  fi

  if [[ -n "${disable_ios_notification}" ]]; then
    curl_options+=('-F' "disable_notify=true")
  fi

  if [[ -n "${distribution_key}" ]]; then
    curl_options+=('-F' "distribution_key=${distribution_key}")
  elif [[ -n "${distribution_name}" ]]; then
    curl_options+=('-F' "distribution_name=${distribution_name}")
  fi

  if [[ -n "${save_to}" ]]; then
    curl_options+=('-o' "${save_to}")
  fi

  curl \
    "${curl_options[@]}" \
    -X POST \
    --url "https://deploygate.com/api/users/$app_owner_name/apps"
}

upload "${app_owner_name}" "${file_path}" "${message}" "${public}" "${disable_ios_notification}" "${output_path}"