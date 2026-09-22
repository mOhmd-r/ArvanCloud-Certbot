#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly INSTALL_DIR="/usr/local/libexec/certbot-arvancloud"
readonly CONFIG_DIR="/etc/letsencrypt/arvancloud"
readonly CREDENTIALS_FILE="$CONFIG_DIR/credentials"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  sudo ./certbot-arvan.sh --email EMAIL --zone ZONE -d DOMAIN [-d DOMAIN ...]
                           [--credentials-file FILE] [--staging]

Required:
  --email EMAIL             ACME account email address.
  --zone ZONE               Exact zone registered in ArvanCloud.
  -d, --domain DOMAIN       Certificate identifier; repeat for SANs/wildcards.

Options:
  --credentials-file FILE   Import a file containing one line:
                              ARVANCLOUD_API_KEY=<authorization value>
  --staging                 Use Let's Encrypt's staging environment.
  -h, --help                Show this help.

The API key is never accepted as a command-line argument. If the protected
credentials file does not exist, the script prompts for it without echo.
USAGE
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_dns_name() {
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

validate_identifier() {
  local value=${1,,}
  value=${value#\*.}
  validate_dns_name "$value"
}

zone_contains_identifier() {
  local identifier=${1,,}
  local zone=${2,,}
  identifier=${identifier#\*.}
  [[ $identifier == "$zone" || $identifier == *."$zone" ]]
}

email=""
zone=""
staging=false
credentials_source=""
declare -a domains=()

while (($# > 0)); do
  case "$1" in
    --email)
      (($# >= 2)) || die "--email requires a value"
      email=$2
      shift 2
      ;;
    --zone)
      (($# >= 2)) || die "--zone requires a value"
      zone=${2,,}
      shift 2
      ;;
    -d | --domain)
      (($# >= 2)) || die "$1 requires a value"
      domains+=("${2,,}")
      shift 2
      ;;
    --credentials-file)
      (($# >= 2)) || die "--credentials-file requires a value"
      credentials_source=$2
      shift 2
      ;;
    --staging)
      staging=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
done

((EUID == 0)) || die "Run this installer with sudo or as root"
[[ -n $email ]] || die "--email is required"
[[ $email =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] ||
  die "Invalid email address"
validate_dns_name "$zone" || die "Invalid --zone value"
((${#domains[@]} > 0)) || die "At least one -d/--domain is required"

for domain in "${domains[@]}"; do
  validate_identifier "$domain" || die "Invalid certificate identifier: $domain"
  zone_contains_identifier "$domain" "$zone" ||
    die "Identifier '$domain' is not inside ArvanCloud zone '$zone'"
done

for command_name in bash certbot curl dig install jq mktemp stat; do
  require_command "$command_name"
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
for hook in arvan-lib.sh auth-hook.sh cleanup-hook.sh; do
  [[ -f "$script_dir/hooks/$hook" && ! -L "$script_dir/hooks/$hook" ]] ||
    die "Required hook is missing or is a symlink: hooks/$hook"
done

install -d -o root -g root -m 0755 "$INSTALL_DIR"
install -d -o root -g root -m 0700 "$CONFIG_DIR"
install -o root -g root -m 0644 "$script_dir/hooks/arvan-lib.sh" "$INSTALL_DIR/arvan-lib.sh"
install -o root -g root -m 0755 "$script_dir/hooks/auth-hook.sh" "$INSTALL_DIR/auth-hook"
install -o root -g root -m 0755 "$script_dir/hooks/cleanup-hook.sh" "$INSTALL_DIR/cleanup-hook"

if [[ -n $credentials_source ]]; then
  [[ -f $credentials_source && ! -L $credentials_source ]] ||
    die "Credentials source must be a regular, non-symlink file"
  install -o root -g root -m 0600 "$credentials_source" "$CREDENTIALS_FILE"
elif [[ ! -e $CREDENTIALS_FILE ]]; then
  [[ -t 0 ]] || die "Interactive terminal required to enter the API key"
  read -r -s -p "Enter the complete ArvanCloud Authorization value: " api_key
  printf '\n' >&2
  [[ -n $api_key && $api_key != *$'\n'* && $api_key != *$'\r'* ]] ||
    die "API key must be non-empty and contain no line breaks"

  credentials_tmp=$(mktemp "$CONFIG_DIR/.credentials.XXXXXX")
  trap 'rm -f -- "${credentials_tmp:-}"' EXIT
  printf 'ARVANCLOUD_API_KEY=%s\n' "$api_key" >"$credentials_tmp"
  unset api_key
  install -o root -g root -m 0600 "$credentials_tmp" "$CREDENTIALS_FILE"
  rm -f -- "$credentials_tmp"
  trap - EXIT
else
  [[ -f $CREDENTIALS_FILE && ! -L $CREDENTIALS_FILE ]] ||
    die "Existing credentials path is not a regular file"
fi

credentials_owner=$(stat -c '%u' "$CREDENTIALS_FILE")
credentials_mode=$(stat -c '%a' "$CREDENTIALS_FILE")
[[ $credentials_owner == 0 && $credentials_mode == 600 ]] ||
  die "$CREDENTIALS_FILE must be owned by root with mode 0600"

auth_command="$INSTALL_DIR/auth-hook --zone $zone"
cleanup_command="$INSTALL_DIR/cleanup-hook"
declare -a certbot_args=(
  certonly
  --manual
  --preferred-challenges dns
  --manual-auth-hook "$auth_command"
  --manual-cleanup-hook "$cleanup_command"
  --non-interactive
  --agree-tos
  --email "$email"
)

for domain in "${domains[@]}"; do
  certbot_args+=(-d "$domain")
done

if [[ $staging == true ]]; then
  certbot_args+=(--staging)
fi

printf 'Requesting certificate for: %s\n' "${domains[*]}"
printf 'ArvanCloud zone: %s\n' "$zone"
certbot "${certbot_args[@]}"

cat <<EOF

Certificate request completed.
Persistent hooks:
  $INSTALL_DIR/auth-hook
  $INSTALL_DIR/cleanup-hook
Credentials:
  $CREDENTIALS_FILE (root:root, 0600)

Validate renewal after issuance:
  sudo certbot renew --dry-run
EOF
