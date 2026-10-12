#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

if [[ ! -f inventory.ini ]]; then
    printf '%s\n' "Создайте inventory.ini по примеру inventory.ini.example" >&2
    exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    printf '%s\n' "Ansible не найден. Установите ansible-core и повторите запуск." >&2
    exit 1
fi

exec ansible-playbook site.yml "$@"
