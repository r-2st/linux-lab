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
BOX ?= rocky-8
# Lab to drive: a directory under labs/
LAB ?= cert-lab
# Optional single machine for vagrant targets, e.g. `make ssh VM=client`
VM  ?=

PACKER_TEMPLATE := packer/vagrant-box.pkr.hcl
READINESS       := packer/readiness/qemu-readiness.pkr.hcl
BOXES           := $(basename $(basename $(notdir $(wildcard packer/vars/*.pkrvars.hcl))))
LAB_DIR         := labs/$(LAB)
VAGRANTFILES    := $(wildcard labs/*/Vagrantfile)
PLAYBOOKS       := $(wildcard labs/*/provision/site.yml)

.PHONY: all setup run remove fmt init validate readiness box box-add boxes list \
	up halt provision status ssh destroy clean help

all: help

## Repo
setup: ## Set up pre-commit hooks for this repo.
	pip3 install pre-commit
	pre-commit install
	pre-commit install-hooks
	pre-commit autoupdate

run: ## Run pre-commit checks manually
	pre-commit run --all-files

remove: ## Clean pre-commit tools from local system.
	pre-commit uninstall -t pre-commit -t pre-merge-commit -t pre-push -t prepare-commit-msg -t commit-msg -t post-commit -t post-checkout -t post-merge -t post-rewrite
	pip3 uninstall pre-commit -y

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
	@if command -v ansible-playbook >/dev/null; then \
		for p in $(PLAYBOOKS); do echo "==> ansible syntax $$p"; ansible-playbook --syntax-check -i localhost, "$$p" >/dev/null || exit 1; done; \
	else echo "==> ansible-playbook not found, skipping playbook syntax checks"; fi

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
