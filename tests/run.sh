#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
credentials="$test_dir/credentials"
printf 'ARVANCLOUD_API_KEY=Apikey test-secret\n' >"$credentials"
chmod 0600 "$credentials"

cat >"$test_dir/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >>"$ARVAN_TEST_CURL_LOG"
printf '\n' >>"$ARVAN_TEST_CURL_LOG"
if [[ " $* " == *" --request POST "* ]]; then
  printf '{"data":{"id":"record_123"}}\n'
fi
MOCK_CURL

cat >"$test_dir/bin/dig" <<'MOCK_DIG'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ " $* " == *" NS "* ]]; then
  printf 'ns1.example.net.\nns2.example.net.\n'
elif [[ ${ARVAN_TEST_PROPAGATED:-true} == true ]]; then
  printf '"%s"\n' "$CERTBOT_VALIDATION"
fi
MOCK_DIG

chmod 0755 "$test_dir/bin/curl" "$test_dir/bin/dig"
export PATH="$test_dir/bin:$PATH"
export ARVANCLOUD_CREDENTIALS_FILE="$credentials"
export ARVAN_TEST_CURL_LOG="$test_dir/curl.log"
export CERTBOT_IDENTIFIER="app.example.co.uk"
export CERTBOT_VALIDATION="validation_123"

auth_output=$("$repo_dir/hooks/auth-hook.sh" --zone example.co.uk 2>"$test_dir/auth.log")
jq -e '.zone == "example.co.uk" and .record_id == "record_123"' \
  <<<"$auth_output" >/dev/null

if grep -q 'test-secret' "$test_dir/auth.log"; then
  printf 'Secret leaked to auth-hook log\n' >&2
  exit 1
fi

export CERTBOT_AUTH_OUTPUT="$auth_output"
"$repo_dir/hooks/cleanup-hook.sh" 2>"$test_dir/cleanup.log"

grep -q -- '--request POST' "$test_dir/curl.log"
grep -q -- '--request DELETE' "$test_dir/curl.log"

printf '' >"$test_dir/curl.log"
export ARVAN_TEST_PROPAGATED=false
export ARVANCLOUD_PROPAGATION_TIMEOUT=1
export ARVANCLOUD_PROPAGATION_INTERVAL=1
if "$repo_dir/hooks/auth-hook.sh" --zone example.co.uk \
  >"$test_dir/failed-auth.out" 2>"$test_dir/failed-auth.log"; then
  printf 'Expected propagation failure did not occur\n' >&2
  exit 1
fi
grep -q -- '--request DELETE' "$test_dir/curl.log"
if grep -q 'test-secret' "$test_dir/failed-auth.out" "$test_dir/failed-auth.log"; then
  printf 'Secret leaked during failed authentication\n' >&2
  exit 1
fi

printf 'ArvanCloud hook tests passed\n'
