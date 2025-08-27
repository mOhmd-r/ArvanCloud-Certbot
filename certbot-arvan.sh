#!/bin/bash
set -euo pipefail

EMAIL="sre@email.com"

# Check input
if [ $# -ne 1 ]; then
  echo "Usage: $0 <domain_or_subdomain>"
  exit 1
fi

INPUT_DOMAIN="$1"

# Prompt API key
read -s -p "Enter ArvanCloud API Key: " API_KEY
echo

# Temp file to store created TXT record ID
RECORD_FILE="/tmp/last_txt_record_id.txt"

# Auth hook
AUTH_HOOK="./auth.sh"
cat <<'EOF' > "$AUTH_HOOK"
#!/bin/bash
set -euo pipefail

CERTBOT_VALIDATION="${CERTBOT_VALIDATION}"
ROOT_DOMAIN=$(echo "$CERTBOT_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

# Determine TXT name
if [[ "$CERTBOT_DOMAIN" == "$ROOT_DOMAIN" ]]; then
    TXT_NAME="_acme-challenge"
else
    SUB=${CERTBOT_DOMAIN%%.$ROOT_DOMAIN}
    TXT_NAME="_acme-challenge.$SUB"
fi

echo "Creating TXT record $TXT_NAME for $ROOT_DOMAIN"

# Create TXT record
CREATE_JSON=$(curl -s -X POST "https://napi.arvancloud.ir/cdn/4.0/domains/$ROOT_DOMAIN/dns-records" \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --header "Authorization: __API_KEY__" \
  --data "{
    \"type\": \"TXT\",
    \"name\": \"$TXT_NAME\",
    \"cloud\": false,
    \"value\": {\"text\": \"$CERTBOT_VALIDATION\"},
    \"ttl\": 120
  }")

# Save record ID for cleanup
RECORD_ID=$(echo "$CREATE_JSON" | jq -r '.data.id')
echo "$ROOT_DOMAIN|$TXT_NAME|$RECORD_ID" > __RECORD_FILE__

FQDN="$TXT_NAME.$ROOT_DOMAIN"

# Wait for DNS propagation
LOOP_COUNT=12
SLEEP_TIME=10
for i in $(seq 1 $LOOP_COUNT); do
    DIG_OUT=$(dig @8.8.8.8 TXT +short "$FQDN")
    if echo "$DIG_OUT" | grep -q "$CERTBOT_VALIDATION"; then
        echo "✅ DNS propagated: $DIG_OUT"
        exit 0
    fi
    echo "⏳ Waiting for DNS ($i/$LOOP_COUNT)..."
    sleep $SLEEP_TIME
done

echo "❌ DNS did not propagate for $FQDN"
exit 1
EOF

# Replace API key and record file path
sed -i "s|__API_KEY__|$API_KEY|g" "$AUTH_HOOK"
sed -i "s|__RECORD_FILE__|$RECORD_FILE|g" "$AUTH_HOOK"
chmod +x "$AUTH_HOOK"

# Run certbot
echo "Requesting certificate for $INPUT_DOMAIN"
certbot certonly -v \
  --preferred-challenges dns \
  --manual \
  --manual-auth-hook "$AUTH_HOOK" \
  -m "$EMAIL" \
  --agree-tos \
  --non-interactive \
  -d "$INPUT_DOMAIN"

# Cleanup TXT record
if [[ -f "$RECORD_FILE" ]]; then
    read ROOT_DOMAIN TXT_NAME RECORD_ID < <(tr '|' ' ' < "$RECORD_FILE")
    if [[ -n "$RECORD_ID" ]]; then
        echo "Deleting TXT record $TXT_NAME.$ROOT_DOMAIN"
        curl -s -X DELETE "https://napi.arvancloud.ir/cdn/4.0/domains/$ROOT_DOMAIN/dns-records/$RECORD_ID" \
             --header "accept: application/json" \
             --header "authorization: $API_KEY"
        rm -f "$RECORD_FILE"
    fi
fi

# Remove hook
rm -f "$AUTH_HOOK"
echo "✅ Done! Certificate issued and TXT record removed."
