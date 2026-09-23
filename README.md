# Certbot with ArvanCloud DNS

Issue and automatically renew Let's Encrypt certificates through ArvanCloud's
DNS API. The project installs persistent Certbot manual hooks and keeps the API
authorization value in a root-owned `0600` file.

## Security model

- The API key is never embedded in a hook or passed on the command line.
- Hooks and credentials are installed under root-controlled paths.
- The exact ArvanCloud zone is required; the script does not guess registrable
  domains and therefore handles multi-label public suffixes such as `co.uk`.
- JSON request and response data is built and validated with `jq`.
- API calls have connection and total timeouts and treat HTTP errors as errors.
- Failed authentication attempts remove any TXT record already created.
- Certbot passes scoped cleanup metadata through `CERTBOT_AUTH_OUTPUT`, avoiding
  predictable files in `/tmp`.
- DNS propagation is confirmed against every authoritative name server.

## Requirements

Supported target: Ubuntu 24.04 LTS or another Linux distribution with:

- Bash 4.4+
- Certbot
- curl 7.76+ (`--fail-with-body`)
- jq
- `dig`
- GNU `install` and `stat`
- root access

On Ubuntu:

```bash
sudo apt-get update
sudo apt-get install --yes certbot curl jq dnsutils
```

Create an ArvanCloud API key with only the permissions and zones required for
DNS record management. Treat the complete value used in the HTTP
`Authorization` header as a password.

## Issue a certificate

```bash
git clone https://github.com/mOhmd-r/ArvanCloud-Certbot.git
cd ArvanCloud-Certbot
chmod +x certbot-arvan.sh hooks/*.sh tests/run.sh

sudo ./certbot-arvan.sh \
  --email sre@example.com \
  --zone example.com \
  -d example.com \
  -d '*.example.com'
```

The API authorization value is requested without terminal echo on the first
run. It is installed at:

```text
/etc/letsencrypt/arvancloud/credentials
```

Expected format:

```ini
ARVANCLOUD_API_KEY=Apikey replace-with-your-key
```

You may prepare that file elsewhere and import it:

```bash
sudo ./certbot-arvan.sh \
  --email sre@example.com \
  --zone example.com \
  --credentials-file /root/arvancloud.credentials \
  -d example.com
```

The source must be a regular file, not a symlink. The installed copy is always
owned by root with mode `0600`.

## Renewal

The absolute auth and cleanup hook commands are stored by Certbot in the
certificate's renewal configuration. Test them immediately:

```bash
sudo certbot renew --dry-run
```

Inspect the saved configuration without exposing the credentials:

```bash
sudo certbot certificates
sudo grep -E '^(authenticator|manual_auth_hook|manual_cleanup_hook)' \
  /etc/letsencrypt/renewal/*.conf
```

Do not remove `/usr/local/libexec/certbot-arvancloud` or
`/etc/letsencrypt/arvancloud/credentials` while certificates depend on these
hooks.

## Staging

Use Let's Encrypt staging while testing to avoid production rate limits:

```bash
sudo ./certbot-arvan.sh \
  --staging \
  --email sre@example.com \
  --zone example.com \
  -d example.com
```

Staging certificates are not trusted by browsers.

## Limitations

- The challenge name must be hosted directly in the configured ArvanCloud zone.
  CNAME-delegated `_acme-challenge` records are not handled.
- Internationalized domains must be supplied in ASCII/Punycode form.
- One invocation operates on identifiers inside one ArvanCloud zone.
- The hook deliberately does not retry mutating API requests automatically;
  blind retries can create duplicate TXT records after ambiguous timeouts.

## Development

Run local checks:

```bash
bash -n certbot-arvan.sh hooks/*.sh tests/run.sh
shellcheck -x certbot-arvan.sh hooks/*.sh tests/run.sh
bash tests/run.sh
```

Tests use mocked network commands and never contact ArvanCloud or Let's Encrypt.

## License

MIT. See [LICENSE](LICENSE).
