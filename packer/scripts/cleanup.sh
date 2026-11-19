#!/usr/bin/env bash
# Generalize and shrink the image before it is packaged as a box.
set -euo pipefail

# Keep cloud-init from re-running (and stalling boot) without its seed ISO.
touch /etc/cloud/cloud-init.disabled

# Unique machine-id (and so DHCP client ID) per VM created from the box.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

if command -v dnf >/dev/null; then
  dnf -y clean all
  rm -rf /var/cache/dnf/*
elif command -v apt-get >/dev/null; then
  apt-get -y autoremove --purge
  apt-get -y clean
fi

rm -f /root/.bash_history /home/vagrant/.bash_history
rm -rf /tmp/* /var/tmp/*

fstrim -av || true
