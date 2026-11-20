# cert-lab on Rocky 8.10, Part 1: Two-Tier PKI with OpenSSL

Build a **root CA → intermediate (issuing) CA → server certificate** chain by hand,
get a client to trust it, serve HTTPS with it, then revoke a certificate.

## Goals

- Understand why a root CA is kept offline and what an intermediate buys you.
- Build CA hierarchies with the right extensions (`basicConstraints`, `pathlen`, `keyUsage`).
- Issue, deploy, verify, and revoke a TLS server certificate.
- Distribute trust with the system trust store (`update-ca-trust`).

## Topology

| VM | IP | FQDN | Role |
| --- | --- | --- | --- |
| `root-ca` | 192.168.150.10 | `root-ca.lab.test` | Root CA. Signs only the intermediate, then stays off. |
| `issuing-ca` | 192.168.150.11 | `issuing-ca.lab.test` | Intermediate CA. Signs everyday certs. |
| `client` | 192.168.150.12 | `client.lab.test` | nginx web server + TLS client. |

All three run the `local/rocky-8.10` box (OpenSSL 1.1.1k, the same as production) on the
private libvirt network `ca-lab`. Ansible (`provision/site.yml`) adds every host to
`/etc/hosts`, so the FQDNs resolve without DNS.

## Conventions

- Host commands (`make ...`) run from the **repo root**. `LAB` defaults to
  `cert-lab/rocky-8.10`, so `make ssh VM=root-ca` is enough. The plain Vagrant equivalent is
  `cd labs/cert-lab/rocky-8.10 && vagrant ssh root-ca`.
- Run CA work as root inside each VM: `make ssh VM=<vm>` then `sudo -i`.
- Files move between VMs with `scp` using the `vagrant` account (password `vagrant`),
  staged through `/tmp`, the way you'd hand a CSR to a real CA. The first `scp` to each
  host asks you to accept its host key: answer `yes`.
- Commands that use a CA key prompt for that key's passphrase. Pick one per CA and keep it.
- Crypto choices: ECDSA keys (P-384 for CAs, P-256 for servers), SHA-384 / SHA-256.

---

## 0. Bring up the lab

On the host, from the repo root. The first two lines are one-time setup per machine; skip
them if `make list` already shows `local/rocky-8.10` under imported boxes.

```bash
make setup                                               # uv, Ansible, pre-commit (once per machine)
make box BOX=rocky-8.10 && make box-add BOX=rocky-8.10   # build + import the box (once)
make up                                                  # creates and provisions all three VMs
make status                                              # all three should be "running"
```

---

## 1. Root CA (on `root-ca`)

```bash
make ssh VM=root-ca
sudo -i
```

### 1a. Directory layout and database

```bash
mkdir -p /root/ca/{certs,crl,csr,newcerts,private}
cd /root/ca
chmod 700 private
touch index.txt          # the CA's database of issued/revoked certs
echo 1000 > serial       # next certificate serial number (hex)
echo 1000 > crlnumber    # next CRL number
```

### 1b. Root CA config

```bash
cat > /root/ca/openssl.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /root/ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
crlnumber         = $dir/crlnumber
private_key       = $dir/private/root.key
certificate       = $dir/certs/root.crt
crl               = $dir/crl/root.crl
crl_extensions    = crl_ext
default_md        = sha384
default_crl_days  = 30
preserve          = no
unique_subject    = no
policy            = policy_strict

# The root only signs subordinate CAs in our org: C and O must match.
[ policy_strict ]
countryName       = match
organizationName  = match
commonName        = supplied

[ req ]
default_md         = sha384
string_mask        = utf8only
distinguished_name = req_distinguished_name

[ req_distinguished_name ]

# Applied to the self-signed root certificate
[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true
keyUsage               = critical, keyCertSign, cRLSign

# Applied when the root signs the intermediate.
# pathlen:0 = the intermediate may sign end-entity certs but NOT further CAs.
[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign

[ crl_ext ]
authorityKeyIdentifier = keyid:always
EOF
```

### 1c. Root key and self-signed certificate

```bash
# -algorithm EC            elliptic-curve key
# -pkeyopt ...:P-384       which curve
# -aes256                  encrypt the key file with a passphrase (you'll be prompted)
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -aes256 \
  -out private/root.key
chmod 400 private/root.key

# -new -x509        create a self-signed cert directly (no CSR)
# -days 7300        ~20 years; roots are long-lived
# -extensions v3_ca use the [v3_ca] section above
# -subj             set the subject non-interactively
openssl req -config openssl.cnf -new -x509 -key private/root.key \
  -days 7300 -extensions v3_ca \
  -subj "/C=US/O=Homelab/CN=Homelab Root CA" \
  -out certs/root.crt
```

### 1d. Inspect it

```bash
openssl x509 -in certs/root.crt -noout -text   # -noout: don't print the PEM blob
```

Look for: `Issuer` = `Subject` (self-signed), `CA:TRUE`,
`Certificate Sign, CRL Sign`, and the validity dates.

Leave this session open. You'll come back to sign the intermediate.

---

## 2. Intermediate CA (on `issuing-ca`)

In a second terminal on the host:

```bash
make ssh VM=issuing-ca
sudo -i
mkdir -p /root/ca/{certs,crl,csr,newcerts,private}
cd /root/ca
chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > crlnumber
```

### 2a. Intermediate CA config

```bash
cat > /root/ca/openssl.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /root/ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
crlnumber         = $dir/crlnumber
private_key       = $dir/private/intermediate.key
certificate       = $dir/certs/intermediate.crt
crl               = $dir/crl/intermediate.crl
crl_extensions    = crl_ext
default_md        = sha256
default_days      = 397          # max lifetime browsers accept for TLS server certs
default_crl_days  = 7
preserve          = no
unique_subject    = no
policy            = policy_loose

# Copy extensions (notably subjectAltName) from the CSR into the cert.
# Convenient but powerful: ALWAYS inspect a CSR before signing it.
copy_extensions   = copy

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_md         = sha384
string_mask        = utf8only
distinguished_name = req_distinguished_name

[ req_distinguished_name ]

# TLS server certificates
[ server_cert ]
basicConstraints       = critical, CA:FALSE
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
keyUsage               = critical, digitalSignature
extendedKeyUsage       = serverAuth

# TLS client certificates (for mTLS experiments later)
[ client_cert ]
basicConstraints       = critical, CA:FALSE
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
keyUsage               = critical, digitalSignature
extendedKeyUsage       = clientAuth

[ crl_ext ]
authorityKeyIdentifier = keyid:always
EOF
```

### 2b. Intermediate key and CSR

```bash
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -aes256 \
  -out private/intermediate.key
chmod 400 private/intermediate.key

# Without -x509, req produces a CSR (a signing request) instead of a cert
openssl req -config openssl.cnf -new -key private/intermediate.key \
  -subj "/C=US/O=Homelab/CN=Homelab Issuing CA" \
  -out csr/intermediate.csr

install -m 644 csr/intermediate.csr /tmp/   # stage for pickup
```

### 2c. Sign the intermediate (back on `root-ca`)

```bash
cd /root/ca
scp vagrant@issuing-ca.lab.test:/tmp/intermediate.csr csr/   # accept host key, password: vagrant

# Always inspect before signing
openssl req -in csr/intermediate.csr -noout -text

# -extensions v3_intermediate_ca  make it a CA with pathlen:0
# -days 3650                      10 years, shorter than the root
# -notext                         write only PEM, no human-readable dump
openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
  -days 3650 -notext \
  -in csr/intermediate.csr -out certs/intermediate.crt
# Enter the root key passphrase, then answer y to "Sign the certificate?" and y to "commit?"

cat index.txt                                          # the new entry, status V (valid)
openssl verify -CAfile certs/root.crt certs/intermediate.crt   # -> OK

# Hand back the signed cert plus the root
scp certs/intermediate.crt certs/root.crt vagrant@issuing-ca.lab.test:/tmp/
```

### 2d. Install on `issuing-ca`

```bash
cd /root/ca
cp /tmp/intermediate.crt /tmp/root.crt certs/
cat certs/intermediate.crt certs/root.crt > certs/ca-chain.crt
openssl x509 -in certs/intermediate.crt -noout -subject -issuer
```

### 2e. Take the root offline

The root has done its job. Exit the `root-ca` session, then on the host:

```bash
make halt VM=root-ca     # bring it back later with: make up VM=root-ca
```

In real life this machine (or HSM, Hardware Security Module) stays powered off
in a safe and only comes out to sign or renew intermediates and publish root CRLs.

---

## 3. Server certificate for `client`

### 3a. Key + CSR (on `client`)

```bash
make ssh VM=client
sudo -i
mkdir -p /root/tls && cd /root/tls

# -newkey ec ...   generate the key and CSR in one step
# -nodes           don't encrypt the key (nginx must read it unattended)
# -addext          put the subjectAltName into the CSR
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout client.key \
  -subj "/CN=client.lab.test" \
  -addext "subjectAltName=DNS:client.lab.test,IP:192.168.150.12" \
  -out client.csr
chmod 600 client.key
install -m 644 client.csr /tmp/
```

> Clients ignore the CN (Common Name) and match the hostname against **SAN**
> (Subject Alternative Name). No SAN = no trust.

### 3b. Sign it (on `issuing-ca`)

```bash
cd /root/ca
scp vagrant@client.lab.test:/tmp/client.csr csr/
openssl req -in csr/client.csr -noout -text     # check the SAN and that it's not asking for CA:TRUE

openssl ca -config openssl.cnf -extensions server_cert -notext \
  -in csr/client.csr -out certs/client.lab.test.crt

# Proper chain check: root is the trust anchor, intermediate is "untrusted" (supplied by the server)
openssl verify -CAfile certs/root.crt -untrusted certs/intermediate.crt \
  certs/client.lab.test.crt                     # -> OK

# Server sends leaf + intermediate (never the root)
cat certs/client.lab.test.crt certs/intermediate.crt > /tmp/client-fullchain.crt
cp certs/root.crt /tmp/root.crt
chmod 644 /tmp/client-fullchain.crt /tmp/root.crt
```

---

## 4. Trust the root and serve HTTPS (on `client`)

### 4a. Add the root to the system trust store

```bash
cd /root/tls
scp vagrant@issuing-ca.lab.test:/tmp/{client-fullchain.crt,root.crt} .

cp root.crt /etc/pki/ca-trust/source/anchors/homelab-root.crt
update-ca-trust extract      # rebuilds the bundles in /etc/pki/ca-trust/extracted/

trust list | grep -A2 "Homelab Root CA"   # confirm it's in
```

### 4b. nginx with the new cert

```bash
dnf -y install nginx         # -y: answer yes to prompts

mkdir -p /etc/pki/nginx/private
install -m 644 client-fullchain.crt /etc/pki/nginx/server.crt
install -m 600 client.key            /etc/pki/nginx/private/server.key
restorecon -Rv /etc/pki/nginx        # fix SELinux labels (-R recursive, -v verbose)

cat > /etc/nginx/conf.d/lab.conf <<'EOF'
server {
    listen 443 ssl;
    server_name client.lab.test;

    ssl_certificate     /etc/pki/nginx/server.crt;
    ssl_certificate_key /etc/pki/nginx/private/server.key;

    default_type text/plain;
    location / {
        return 200 "Hello over TLS from $hostname\n";
    }
}
EOF

nginx -t                          # -t: test config syntax
systemctl enable --now nginx
```

The box doesn't install firewalld, so port 443 is reachable from the other VMs. If you add
firewalld later: `firewall-cmd --add-service=https --permanent && firewall-cmd --reload`.

### 4c. Test

```bash
curl https://client.lab.test                    # works with no -k: the chain is trusted

# See exactly what the server presents
openssl s_client -connect client.lab.test:443 -servername client.lab.test \
  -showcerts </dev/null 2>/dev/null | grep -E "^ *[0-9] s:|i:|Verify return"
```

Expected: depth 0 = `client.lab.test` issued by the Issuing CA, depth 1 = the Issuing CA
issued by the Root, and `Verify return code: 0 (ok)`.

### 4d. Watch trust fail elsewhere (on `issuing-ca`)

`issuing-ca` has the root file but has **not** added it to its trust store:

```bash
curl https://client.lab.test                                  # fails: unable to get local issuer certificate
curl --cacert /root/ca/certs/root.crt https://client.lab.test # works: trust supplied explicitly
```

That's the whole game: a certificate is only as good as the trust anchors on the machine checking it.

---

## 5. Revocation (on `issuing-ca`)

```bash
cd /root/ca

openssl ca -config openssl.cnf -revoke certs/client.lab.test.crt
cat index.txt                     # status flips from V to R

openssl ca -config openssl.cnf -gencrl -out crl/intermediate.crl
openssl crl -in crl/intermediate.crl -noout -text   # serial 1000 is listed

openssl verify -crl_check -CAfile certs/root.crt -untrusted certs/intermediate.crt \
  -CRLfile crl/intermediate.crl certs/client.lab.test.crt
# -> error 23: certificate revoked
```

Now back on `client`, `curl https://client.lab.test` **still works**. Nothing told curl where
the CRL lives, and the client never checked. Revocation only works if:

1. certs carry a **CDP** (CRL Distribution Point) URL or an **OCSP** (Online Certificate
   Status Protocol) responder URL, **and**
2. the CRL/OCSP endpoint is actually reachable, **and**
3. the relying software is configured to check.

That gap is why the industry is moving to short-lived certificates instead of
relying on revocation, which is where ACME and step-ca come in.

---

## Reset

On the host, from the repo root:

```bash
make destroy            # wipe all three VMs (runs vagrant destroy -f: no confirmation prompt)
make up
```

## Next experiments

- Add `crlDistributionPoints = URI:http://issuing-ca.lab.test/intermediate.crl` to
  `server_cert`, publish the CRL with nginx on `issuing-ca`, and re-test revocation.
- Issue a `client_cert` and set up **mTLS** (mutual TLS) on nginx with `ssl_verify_client on`.
- Run an OCSP responder: `openssl ocsp -index index.txt -port 2560 ...`.
- Renew the intermediate with the same key and watch which certs keep validating.
- Rotate the server cert: issue a replacement before the old one expires and swap it into
  nginx with `systemctl reload nginx`, with no downtime.
- Automate renewal with `certmonger`, or compare against Dogtag (FreeIPA).
- Part 2: replace the issuing CA with **step-ca** and get certs automatically over ACME.
