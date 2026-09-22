#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=hooks/arvan-lib.sh
source "$script_dir/arvan-lib.sh"

for command_name in curl jq stat; do
  arvan_require_command "$command_name"
done
arvan_load_api_key

auth_output=${CERTBOT_AUTH_OUTPUT:-}
[[ -n $auth_output ]] || arvan_die "CERTBOT_AUTH_OUTPUT is empty; refusing an unscoped cleanup"

zone=$(jq -er '.zone | strings | select(length > 0)' <<<"$auth_output") ||
  arvan_die "Cleanup metadata does not contain a valid zone"
record_id=$(jq -er '.record_id | strings | select(length > 0)' <<<"$auth_output") ||
  arvan_die "Cleanup metadata does not contain a valid record ID"

arvan_validate_dns_name "$zone" || arvan_die "Unsafe zone in cleanup metadata"
arvan_validate_record_id "$record_id" || arvan_die "Unsafe record ID in cleanup metadata"

arvan_log "Removing DNS-01 TXT record from zone $zone"
arvan_delete_record "$zone" "$record_id" ||
  arvan_die "ArvanCloud rejected TXT record cleanup"
