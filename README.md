# linux-lab

Hands-on labs for Linux distros and related tech, built with [Packer](https://developer.hashicorp.com/packer),
run with [Vagrant](https://developer.hashicorp.com/vagrant) on libvirt/KVM, and configured with
[Ansible](https://docs.ansible.com/).

Packer turns an upstream cloud image into a Vagrant box (one template, one var file per distro).
Each lab is a directory under `labs/` with a `Vagrantfile` that builds VMs from those boxes and
an Ansible playbook that configures them.

## Layout

```text
.
├── packer/
│   ├── vagrant-box.pkr.hcl         # One template for every box
│   ├── vars/<box>.pkrvars.hcl      # Per-distro image URL + checksum
│   ├── scripts/                    # Provisioning run inside the image (network, python, cleanup)
│   ├── readiness/                  # Smoke test for the local Packer + QEMU/KVM setup
│   └── output/                     # Build output (gitignored)
├── boxes/                          # Built *.box files (gitignored)
├── ansible.cfg                     # Shared Ansible config; roles_path = ansible/roles
├── ansible/roles/lab_base/         # Baseline for every lab VM (/etc/hosts, banners)
├── labs/
│   └── cert-lab/                   # Two-tier PKI lab, see its README
│       ├── Vagrantfile
│       └── provision/site.yml
├── .github/workflows/validate.yml  # CI: pre-commit + make validate
└── Makefile                        # Entry point for everything below
```

## Boxes

| `BOX=` | Distro | Source image |
| --- | --- | --- |
| `rocky-8.10` | Rocky Linux 8.10 (pinned build) | GenericCloud-Base |
| `rocky-9.4` | Rocky Linux 9.4 (pinned build, from the vault) | GenericCloud-Base |
| `rocky-10` | Rocky Linux 10 (latest) | GenericCloud-Base |
| `alma-9` | AlmaLinux 9 (latest) | GenericCloud |
| `alma-10` | AlmaLinux 10 (latest) | GenericCloud |
| `debian-12` | Debian 12 bookworm | genericcloud |
| `debian-13` | Debian 13 trixie | genericcloud |
| `ubuntu-24.04` | Ubuntu 24.04 LTS noble | server cloudimg |
| `ubuntu-26.04` | Ubuntu 26.04 LTS resolute | server cloudimg |

Every box has:

- a `vagrant` user (password `vagrant`, passwordless sudo); Vagrant swaps in its own key on first `up`
- DHCP on `eth0` (traditional NIC names, so it works no matter which PCI slot libvirt picks)
- cloud-init disabled after the build, and an empty `machine-id` so each VM gets its own
- Python 3.9+ as `python3` for Ansible (EL8 gets `python3.12`, since its 3.6 is too old)

The Rocky boxes are pinned to the point releases used in production (8.10 and 9.4) and named
after them, so a rebuild always produces the same release. The others track the latest image
for their major version.

To add a distro, drop a new `packer/vars/<box>.pkrvars.hcl` with `name`, `image_url`, and
`image_checksum`; `make validate` and `make box BOX=<box>` pick it up automatically.

**EL10 (Rocky/Alma 10) needs an x86-64-v3 CPU.** The Packer build passes `-cpu host`; in a
Vagrantfile set `lv.cpu_mode = "host-passthrough"` (or `host-model`) for those boxes.

## Prerequisites

Fedora example (adjust for your distro):

```sh
sudo dnf install -y @virtualization xorriso make ruby ansible-core
sudo dnf install -y packer vagrant      # from the HashiCorp repo
vagrant plugin install vagrant-libvirt
sudo usermod -aG libvirt "$USER"        # log out/in afterwards
```

- KVM must be available (`ls /dev/kvm`).
- `xorriso` (or `mkisofs`) is needed for Packer's `cd_content` cloud-init seed ISO.
- `ansible-core` runs on the host; Vagrant's `ansible` provisioner calls `ansible-playbook`.

Check the host with the readiness build:

```sh
make readiness
```

## Quick start: cert-lab

```sh
make box     BOX=rocky-8.10   # -> boxes/rocky-8.10-libvirt.box
make box-add BOX=rocky-8.10   # -> Vagrant box local/rocky-8.10
make up      LAB=cert-lab
make ssh     LAB=cert-lab VM=issuing-ca
make destroy LAB=cert-lab
```

`BOX` defaults to `rocky-8.10` and `LAB` to `cert-lab`. Run `make help` for every target and
`make list` for the boxes and labs available.

## Make targets

| Group | Target | What it does |
| --- | --- | --- |
| Repo | `setup` / `run` / `remove` | Install, run, or remove pre-commit hooks |
| Packer | `fmt` | `packer fmt -recursive packer/` |
| Packer | `init` / `validate` | Install plugins / validate every box var file, the readiness test, each `Vagrantfile`, and each lab playbook |
| Packer | `readiness` | Smoke-test Packer + QEMU/KVM on this host |
| Packer | `box` / `box-add` | Build `boxes/$(BOX)-libvirt.box` / import it as `local/$(BOX)` |
| Packer | `boxes` | Build and import every box |
| Packer | `list` | Show buildable boxes, imported boxes, and labs |
| Vagrant | `up` / `halt` / `provision` / `status` / `ssh` / `destroy` | Run the matching `vagrant` command in `labs/$(LAB)`, optionally for one `VM` |
| Vagrant | `clean` | Delete Packer build output (keeps `boxes/*.box`) |

## Adding a lab

1. `mkdir -p labs/<name>/provision` and add a `Vagrantfile` (copy `labs/cert-lab/Vagrantfile`
   as a starting point; give it its own libvirt network name and subnet).
2. Write `provision/site.yml`; reuse `lab_base` and put anything shared across labs in
   `ansible/roles/`. Point the Vagrant provisioner at `../../ansible.cfg`.
3. Add a `README.md` with the lab's goals, topology, and exercises.
4. `make validate`, then `make up LAB=<name>`.

## Artifacts

Boxes, disk images, Packer output, and `.vagrant/` state are all gitignored and blocked by the
`check-added-large-files` pre-commit hook. They stay on the local disk only.

vagrant-libvirt copies each imported box into the libvirt `default` storage pool, and neither
`vagrant box remove` nor re-importing a rebuilt box deletes the old copy. Prune them once no VM
uses them:

```sh
virsh -c qemu:///system vol-list default | grep VAGRANTSLASH
virsh -c qemu:///system vol-delete --pool default <volume>
```

## CI/CD

`.github/workflows/validate.yml` runs pre-commit (incl. ansible-lint, actionlint, gitleaks,
shellcheck, `packer fmt`) and `make validate` on every push and PR to `main`. Actual builds need
KVM and multi-GB downloads, so they run locally, not in CI.
