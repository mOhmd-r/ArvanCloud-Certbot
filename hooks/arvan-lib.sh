#!/usr/bin/env bash

readonly ARVAN_API_BASE="https://napi.arvancloud.ir/cdn/4.0"
readonly DEFAULT_CREDENTIALS_FILE="/etc/letsencrypt/arvancloud/credentials"

arvan_log() {
  printf '%s\n' "$*" >&2
}

arvan_die() {
  arvan_log "ERROR: $*"
  exit 1
}

arvan_require_command() {
  command -v "$1" >/dev/null 2>&1 || arvan_die "Required command not found: $1"
}

arvan_validate_dns_name() {
  local value=${1,,}
  local label
  local -a labels=()

  [[ ${#value} -le 253 ]] || return 1
  [[ $value != *..* ]] || return 1
  IFS='.' read -r -a labels <<<"$value"
  ((${#labels[@]} >= 2)) || return 1
  for label in "${labels[@]}"; do
    [[ ${#label} -le 63 ]] || return 1
    [[ $label =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
}

arvan_validate_record_id() {
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]]
}

arvan_load_api_key() {
  local credentials_file=${ARVANCLOUD_CREDENTIALS_FILE:-$DEFAULT_CREDENTIALS_FILE}
  local owner mode
  local -a lines=()

  [[ -f $credentials_file && ! -L $credentials_file ]] ||
    arvan_die "Credentials must be a regular, non-symlink file: $credentials_file"

  owner=$(stat -c '%u' "$credentials_file") ||
    arvan_die "Unable to inspect credentials owner"
  mode=$(stat -c '%a' "$credentials_file") ||
    arvan_die "Unable to inspect credentials permissions"

  [[ $owner == "$EUID" ]] ||
    arvan_die "Credentials must be owned by the hook user (uid $EUID)"
  [[ $mode =~ ^[0-7]{3,4}$ ]] ||
    arvan_die "Unable to validate credentials permissions"
  local mode_decimal=$((8#$mode))
  (( (mode_decimal & 077) == 0 )) ||
    arvan_die "Credentials must not be accessible by group or others"

  mapfile -t lines <"$credentials_file"
  ((${#lines[@]} == 1)) ||
    arvan_die "Credentials file must contain exactly one line"
  [[ ${lines[0]} == ARVANCLOUD_API_KEY=* ]] ||
    arvan_die "Credentials line must start with ARVANCLOUD_API_KEY="

  ARVANCLOUD_API_KEY=${lines[0]#ARVANCLOUD_API_KEY=}
  [[ -n $ARVANCLOUD_API_KEY ]] || arvan_die "API key is empty"
  [[ $ARVANCLOUD_API_KEY != *$'\r'* && $ARVANCLOUD_API_KEY != *$'\n'* ]] ||
    arvan_die "API key contains a forbidden line break"
  readonly ARVANCLOUD_API_KEY
}

arvan_delete_record() {
  local zone=$1
  local record_id=$2

  arvan_validate_dns_name "$zone" || return 1
  arvan_validate_record_id "$record_id" || return 1

  curl --disable --proto '=https' --tlsv1.2 \
    --silent --show-error --fail-with-body \
    --connect-timeout 10 --max-time 30 \
    --request DELETE \
    --header "Accept: application/json" \
    --header "Authorization: $ARVANCLOUD_API_KEY" \
    --output /dev/null \
    "$ARVAN_API_BASE/domains/$zone/dns-records/$record_id"
}
