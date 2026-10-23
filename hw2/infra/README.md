# ДЗ2 — YARN и MapReduce

## Схема

| Узел из inventory ДЗ1 | Добавляемые сервисы |
| --- | --- |
| edge | Ansible и SSH-туннели |
| nn (`namenode`) | ResourceManager, NodeManager, JobHistoryServer |
| nn, dn0, dn1 (`datanodes`) | По одному NodeManager |

## Запуск с внешнего устройства

На локальном устройстве нужны Ansible, Python 3 и SSH. Доступ по SSH и `sudo` на VM должен быть настроен, как для ДЗ1.

Из корня репозитория в ветке `hw2`:

```bash
cd hw2/infra
./deploy.sh
```

Скрипт сначала выполнит `hw1/infra/deploy.sh`, затем скопирует плейбуки ДЗ1 и ДЗ2, внутренний inventory и общие переменные ДЗ1 в `/home/team/yarn-ansible`, затем выполнит внутренний деплой с edge. Путь меняется через `yarn_edge_project_dir`. Сам этап ДЗ2 пакеты не устанавливает. Для запуска только ДЗ2 используйте `./deploy.sh --skip-hw1`.

## Запуск с edge

Клонируйте ветку `hw2` на edge и заполните внутренний inventory:

```bash
git clone -b hw2 https://github.com/xarujl/data-platforms.git
cd data-platforms
cp hw1/infra/edge/inventory.ini.example hw1/infra/edge/inventory.ini
```
Заполните внутренние IP и путь к существующему SSH-ключу на edge.

Из корня репозитория:

```bash
cd hw2/infra/edge
./deploy.sh
```

После копирования с локального устройства:

```bash
cd /home/team/yarn-ansible/hw2/infra/edge
./deploy.sh
```

## Исправление привязки имени к loopback

На текущих VM имя узла одновременно записано в `/etc/hosts` с внутренним IP и с `127.0.1.1`. Из-за повторного разрешения имени ResourceManager и JobHistoryServer могут слушать loopback даже при указании внутреннего IP в XML.

Перед запуском сервисов плейбук получает короткое имя каждой VM и заменяет адрес в строке `127.0.1.1`, содержащей только это имя и его FQDN-варианты, на `ansible_host` из inventory ДЗ1. Имена, комментарии и остальные записи сохраняются; `127.0.0.1 localhost` не меняется. Например:

```text
# До
127.0.1.1 team-35-nn.hse.c.mws team-35-nn
# После
10.35.0.11 team-35-nn.hse.c.mws team-35-nn
```

Перед изменением создаётся резервная копия `/etc/hosts`. Чтобы применить исправление после неудачного запуска, повторите `hw2/infra/deploy.sh` с локального устройства: он доставит обновлённые плейбуки на edge и перезапустит затронутые демоны YARN/MapReduce.

## Веб-интерфейсы

На локальном устройстве из `hw2/infra` запустите:

```bash
./web-ui.sh
```

Скрипт возьмёт адреса из inventory ДЗ1 и откроет туннели из [шага 10 ручной инструкции](../manual-installation.md#шаг-10-открыть-веб-интерфейсы-через-ssh-туннель). Пока открыто SSH-соединение, доступны:

| Интерфейс | URL |
| --- | --- |
| ResourceManager | `http://localhost:8088` |
| JobHistoryServer | `http://localhost:19888` |
| NodeManager nn | `http://localhost:18042` |
| NodeManager dn0 | `http://localhost:18043` |
| NodeManager dn1 | `http://localhost:18044` |
