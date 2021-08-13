#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

usage() {
  cat <<EOF >&2
Usage:

  git get-default-branch -h
  git get-default-branch --remote <remote>

A command returns a default branch name of the specific remote.

Available options:
-h, --help      Print this help and exit
-r, --remote    A remote name to fetch. e.g. origin (default)
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT

  : # do nothing for now
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
  remote=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    --no-color) NO_COLOR=1 ;;
    -r | --remote)
      remote="${2-}"
      shift
      ;;
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac

    shift
  done

  if [[ -z "${remote}" ]]; then
    warn "--remote is not specified so origin will be used by default."
    remote='origin'
  fi

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

git ls-remote --symref "$(git remote get-url "${remote}")" HEAD | grep 'refs/heads' | awk '$0=$2' | sed 's/refs\/heads\///';