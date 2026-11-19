# ===================================================================================
# linux-lab Makefile
#
# DESCRIPTION: Set up the repo, run pre-commit, build Vagrant boxes with Packer, and
#              drive Vagrant labs. Each lab lives in its own directory (LAB=<dir>).
#
# AUTHOR: Ross Thompson <ross.thompson@thetradedesk.com>, Copilot
#
# ===================================================================================

CYAN   := $(shell tput -Txterm setaf 6)
GREEN  := $(shell tput -Txterm setaf 2)
RESET  := $(shell tput -Txterm sgr0)
WHITE  := $(shell tput -Txterm setaf 7)
YELLOW := $(shell tput -Txterm setaf 3)

# Lab directory to operate on, e.g. `make up LAB=cert-lab`
LAB      ?= cert-lab
# Packer template inside $(LAB), e.g. `make build TEMPLATE=rocky8-vagrant-box.pkr.hcl`
TEMPLATE ?=
# Box produced by Packer and the name Vagrantfiles refer to it by
BOX_FILE ?= rocky-8.10-libvirt.box
BOX_NAME ?= local/rocky-8.10
# Optional single machine for vagrant targets, e.g. `make ssh VM=client`
VM       ?=

PACKER_TEMPLATES := $(shell find . -name '*.pkr.hcl' -not -path './.git/*' 2>/dev/null)

.PHONY: all setup run remove fmt validate init build box-add box-list \
	up halt destroy status ssh provision clean help

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
fmt: ## Format all Packer templates in the repo.
	packer fmt -recursive .

init: ## Install Packer plugins for every template in the repo.
	@for t in $(PACKER_TEMPLATES); do echo "==> packer init $$t"; packer init "$$t" || exit 1; done

validate: init ## Validate every Packer template and Vagrantfile in the repo.
	@for t in $(PACKER_TEMPLATES); do echo "==> packer validate $$t"; packer validate "$$t" || exit 1; done
	@for v in $$(find . -name Vagrantfile -not -path '*/.vagrant/*'); do echo "==> ruby -c $$v"; ruby -c "$$v" >/dev/null || exit 1; done

build: ## Build a Packer template: LAB=<dir> TEMPLATE=<file.pkr.hcl>
	@test -n "$(TEMPLATE)" || { echo "TEMPLATE is required, e.g. make build TEMPLATE=rocky8-vagrant-box.pkr.hcl"; exit 1; }
	cd $(LAB) && packer init $(TEMPLATE) && packer build $(TEMPLATE)

box-add: ## Import a built box into Vagrant: LAB=<dir> BOX_FILE=<file> BOX_NAME=<name>
	vagrant box add --force --name $(BOX_NAME) $(LAB)/$(BOX_FILE)

box-list: ## List boxes known to Vagrant.
	vagrant box list

## Vagrant
up: ## Start the lab (or one machine with VM=<name>).
	cd $(LAB) && vagrant up $(VM)

halt: ## Shut down the lab (or VM=<name>).
	cd $(LAB) && vagrant halt $(VM)

provision: ## Re-run provisioners (or VM=<name>).
	cd $(LAB) && vagrant provision $(VM)

status: ## Show lab machine status.
	cd $(LAB) && vagrant status

ssh: ## SSH into a lab machine: VM=<name>
	@test -n "$(VM)" || { echo "VM is required, e.g. make ssh VM=client"; exit 1; }
	cd $(LAB) && vagrant ssh $(VM)

destroy: ## Destroy the lab VMs (or VM=<name>).
	cd $(LAB) && vagrant destroy -f $(VM)

clean: ## Remove Packer output dirs, caches, and manifests from LAB (keeps .box files).
	cd $(LAB) && rm -rf output-*/ packer_cache/ *-manifest.json crash.log

## Help:
help: ## Show this help.
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET} [LAB=<dir>] [TEMPLATE=<file>] [VM=<name>]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) {printf "    ${YELLOW}%-20s${GREEN}%s${RESET}\n", $$1, $$2} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)
