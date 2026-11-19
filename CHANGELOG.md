# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/).
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-19

Portable tooling bootstrap.

### Added
- `pyproject.toml`, `uv.lock`, `.python-version`: ansible-core and pre-commit pinned in a
  repo-local `.venv` managed by uv.
- `ansible/requirements.yml` placeholder for Galaxy roles/collections, installed under `ansible/`.
- Make targets: `install-uv`, `sync`, `galaxy`, `update`.

### Changed
- `make setup` installs uv if needed, syncs `.venv`, installs hooks and Galaxy content; it no
  longer runs `pre-commit autoupdate` (moved to `make update`).
- Make targets and Vagrantfiles put `.venv/bin` first on `PATH`, so Vagrant's ansible
  provisioner uses the pinned ansible-core.
- ansible-lint hook pinned to the `.python-version` interpreter.
- CI uses uv and the lockfile; actions pinned (`setup-packer@v3.4.0`, `setup-uv@v10.3.3`) and
  moved off deprecated Node 20 versions.

## [0.1.0] - 2026-11-19

Restructure into reusable boxes and self-contained labs.

### Added
- `packer/vagrant-box.pkr.hcl`: one box template driven by `packer/vars/*.pkrvars.hcl`, with
  boxes for Rocky 8.10/9.4 (pinned to the production releases)/10, AlmaLinux 9/10,
  Debian 12/13, and Ubuntu 24.04/26.04.
- `packer/scripts/`: network (eth0 DHCP via `net.ifnames=0`), Python for Ansible, and cleanup.
- Ansible provisioning: shared `ansible/ansible.cfg` and `lab_base` role; cert-lab playbook.
- `labs/cert-lab/README.md` with goals, topology, and exercises.
- pre-commit hooks: ansible-lint, actionlint, gitleaks; hook versions updated.
- Make targets: `box`, `boxes`, `readiness`, `list`.

### Changed
- `cert-lab/` moved to `labs/cert-lab/`; box build and readiness test moved to `packer/`.
- cert-lab uses the `local/rocky-8.10` box and Ansible instead of inline shell provisioning.
- Built boxes go to `boxes/`, Packer output to `packer/output/`.

### Fixed
- EL8 boxes include Python 3.12, so current ansible-core can manage them.

## [0.0.1] - 2026-11-19

Initial setup to get a working environment with requirements in place.

### Added
- Base files bootstrapped from `container-repo-template`, adapted for Packer and Vagrant.
- Makefile targets for Packer (`init`, `validate`, `build`, `box-add`) and Vagrant (`up`, `halt`, `ssh`, `destroy`).
- pre-commit hooks for `packer fmt`, Vagrantfile syntax, shellcheck, and large-file/private-key guards.
- GitHub Actions workflow running pre-commit and `make validate`.
- `cert-lab`: Rocky Linux 8.10 libvirt box build and a three-node PKI lab.

### Changed
- N/A

### Deprecated
- N/A

### Fixed
- N/A

### Removed
- N/A

### Security
- N/A
