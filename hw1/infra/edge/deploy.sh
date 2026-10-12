#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

if [[ ! -f inventory.ini ]]; then
    echo "Создайте inventory.ini по примеру inventory.ini.example" >&2
    exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y ansible-core ca-certificates
fi

exec ansible-playbook site.yml
