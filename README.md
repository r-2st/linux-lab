# linux-lab

Hands-on labs for Linux distros and related tech, built with [Packer](https://developer.hashicorp.com/packer)
and run with [Vagrant](https://developer.hashicorp.com/vagrant) on libvirt/KVM.

Packer turns an upstream cloud image into a Vagrant box; each lab is a directory with a
`Vagrantfile` that spins up one or more VMs from that box.

## Layout

```text
.
├── cert-lab/                       # Two-tier PKI lab (root CA, issuing CA, client)
│   ├── rocky8-vagrant-box.pkr.hcl  # Builds rocky-8.10-libvirt.box from the GenericCloud image
│   ├── qemu-readiness.pkr.hcl      # Smoke test for the local Packer + QEMU/KVM setup
│   └── Vagrantfile                 # The lab VMs
├── .github/workflows/validate.yml  # CI: pre-commit + packer validate
├── Makefile                        # Entry point for everything below
└── VERSION / CHANGELOG.md
```

New labs get their own top-level directory with a `Vagrantfile` and any Packer templates or
provisioning scripts they need.

## Prerequisites

Fedora example (adjust for your distro):

```sh
sudo dnf install -y @virtualization xorriso make ruby
sudo dnf install -y packer vagrant      # from the HashiCorp repo
vagrant plugin install vagrant-libvirt
sudo usermod -aG libvirt "$USER"        # log out/in afterwards
```

- KVM must be available (`ls /dev/kvm`).
- `xorriso` (or `mkisofs`) is needed for Packer's `cd_content` cloud-init seed ISO.

Check the host with the readiness build:

```sh
make build LAB=cert-lab TEMPLATE=qemu-readiness.pkr.hcl
```

## Quick start: cert-lab

```sh
make build   LAB=cert-lab TEMPLATE=rocky8-vagrant-box.pkr.hcl  # -> cert-lab/rocky-8.10-libvirt.box
make box-add LAB=cert-lab BOX_FILE=rocky-8.10-libvirt.box BOX_NAME=local/rocky-8.10
make up      LAB=cert-lab
make ssh     LAB=cert-lab VM=issuing-ca
make destroy LAB=cert-lab
```

`LAB` defaults to `cert-lab`, so it can be omitted for that lab. Run `make help` for every target.

## Make targets

| Group | Target | What it does |
| --- | --- | --- |
| Repo | `setup` / `run` / `remove` | Install, run, or remove pre-commit hooks |
| Packer | `fmt` | `packer fmt -recursive .` |
| Packer | `init` / `validate` | Install plugins / validate every `*.pkr.hcl` and `Vagrantfile` |
| Packer | `build` | `packer build $(TEMPLATE)` inside `$(LAB)` |
| Packer | `box-add` / `box-list` | Import a built box into Vagrant / list boxes |
| Vagrant | `up` / `halt` / `provision` / `status` / `ssh` / `destroy` | Run the matching `vagrant` command in `$(LAB)`, optionally for one `VM` |
| Vagrant | `clean` | Delete Packer `output-*` dirs, caches, and manifests in `$(LAB)` (keeps `.box` files) |

## Artifacts

Boxes, disk images, Packer output directories, and `.vagrant/` state are all gitignored and
blocked by the `check-added-large-files` pre-commit hook. They stay on the local disk only.

## CI/CD

`.github/workflows/validate.yml` runs pre-commit and `make validate` on every push and PR to
`main`. Actual builds need KVM and multi-GB downloads, so they run locally, not in CI.
