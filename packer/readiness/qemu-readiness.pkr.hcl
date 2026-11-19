# qemu-readiness.pkr.hcl
#
# Smoke test for a local Packer + QEMU/KVM setup.
# Boots the official Ubuntu 24.04 cloud image (no OS install needed),
# seeds it with cloud-init via a generated ISO (exercises xorriso/mkisofs),
# connects over SSH, runs a few checks, and shuts down cleanly.
#
# Usage (from the repo root; `make readiness` wraps this):
#   packer init  packer/readiness/qemu-readiness.pkr.hcl
#   packer build packer/readiness/qemu-readiness.pkr.hcl
#
# Expected runtime with KVM: ~2-4 minutes (mostly the image download).

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "headless" {
  type        = bool
  default     = true
  description = "Set to false to watch the VM boot in a GTK window."
}

variable "accelerator" {
  type        = string
  default     = "kvm"
  description = "kvm for hardware acceleration; tcg to test without KVM (slow)."
}

variable "ssh_password" {
  type      = string
  default   = "packer"
  sensitive = true
}

locals {
  build_ts = formatdate("YYYYMMDD-hhmmss", timestamp())
}

source "qemu" "readiness" {
  # --- Base image: Ubuntu 24.04 (Noble) cloud image, qcow2 format ---
  iso_url      = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  iso_checksum = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"
  disk_image   = true # treat iso_url as a bootable disk, not an installer ISO

  # --- VM hardware ---
  accelerator    = var.accelerator
  cpus           = 2
  memory         = 2048
  disk_size      = "10G"
  format         = "qcow2"
  disk_interface = "virtio"
  net_device     = "virtio-net"
  headless       = var.headless

  # --- cloud-init seed ISO (NoCloud datasource needs the label "cidata") ---
  cd_label = "cidata"
  cd_content = {
    "meta-data" = <<-EOF
      instance-id: packer-readiness
      local-hostname: packer-readiness
    EOF
    "user-data" = <<-EOF
      #cloud-config
      ssh_pwauth: true
      chpasswd:
        expire: false
        users:
          - name: ubuntu
            password: ${var.ssh_password}
            type: text
    EOF
  }

  # --- Communicator ---
  communicator = "ssh"
  ssh_username = "ubuntu"
  ssh_password = var.ssh_password
  ssh_timeout  = "10m"

  shutdown_command = "sudo shutdown -P now"

  # --- Output ---
  output_directory = "${path.root}/../output/readiness-${local.build_ts}"
  vm_name          = "readiness.qcow2"
}

build {
  name    = "qemu-readiness"
  sources = ["source.qemu.readiness"]

  provisioner "shell" {
    inline = [
      "echo '==> Waiting for cloud-init to finish'",
      "cloud-init status --wait || true",
      "echo '==> Guest info'",
      "uname -a",
      "cat /etc/os-release | head -n 2",
      "echo '==> CPU / memory / disk'",
      "nproc",
      "free -h",
      "df -h /",
      "echo '==> Virtualization as seen by the guest'",
      "systemd-detect-virt || true",
      "echo '==> Network check'",
      "ip -brief addr",
      "echo 'Packer QEMU readiness test passed' | sudo tee /etc/packer-readiness",
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/../output/readiness-manifest.json"
    strip_path = true
  }
}
