# Certbot-ArvanCloud

````markdown
# Certbot + ArvanCloud DNS Hook

This script automates issuing SSL certificates with **Certbot** using the **DNS-01 challenge** via **ArvanCloud DNS API**.  

---

## Requirements

1. **ArvanCloud API Key**  
   You need to generate an API Key from your ArvanCloud panel:  
   👉 [Official ArvanCloud API Key Documentation](https://docs.arvancloud.ir/fa/developer-tools/api/api-key)

2. **Dependencies**
   - `bash`
   - `curl`
   - `jq`
   - `dig` (package `dnsutils`)
   - `certbot`

3. Access to a server where your domain (or subdomain) is pointing.

---

## How It Works

1. The script securely prompts you for the **ArvanCloud API Key**.  
2. A temporary hook script (`auth.sh`) is created as a **Certbot manual-auth-hook**:
   - It creates the required `_acme-challenge` TXT record via ArvanCloud API.
   - Waits until the DNS record is propagated.  
3. Certbot uses the TXT record to validate the domain and issue the SSL certificate.  
4. After successful issuance:
   - The temporary TXT record is **removed** from ArvanCloud DNS.  
   - The temporary hook script is deleted.  

---

## Usage

Run the script with your domain or subdomain as an argument:

```bash
./certbot-arvan.sh <domain_or_subdomain>
````

### Examples

Request certificate for the root domain:

```bash
./certbot-arvan.sh example.com
```

Request certificate for a subdomain:

```bash
./certbot-arvan.sh app.example.com
```

---

## Output

* Certificates are stored in the default Certbot location:

  ```
  /etc/letsencrypt/live/<domain>/
  ```
* Temporary TXT records are removed after validation.
* On success, you will see:

  ```
  ✅ Done! Certificate issued and TXT record removed.
  ```

---

## Notes

* The TXT record TTL is set to **120 seconds**.
* The script waits up to **120 seconds** (12 × 10s retries) for DNS propagation.
* If DNS propagation takes longer, the process will fail.

---

## Temporary Files

* `/tmp/last_txt_record_id.txt`
  Stores the record ID of the created TXT entry, used for cleanup.

---
