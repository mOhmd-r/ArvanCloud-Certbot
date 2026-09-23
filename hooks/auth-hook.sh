#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=hooks/arvan-lib.sh
source "$script_dir/arvan-lib.sh"

zone=""
while (($# > 0)); do
  case "$1" in
    --zone)
      (($# >= 2)) || arvan_die "--zone requires a value"
      zone=${2,,}
      shift 2
      ;;
    *)
      arvan_die "Unknown hook argument: $1"
      ;;
  esac
done

arvan_validate_dns_name "$zone" || arvan_die "Invalid or missing --zone"

identifier=${CERTBOT_IDENTIFIER:-${CERTBOT_DOMAIN:-}}
validation=${CERTBOT_VALIDATION:-}
identifier=${identifier,,}
identifier=${identifier#\*.}

arvan_validate_dns_name "$identifier" || arvan_die "Invalid Certbot identifier"
[[ $identifier == "$zone" || $identifier == *."$zone" ]] ||
  arvan_die "Identifier is outside configured zone"
[[ -n $validation && $validation =~ ^[A-Za-z0-9_-]+$ ]] ||
  arvan_die "Invalid or missing Certbot validation value"

for command_name in curl dig jq stat; do
  arvan_require_command "$command_name"
done
arvan_load_api_key

if [[ $identifier == "$zone" ]]; then
  record_name="_acme-challenge"
else
  subdomain=${identifier%."$zone"}
  record_name="_acme-challenge.$subdomain"
fi
fqdn="$record_name.$zone"
[[ ${#fqdn} -le 253 ]] || arvan_die "ACME challenge name exceeds DNS length limits"

payload=$(jq -cn \
  --arg name "$record_name" \
  --arg value "$validation" \
  '{type:"TXT", name:$name, cloud:false, value:{text:$value}, ttl:120}')

arvan_log "Creating DNS-01 TXT record for $fqdn"
response=$(
  curl --disable --proto '=https' --tlsv1.2 \
    --silent --show-error --fail-with-body \
    --connect-timeout 10 --max-time 30 \
    --request POST \
    --header "Accept: application/json" \
    --header "Content-Type: application/json" \
    --header "Authorization: $ARVANCLOUD_API_KEY" \
    --data "$payload" \
    "$ARVAN_API_BASE/domains/$zone/dns-records"
) || arvan_die "ArvanCloud rejected the TXT record creation request"

record_id=$(jq -er '.data.id | strings | select(length > 0)' <<<"$response") ||
  arvan_die "ArvanCloud response did not contain a valid record ID"
arvan_validate_record_id "$record_id" ||
  arvan_die "ArvanCloud returned an unsafe record ID"

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2317
cleanup_failed_auth() {
  local status=$?
  if ((status != 0)) && [[ -n ${record_id:-} ]]; then
    arvan_log "Authentication failed; removing the TXT record"
    arvan_delete_record "$zone" "$record_id" ||
      arvan_log "WARNING: failed to remove TXT record $record_id"
  fi
  exit "$status"
}
trap cleanup_failed_auth EXIT

timeout=${ARVANCLOUD_PROPAGATION_TIMEOUT:-300}
interval=${ARVANCLOUD_PROPAGATION_INTERVAL:-10}
[[ $timeout =~ ^[0-9]+$ && $interval =~ ^[0-9]+$ ]] ||
  arvan_die "Propagation timeout and interval must be integers"
((timeout >= 1 && timeout <= 3600 && interval >= 1 && interval <= 60)) ||
  arvan_die "Propagation timeout or interval is outside the safe range"

mapfile -t name_servers < <(
  dig +time=3 +tries=2 +short NS "$zone" |
    sed 's/\.$//' |
    awk 'NF' |
    sort -u
)
((${#name_servers[@]} > 0)) ||
  arvan_die "No authoritative name servers found for $zone"

deadline=$((SECONDS + timeout))
while ((SECONDS < deadline)); do
  all_ready=true
  for name_server in "${name_servers[@]}"; do
    found=false
    while IFS= read -r answer; do
      if [[ $answer == "\"$validation\"" || $answer == "$validation" ]]; then
        found=true
        break
      fi
    done < <(dig +time=3 +tries=1 +short "@$name_server" TXT "$fqdn" 2>/dev/null || true)

    if [[ $found != true ]]; then
      all_ready=false
      break
    fi
  done

  if [[ $all_ready == true ]]; then
    arvan_log "TXT record is visible on all authoritative name servers"
    jq -cn --arg zone "$zone" --arg record_id "$record_id" \
      '{zone:$zone, record_id:$record_id}'
    trap - EXIT
    exit 0
  fi

  sleep "$interval"
done

arvan_die "TXT record did not propagate to every authoritative name server within ${timeout}s"
