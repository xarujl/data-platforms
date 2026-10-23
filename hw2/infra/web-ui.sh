#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

for executable in ansible-inventory python3 ssh; do
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

edge_vars=$(ansible-inventory --playbook-dir edge --host edge-node)
cluster_vars=$(ansible-inventory --playbook-dir edge -i ../../hw1/infra/edge/inventory.ini --list)

python3 - "$edge_vars" "$cluster_vars" <<'PY'
import json
import os
import sys

edge = json.loads(sys.argv[1])
cluster = json.loads(sys.argv[2])
hosts = cluster["_meta"]["hostvars"]
namenode = cluster["namenode"]["hosts"][0]
workers = [namenode] + [host for host in cluster["datanodes"]["hosts"] if host != namenode]
nn_ip = hosts[namenode]["ansible_host"]
forwards = [
    (8088, nn_ip, edge["yarn_resourcemanager_web_port"], "ResourceManager"),
    (19888, nn_ip, edge["mapred_history_web_port"], "JobHistoryServer"),
]
for index, host in enumerate(workers):
    forwards.append((18042 + index, hosts[host]["ansible_host"], edge["yarn_nodemanager_web_port"], f"NodeManager {host}"))

command = ["ssh", "-N", "-o", "ExitOnForwardFailure=yes", "-o", "StrictHostKeyChecking=accept-new"]
if edge.get("ansible_ssh_private_key_file"):
    command += ["-i", os.path.expanduser(edge["ansible_ssh_private_key_file"])]
command += ["-p", str(edge.get("ansible_port", 22))]
for local_port, host, remote_port, label in forwards:
    command += ["-L", f"127.0.0.1:{local_port}:{host}:{remote_port}"]
    print(f"{label}: http://localhost:{local_port}", flush=True)
command += [f"{edge.get('ansible_user', 'team')}@{edge['ansible_host']}"]
print("Открываю SSH-туннель. Для остановки нажмите Ctrl+C.", flush=True)
os.execvp(command[0], command)
PY
