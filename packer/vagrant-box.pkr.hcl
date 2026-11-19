# vagrant-box.pkr.hcl
#
# Builds a vagrant-libvirt box from an upstream cloud image (no installer run).
# One template for every distro; the distro-specific bits live in vars/*.pkrvars.hcl.
#
# Usage (from the repo root; `make box BOX=<name>` wraps this):
#   packer init  packer/vagrant-box.pkr.hcl
#   packer build -var-file=packer/vars/rocky-8.10.pkrvars.hcl packer/vagrant-box.pkr.hcl
#   -> boxes/rocky-8.10-libvirt.box

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = ">= 1.1.0"
    }
  }
}

variable "name" {
  type        = string
  description = "Box short name, e.g. rocky-8.10. Output is boxes/<name>-libvirt.box, imported as local/<name>."
}

variable "image_url" {
  type        = string
  description = "URL of the distro's qcow2 cloud image."
}

variable "image_checksum" {
  type        = string
  description = "Checksum, or file:<url> pointing at the distro's checksum file."
}

variable "headless" {
  type    = bool
  default = true
}

variable "accelerator" {
  type        = string
  default     = "kvm"
  description = "kvm for hardware acceleration; tcg to test without KVM (slow, also set cpu_model)."
}

variable "cpu_model" {
  type        = string
  default     = "host"
  description = "QEMU -cpu model. EL10 needs x86-64-v3, which QEMU's default model lacks."
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "output_dir" {
  type        = string
  default     = ""
  description = "Override the build directory (default packer/output/<name>); Packer requires it not to exist."
}

locals {
  output_dir = var.output_dir != "" ? var.output_dir : "${path.root}/output/${var.name}"
}

source "qemu" "box" {
  iso_url      = var.image_url
  iso_checksum = var.image_checksum
  disk_image   = true

  accelerator    = var.accelerator
  cpu_model      = var.cpu_model
  cpus           = var.cpus
  memory         = var.memory
  disk_size      = var.disk_size
  format         = "qcow2"
  disk_interface = "virtio"
  net_device     = "virtio-net"
  headless       = var.headless

  # cloud-init NoCloud seed ISO
  cd_label = "cidata"
  cd_content = {
    "meta-data" = <<-EOF
      instance-id: packer-${var.name}
      local-hostname: ${var.name}
    EOF
    "user-data" = <<-EOF
      #cloud-config
      ssh_pwauth: true
      users:
        - name: vagrant
          shell: /bin/bash
          sudo: ALL=(ALL) NOPASSWD:ALL
          lock_passwd: false
          plain_text_passwd: vagrant
    EOF
  }

  communicator = "ssh"
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  ssh_timeout  = "15m"

  shutdown_command = "sudo shutdown -P now"

  output_directory = local.output_dir
  vm_name          = "${var.name}.qcow2"
}

build {
  name    = "vagrant-box"
  sources = ["source.qemu.box"]

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    inline = [
      "cloud-init status --wait || true",
      "grep PRETTY_NAME /etc/os-release",
    ]
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/network.sh",
      "${path.root}/scripts/python.sh",
      "${path.root}/scripts/cleanup.sh",
    ]
  }

  post-processor "vagrant" {
    provider_override = "libvirt"
    output            = "${path.root}/../boxes/${var.name}-libvirt.box"
  }
}
