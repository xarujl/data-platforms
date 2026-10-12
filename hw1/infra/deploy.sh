#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

for inventory in control-inventory.ini edge/inventory.ini; do
    if [[ ! -f "$inventory" ]]; then
        echo "Создайте $inventory по примеру $inventory.example" >&2
        exit 1
    fi
done

edge_vars=$(ansible-inventory --playbook-dir edge --host edge-node)
ansible-playbook edge-deploy.yml

# вот эта штука написана гпт для того чтобы ansible передавал процесс плейбуков с edge ноды
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
    f"cd {shlex.quote(edge['edge_project_dir'])} && exec ./deploy.sh",
]
os.execvp(command[0], command)
PY
