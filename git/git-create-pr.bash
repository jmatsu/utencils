#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

readonly OUTPUT_DIR="$(mktemp -d)"

usage() {
  cat <<EOF >&2
Usage:

  git create-pr -h
  git create-pr --token <token> --base <base branch> --head <head branch> [--force] [--title <title>] [--body-file <path>]

A command returns a default branch name of the specific remote.

Available options:
-h, --help      Print this help and exit
-t, --token     An API token
--base          A base branch
--head          A head branch
-f, --force     Force to push the head branch if specified
--title         A PR title
--body-file     A file path that contains PR description
--with-push     Push the head branch before creating a PR. Just push only unless --force option is specified.
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

  curl_options+=('-H' "Authorization: token ${_GITHUB_TOKEN_}")

  if [[ -n "${_VERBOSE_}" ]]; then
    curl_options+=('-v')
  fi

  command curl "${curl_options[@]}" "$@"
}

parse_params() {
  base_branch='master'
  body_file=''
  head_branch=''
  force=''
  pr_title=''
  with_push=''

  _DRAFT_=''
  _GITHUB_TOKEN_="${GITHUB_TOKEN-}"
  _VERBOSE_=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) _VERBOSE_=1 ;;
    --no-color) NO_COLOR=1 ;;
    -d | --draft) _DRAFT_=true ;;
    -f | --force)
      force=1
      with_push=1
      ;;
    --base)
      base_branch="${2-}"
      shift
      ;;
    --body-file)
      body_file="${2-}"
      shift
      ;;
    --head)
      head_branch="${2-}"
      shift
      ;;
    -s | --slug)
      slug="${2-}"
      shift
      ;;
    -t | --token)
      _GITHUB_TOKEN_="${2-}"
      shift
      ;;
    --title)
      pr_title="${2-}"
      shift
      ;;
    --with[-_]push)
      with_push=1
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac

    shift
  done

  [[ -z "${_GITHUB_TOKEN_-}" ]] && die "Missing required parameter: --token"
  [[ -z "${base_branch-}" ]] && die "Missing required parameter: --base"
  [[ -z "${head_branch-}" ]] && die "Missing required parameter: --head"

  return 0
}

initialize_colors
parse_params "$@"
setup_colors

create_pr() {
  local -r slug="$1" base_branch="$2" head_branch="$3" title="$4" body_file="$5"
  local -r request_file="${OUTPUT_DIR}/request_body.json"

  if [[ ! -f "${body_file}" ]]; then
    echo > "${body_file}"
  fi

  jq -cn \
    --arg base_branch "${base_branch}" \
    --arg head_branch "${head_branch}" \
    --arg title "${title}" \
    --arg draft "${_DRAFT_}" \
    --rawfile body "${body_file}" \
    '
{
  "base": $base_branch,
  "head": $head_branch,
  "title": $title,
  "draft": $draft,
  "body": $body
}| with_entries(select(.value != ""))' | tee -a "${request_file}"

  curl \
    -X POST \
    -H 'Accept: application/vnd.github.v3+json' \
    --data-binary @"${request_file}" \
    "https://api.github.com/repos/${slug}/pulls"
}

if [[ -n "${with_push}" ]]; then
  if [[ -n "${force}" ]]; then
    git push origin "${head_branch}" -f
  else
    git push origin "${head_branch}"
  fi
fi

create_pr "${slug}" "${base_branch}" "${head_branch}" "${pr_title}" "${body_file}"
