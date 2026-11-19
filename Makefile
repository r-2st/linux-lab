# ===================================================================================
# linux-lab Makefile
#
# DESCRIPTION: Set up the repo, run pre-commit, build Vagrant boxes with Packer, and
#              drive the Vagrant labs under labs/ (LAB=<name>).
#
# AUTHOR: Ross Thompson <7013129+r-2st@users.noreply.github.com>, Copilot
#
# ===================================================================================

CYAN   := $(shell tput -Txterm setaf 6)
GREEN  := $(shell tput -Txterm setaf 2)
RESET  := $(shell tput -Txterm sgr0)
WHITE  := $(shell tput -Txterm setaf 7)
YELLOW := $(shell tput -Txterm setaf 3)

# Box to build/import: a file name (minus .pkrvars.hcl) from packer/vars/
BOX ?= rocky-8.10
# Lab to drive: a directory under labs/
LAB ?= cert-lab
# Optional single machine for vagrant targets, e.g. `make ssh VM=client`
VM  ?=
# mermaid.js version vendored into the docs site (make vendor-mermaid)
MERMAID_VERSION ?= 12.3.0

PACKER_TEMPLATE := packer/vagrant-box.pkr.hcl
READINESS       := packer/readiness/qemu-readiness.pkr.hcl
BOXES           := $(basename $(basename $(notdir $(wildcard packer/vars/*.pkrvars.hcl))))
LAB_DIR         := labs/$(LAB)
VAGRANTFILES    := $(wildcard labs/*/Vagrantfile)
PLAYBOOKS       := $(wildcard labs/*/provision/site.yml)

# uv manages the Python tooling (ansible-core, pre-commit) in a repo-local .venv;
# make setup installs uv first if it's missing.
# Resolved when each recipe runs, so a uv installed by install-uv is found.
UV = $$(command -v uv || echo $(HOME)/.local/bin/uv)
# Put the repo's tools first on PATH for every recipe (incl. Vagrant's ansible provisioner).
export PATH := $(CURDIR)/.venv/bin:$(PATH)

.PHONY: all setup install-uv sync galaxy run update remove fmt init validate readiness \
	box box-add boxes list up halt provision status ssh destroy clean docs docs-build \
	vendor-mermaid help

all: help

## Repo
setup: install-uv sync galaxy ## Bootstrap all tooling: uv, .venv (ansible-core, pre-commit), hooks, Galaxy content.
	pre-commit install
	pre-commit install-hooks
	@echo "${GREEN}Tooling ready. Host still needs: packer, vagrant + vagrant-libvirt, libvirt/KVM, xorriso, ruby.${RESET}"

install-uv: ## Install uv if missing (Homebrew if available, else the official installer).
	@if command -v uv >/dev/null 2>&1 || [ -x "$(HOME)/.local/bin/uv" ]; then \
		echo "uv already installed: $$("$(UV)" --version)"; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install uv; \
	else \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	fi

sync: ## Create/refresh .venv from uv.lock (exact pinned versions).
	$(UV) sync --locked

galaxy: ## Install Ansible Galaxy content from ansible/requirements.yml.
	ansible-galaxy role install -r ansible/requirements.yml -p ansible/galaxy_roles
	ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections

run: ## Run pre-commit checks manually
	pre-commit run --all-files

update: ## Upgrade uv.lock and pre-commit hook revs (review and commit the result).
	$(UV) lock --upgrade
	$(UV) sync
	pre-commit autoupdate

remove: ## Uninstall pre-commit hooks and delete .venv and Galaxy content (keeps uv).
	-pre-commit uninstall -t pre-commit -t pre-merge-commit -t pre-push -t prepare-commit-msg -t commit-msg -t post-commit -t post-checkout -t post-merge -t post-rewrite
	rm -rf .venv ansible/collections ansible/galaxy_roles

## Packer
fmt: ## Format all Packer templates and var files.
	packer fmt -recursive packer/

init: ## Install the Packer plugins the templates need.
	packer init $(PACKER_TEMPLATE)
	packer init $(READINESS)

validate: init ## Validate every box var file, the readiness test, Vagrantfiles, and playbooks.
	@for b in $(BOXES); do echo "==> packer validate $$b"; packer validate -var-file=packer/vars/$$b.pkrvars.hcl -var output_dir=packer/output/.validate-does-not-exist $(PACKER_TEMPLATE) || exit 1; done
	@echo "==> packer validate readiness"; packer validate $(READINESS)
	@for v in $(VAGRANTFILES); do echo "==> ruby -c $$v"; ruby -c "$$v" >/dev/null || exit 1; done
	@command -v ansible-playbook >/dev/null || { echo "ansible-playbook not found; run make setup"; exit 1; }
	@for p in $(PLAYBOOKS); do echo "==> ansible syntax $$p"; ansible-playbook --syntax-check -i localhost, "$$p" >/dev/null || exit 1; done

readiness: init ## Smoke-test the host's Packer + QEMU/KVM setup.
	packer build $(READINESS)

box: init ## Build boxes/<BOX>-libvirt.box: BOX=<name>
	packer build -var-file=packer/vars/$(BOX).pkrvars.hcl $(PACKER_TEMPLATE)

box-add: ## Import boxes/<BOX>-libvirt.box into Vagrant as local/<BOX>.
	vagrant box add --force --name local/$(BOX) boxes/$(BOX)-libvirt.box

boxes: ## Build and import every box in packer/vars/.
	@for b in $(BOXES); do $(MAKE) --no-print-directory box box-add BOX=$$b || exit 1; done

list: ## List buildable boxes, imported boxes, and labs.
	@echo 'Buildable (BOX=):'; for b in $(BOXES); do echo "  $$b"; done
	@echo 'Imported into Vagrant:'; vagrant box list | sed 's/^/  /'
	@echo 'Labs (LAB=):'; for v in $(VAGRANTFILES); do echo "  $$(basename $$(dirname $$v))"; done

## Vagrant
up: ## Start the lab (or one machine with VM=<name>).
	cd $(LAB_DIR) && vagrant up $(VM)

halt: ## Shut down the lab (or VM=<name>).
	cd $(LAB_DIR) && vagrant halt $(VM)

provision: ## Re-run provisioners (or VM=<name>).
	cd $(LAB_DIR) && vagrant provision $(VM)

status: ## Show lab machine status.
	cd $(LAB_DIR) && vagrant status

ssh: ## SSH into a lab machine: VM=<name>
	@test -n "$(VM)" || { echo "VM is required, e.g. make ssh VM=client"; exit 1; }
	cd $(LAB_DIR) && vagrant ssh $(VM)

destroy: ## Destroy the lab VMs (or VM=<name>).
	cd $(LAB_DIR) && vagrant destroy -f $(VM)

clean: ## Remove Packer build output (keeps boxes/*.box).
	rm -rf packer/output/ packer_cache/ crash.log

## Docs
docs: ## Live-preview the docs site at http://localhost:8000
	zensical serve

docs-build: ## Build the docs site into site/ (strict: warnings fail).
	zensical build --strict --clean

vendor-mermaid: ## Vendor a pinned mermaid.js for the docs: MERMAID_VERSION=<x.y.z>
	tools/vendor-mermaid.sh $(MERMAID_VERSION)

## Help:
help: ## Show this help.
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET} [BOX=<name>] [LAB=<name>] [VM=<name>]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) {printf "    ${YELLOW}%-20s${GREEN}%s${RESET}\n", $$1, $$2} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)
