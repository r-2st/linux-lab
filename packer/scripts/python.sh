#!/usr/bin/env bash
# Make the box manageable by current Ansible, which needs Python >= 3.9 on the
# target. EL8 only ships 3.6 (platform-python), so add 3.12 as python3.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/os-release
if [[ "${ID_LIKE:-} $ID" == *rhel* && "${VERSION_ID%%.*}" == 8 ]]; then
  echo "==> EL8: installing python3.12 as /usr/bin/python3"
  dnf -y install python3.12
  alternatives --set python3 /usr/bin/python3.12
fi

python3 --version
