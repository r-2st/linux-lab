# cert-lab: Two-Tier PKI with OpenSSL

Build a root CA, an intermediate (issuing) CA, and a server certificate by hand, trust the
chain, serve HTTPS with it, then revoke a certificate.

The lab has one directory per distro release, because OpenSSL versions differ between
releases. Each one has its own walkthrough, `Vagrantfile`, libvirt network, and subnet, so
releases can run side by side.

| Release | `LAB=` | Box | OpenSSL | Network |
| --- | --- | --- | --- | --- |
| [Rocky 8.10](rocky-8.10/README.md) | `cert-lab/rocky-8.10` (default) | `local/rocky-8.10` | 1.1.1k | `ca-lab`, 192.168.150.0/24 |
| [Rocky 9.4](rocky-9.4/README.md) | `cert-lab/rocky-9.4` | `local/rocky-9.4` | 3.0 | `ca-lab-rocky-9.4`, 192.168.151.0/24 |

To add a release, copy an existing directory to `<distro>-<release>/`, then change `BOX`,
`NETWORK`, `PREFIX`, and the IPs in its `Vagrantfile` and README.
