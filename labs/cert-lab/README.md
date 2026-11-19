# cert-lab

A two-tier PKI built by hand with OpenSSL: an offline root CA, an issuing (intermediate) CA,
and a client web server that gets a certificate from the issuing CA and is trusted through
the chain.

## Goals

- Understand why a root CA is kept offline and what an intermediate buys you.
- Build CA hierarchies with the right extensions (`basicConstraints`, `pathlen`, `keyUsage`).
- Issue, deploy, verify, and revoke a TLS server certificate.
- Distribute trust with the system trust store (`update-ca-trust`).

## Topology

| VM | IP | FQDN | Role |
| --- | --- | --- | --- |
| `root-ca` | 192.168.150.10 | `root-ca.lab.test` | Offline root CA; halt it except when signing |
| `issuing-ca` | 192.168.150.11 | `issuing-ca.lab.test` | Intermediate CA that signs leaf certs |
| `client` | 192.168.150.12 | `client.lab.test` | Web server (and test client) |

All three run on the `local/rocky-8` box on the private libvirt network `ca-lab`. Ansible
(`provision/site.yml`) puts every host in `/etc/hosts`. The VMs can `scp` to each other as
`vagrant` / `vagrant`.

## Usage

```sh
make box BOX=rocky-8 && make box-add BOX=rocky-8   # once
make up LAB=cert-lab
make ssh LAB=cert-lab VM=root-ca
make halt LAB=cert-lab VM=root-ca                  # "offline" the root when done signing
```

## Exercises

1. **Root CA** (on `root-ca`): create a directory layout (`certs/ crl/ newcerts/ private/`,
   `index.txt`, `serial`), an `openssl.cnf` with a `v3_ca` section
   (`basicConstraints = critical, CA:true, pathlen:1`, `keyUsage = critical, keyCertSign, cRLSign`),
   then generate the root key and a long-lived self-signed root certificate.
2. **Issuing CA** (on `issuing-ca`): generate a key and CSR, copy the CSR to `root-ca`, and sign
   it with a `v3_intermediate_ca` section (`pathlen:0`). Copy the certificate back and build a
   `chain.pem` (intermediate + root).
3. **Leaf certificate** (on `client`): install `httpd` + `mod_ssl` or `nginx`, generate a key and
   a CSR for `client.lab.test` with a `subjectAltName`, have `issuing-ca` sign it with a
   `server_cert` section (`extendedKeyUsage = serverAuth`), and configure the web server with
   the leaf cert and chain.
4. **Trust**: copy the root cert into `/etc/pki/ca-trust/source/anchors/` on `issuing-ca` and
   `client`, run `update-ca-trust`, and confirm `curl https://client.lab.test` works without `-k`.
   Check the chain with `openssl s_client -connect client.lab.test:443 -showcerts` and
   `openssl verify -CAfile root.pem -untrusted intermediate.pem leaf.pem`.
5. **Revocation**: revoke the leaf on `issuing-ca`, generate a CRL, and confirm
   `openssl verify -crl_check -CRLfile ...` rejects it. Stretch: publish the CRL over HTTP and add
   a `crlDistributionPoints` extension, or run `openssl ocsp` as a responder.
6. **Rotation**: issue a replacement leaf before the old one expires and swap it in with no
   downtime.

Stretch ideas: automate issuance with `certmonger`, or replace the issuing CA with
`step-ca` / Dogtag (FreeIPA) and compare.

## Reset

```sh
make destroy LAB=cert-lab && make up LAB=cert-lab
```
