# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/).
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

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
