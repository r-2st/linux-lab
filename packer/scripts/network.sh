#!/usr/bin/env bash
# Replace cloud-init's network config, which can pin the NIC to the build VM's
# MAC address, with plain DHCP on eth0, so every VM created from the box gets
# network. Other NICs are left to Vagrant.
set -euo pipefail

build_dev=$(ip -o route show default | awk '{print $5; exit}')
if [[ -z "$build_dev" ]]; then
  echo "network.sh: no default route, cannot find primary interface" >&2
  exit 1
fi
# shellcheck source=/dev/null
. /etc/os-release
major=${VERSION_ID%%.*}
echo "==> Primary interface during build: $build_dev"

# Predictable names (ens3, enp1s0, ...) follow the PCI slot, which differs
# between Packer's QEMU and vagrant-libvirt. Traditional names make the
# first NIC eth0 everywhere.
dev=eth0
if [[ "$build_dev" != "$dev" ]]; then
  echo "==> Switching to traditional NIC names (net.ifnames=0)"
  args="net.ifnames=0 biosdevname=0"
  if command -v grubby >/dev/null; then
    grubby --update-kernel=ALL --args="$args"
  fi
  if command -v update-grub >/dev/null; then
    mkdir -p /etc/default/grub.d
    echo "GRUB_CMDLINE_LINUX=\"\$GRUB_CMDLINE_LINUX $args\"" >/etc/default/grub.d/99-net-ifnames.cfg
    update-grub
  elif [[ -f /etc/default/grub ]] && ! grep -q 'net.ifnames=0' /etc/default/grub; then
    sed -i "s/^GRUB_CMDLINE_LINUX=\"/&$args /" /etc/default/grub
  fi
fi

if command -v netplan >/dev/null; then
  # Ubuntu, and Debian releases that ship netplan
  echo "==> Writing netplan config"
  rm -f /etc/netplan/50-cloud-init.yaml
  cat >/etc/netplan/01-primary.yaml <<EOF
network:
  version: 2
  ethernets:
    ${dev}:
      dhcp4: true
EOF
  chmod 600 /etc/netplan/01-primary.yaml

elif command -v nmcli >/dev/null; then
  # EL: NetworkManager, with ifcfg files on EL8 and keyfiles on EL9+
  rm -f /etc/sysconfig/network-scripts/ifcfg-eth* /etc/sysconfig/network-scripts/ifcfg-en*
  rm -f /etc/NetworkManager/system-connections/*
  if [[ "$major" -le 8 ]]; then
    echo "==> Writing ifcfg-${dev}"
    printf 'DEVICE=%s\nNAME=%s\nTYPE=Ethernet\nBOOTPROTO=dhcp\nONBOOT=yes\n' "$dev" "$dev" \
      >"/etc/sysconfig/network-scripts/ifcfg-${dev}"
  else
    echo "==> Writing NetworkManager keyfile for ${dev}"
    cat >"/etc/NetworkManager/system-connections/${dev}.nmconnection" <<EOF
[connection]
id=${dev}
type=ethernet
interface-name=${dev}
autoconnect=true

[ipv4]
method=auto

[ipv6]
method=auto
EOF
    chmod 600 "/etc/NetworkManager/system-connections/${dev}.nmconnection"
  fi

elif [[ -f /etc/network/interfaces ]]; then
  # Debian with ifupdown
  echo "==> Writing ifupdown config"
  rm -f /etc/network/interfaces.d/50-cloud-init*
  printf 'auto %s\nallow-hotplug %s\niface %s inet dhcp\n' "$dev" "$dev" "$dev" \
    >"/etc/network/interfaces.d/60-primary"

else
  echo "network.sh: unknown network stack" >&2
  exit 1
fi

# Keep cloud-init from rewriting the config above on later boots.
mkdir -p /etc/cloud/cloud.cfg.d
echo 'network: {config: disabled}' >/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
