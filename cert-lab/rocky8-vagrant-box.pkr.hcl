# rocky8-vagrant-box.pkr.hcl
#
# Builds a Rocky Linux 8.10 Vagrant box for the vagrant-libvirt provider,
# starting from the official GenericCloud-Base qcow2 image (no installer run).
#
# Usage:
#   packer init  rocky8-vagrant-box.pkr.hcl
#   packer build rocky8-vagrant-box.pkr.hcl
#   -> produces rocky-8.10-libvirt.box in the current directory

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

variable "headless" {
  type    = bool
  default = true
}

variable "rocky_mirror" {
  type        = string
  default     = "https://dl.rockylinux.org/pub/rocky"
  description = "Base URL; switch to https://dl.rockylinux.org/vault/rocky if 8.10 is moved to the vault."
}

locals {
  # Pinned 8.10 build rather than the ".latest" pointer, so rebuilds are reproducible.
  image_name = "Rocky-8-GenericCloud-Base-8.10-20240528.0.x86_64.qcow2"
  image_dir  = "${var.rocky_mirror}/8.10/images/x86_64"
}

source "qemu" "rocky8" {
  iso_url      = "${local.image_dir}/${local.image_name}"
  iso_checksum = "file:${local.image_dir}/${local.image_name}.CHECKSUM"
  disk_image   = true

  accelerator    = "kvm"
  cpus           = 2
  memory         = 2048
  disk_size      = "20G"
  format         = "qcow2"
  disk_interface = "virtio"
  net_device     = "virtio-net"
  headless       = var.headless

  # cloud-init NoCloud seed ISO
  cd_label = "cidata"
  cd_content = {
    "meta-data" = <<-EOF
      instance-id: packer-rocky8-box
      local-hostname: rocky8-vagrant
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

  output_directory = "output-rocky8-box"
  vm_name          = "rocky8.qcow2"
}

build {
  sources = ["source.qemu.rocky8"]

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    inline = [
      "cloud-init status --wait || true",
      "cat /etc/rocky-release",

      # cloud-init's ifcfg file can pin eth0 to the build VM's MAC address.
      # Replace it with a plain DHCP config so new Vagrant VMs get network.
      "rm -f /etc/sysconfig/network-scripts/ifcfg-eth*",
      "printf 'DEVICE=eth0\\nNAME=eth0\\nTYPE=Ethernet\\nBOOTPROTO=dhcp\\nONBOOT=yes\\n' > /etc/sysconfig/network-scripts/ifcfg-eth0",
      "rm -f /etc/NetworkManager/system-connections/*",

      # Keep cloud-init from re-running (and stalling boot) without its seed ISO.
      "touch /etc/cloud/cloud-init.disabled",

      # Unique machine-id / DHCP lease per VM created from the box.
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",

      # Trim the image.
      "dnf -y clean all",
      "rm -rf /var/cache/dnf/*",
      "fstrim -av || true",
    ]
  }

  post-processor "vagrant" {
    provider_override = "libvirt"
    output            = "rocky-8.10-libvirt.box"
  }
}
