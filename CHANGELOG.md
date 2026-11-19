# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/).
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [0.5.0] - 2026-11-19

cert-lab is ready to use: a full, tested walkthrough.

### Changed

- `labs/cert-lab/README.md`: replaced the exercise outline with a step-by-step Part 1
  walkthrough (root CA, intermediate, server cert, trust store, nginx, revocation) using
  `make` targets. Every step was run end to end on the `local/rocky-8.10` VMs.

## [0.4.0] - 2026-11-19

Zensical, self-hosted Mermaid, and GitHub Pages.

### Added

- `.github/workflows/docs.yml`: build and deploy the docs site to GitHub Pages from `main`
  (actions pinned to commit SHAs).
- mermaid.js 12.3.0 vendored under `docs/assets/javascripts/vendor/` and loaded via
  `extra_javascript`, so pages never fetch it from unpkg. `tools/vendor-mermaid.sh` /
  `make vendor-mermaid` re-pin it with sha512 verification against the npm registry.
- `.gitleaks.toml`: default rules plus an allowlist for the vendored directory.

### Changed

- Docs build with Zensical 0.1.2 instead of MkDocs + Material for MkDocs (end of life
  2027-05-05), using the same `mkdocs.yml`; `make docs` / `make docs-build` call `zensical`.
- pre-commit excludes `docs/assets/javascripts/vendor/` so hooks cannot rewrite vendored files.

### Removed

- `mkdocs` and `mkdocs-material` (and 16 transitive packages) from the `docs` dependency group.

## [0.3.0] - 2026-11-19

Documentation site.

### Added

- MkDocs + Material docs site (`mkdocs.yml`, `docs/`), installed via a `docs` dependency group.
- Mermaid diagrams: the Packer → Vagrant box pipeline (`docs/building-boxes.md`) and the
  Makefile workflow (`docs/makefile.md`).
- Home and cert-lab pages include `README.md` and `labs/cert-lab/README.md` via snippets, so
  the READMEs stay the single source.
- Make targets `docs` (live preview) and `docs-build` (strict build); CI `docs` job.

### Changed

- `check-yaml` runs with `--unsafe` (syntax only) to allow `mkdocs.yml`'s `!!python/name` tags.

## [0.2.0] - 2026-11-19

Portable tooling bootstrap.

### Added

- `pyproject.toml`, `uv.lock`, `.python-version`: ansible-core and pre-commit pinned in a
  repo-local `.venv` managed by uv.
- `ansible/requirements.yml` placeholder for Galaxy roles/collections, installed under `ansible/`.
- Make targets: `install-uv`, `sync`, `galaxy`, `update`.

### Removed

- markdownlint (Node.js) pre-commit hook, replaced by PyMarkdown (pure Python); rules
  configured in `pyproject.toml`. No pre-commit hook depends on Node.js.

### Changed

- `make setup` installs uv if needed, syncs `.venv`, installs hooks and Galaxy content; it no
  longer runs `pre-commit autoupdate` (moved to `make update`).
- Make targets and Vagrantfiles put `.venv/bin` first on `PATH`, so Vagrant's ansible
  provisioner uses the pinned ansible-core.
- ansible-lint hook pinned to the `.python-version` interpreter.
- `.gitignore` regenerated from the toptal.com templates (linux, macos, windows, packer,
  vagrant, ansible, python) plus a repo-specific section; `packer/vars/*.pkrvars.hcl` is
  re-included because the packer template ignores all var files.
- CI uses uv and the lockfile; every action is pinned to a full commit SHA (release tag in a
  trailing comment) and moved off deprecated Node 20 versions.

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
