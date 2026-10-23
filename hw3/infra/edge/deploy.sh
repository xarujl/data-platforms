#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

skip_previous=false
case "${1:-}" in
    "") ;;
    --skip-previous) skip_previous=true; shift ;;
    *) echo "Использование: $0 [--skip-previous]" >&2; exit 1 ;;
esac
if (( $# != 0 )); then
    echo "Использование: $0 [--skip-previous]" >&2
    exit 1
fi

if [[ ! -f ../../../hw1/infra/edge/inventory.ini ]]; then
    echo "Создайте hw1/infra/edge/inventory.ini по примеру из ДЗ1" >&2
    exit 1
fi

if [[ "$skip_previous" == false ]]; then
    ../../../hw2/infra/edge/deploy.sh
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "На edge нужен Ansible, установленный при выполнении ДЗ1" >&2
    exit 1
fi

exec ansible-playbook site.yml
