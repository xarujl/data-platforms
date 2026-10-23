#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

skip_hw1=false
case "${1:-}" in
    "") ;;
    --skip-hw1) skip_hw1=true; shift ;;
    *) echo "Использование: $0 [--skip-hw1]" >&2; exit 1 ;;
esac
if (( $# != 0 )); then
    echo "Использование: $0 [--skip-hw1]" >&2
    exit 1
fi

for executable in ansible-inventory ansible-playbook python3 ssh; do
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "Для запуска нужен $executable" >&2
        exit 1
    fi
done

for inventory in ../../hw1/infra/control-inventory.ini ../../hw1/infra/edge/inventory.ini; do
    if [[ ! -f "$inventory" ]]; then
        echo "Создайте $inventory по примеру $inventory.example из ДЗ1" >&2
        exit 1
    fi
done

if [[ "$skip_hw1" == false ]]; then
    ../../hw1/infra/deploy.sh
fi

edge_vars=$(ansible-inventory --playbook-dir edge --host edge-node)
ansible-playbook edge-deploy.yml

# Как в ДЗ1, внутренний плейбук выполняется на edge с его SSH-ключом.
python3 - "$edge_vars" <<'PY'
import json
import os
import shlex
import sys

edge = json.loads(sys.argv[1])
command = ["ssh", "-o", "StrictHostKeyChecking=accept-new"]
if edge.get("ansible_ssh_private_key_file"):
    command += ["-i", os.path.expanduser(edge["ansible_ssh_private_key_file"])]
command += [
    "-p", str(edge.get("ansible_port", 22)),
    f"{edge.get('ansible_user', 'team')}@{edge['ansible_host']}",
    f"cd {shlex.quote(edge['yarn_edge_project_dir'] + '/hw2/infra/edge')} && exec ./deploy.sh --skip-hw1",
]
os.execvp(command[0], command)
PY
