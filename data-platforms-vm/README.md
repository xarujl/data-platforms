# Имитация инфраструктуры серверов на Docker Compose

## Быстрый старт

Генерируем SSH-ключи 

| Ключ | Где хранится приватная часть | Для чего |
|---|---|---|
| `host_edge` | На компьютере | Компьютер → edge |
| `team_internal` | На компьютере при подготовке проекта; монтируется в edge | Edge → внутренние узлы |

```
mkdir -p docker ssh
ssh-keygen -t ed25519 -f ssh/host_edge -N ""
ssh-keygen -t ed25519 -f ssh/team_internal -N ""
```

## Команды запуска и управления

Все команды `docker compose ...` запускать **с компьютера, из корня проекта**, где находится `compose.yaml`.

```bash
# Сборка и запуск
docker compose up -d --build

# Состояние контейнеров
docker compose ps

# Список процессов внутри контейнера
docker compose top

# Прямой вход в контейнер без SSH (полезно для диагностики)
docker compose exec edge bash
docker compose exec namenode bash

# Выполнить одну команду от пользователя team
docker compose exec -u team namenode hostname

# Остановить / запустить существующие контейнеры
docker compose stop
docker compose start

# Перезапустить без пересоздания
docker compose restart

# Удалить контейнеры и сеть проекта
docker compose down
```

### SSH подключение

```bash
# На вашем компьютере, из корня проекта в edge:
ssh -i ssh/host_edge -p 2222 team@127.0.0.1

# На edge в другие узлы:
ssh -i ~/.ssh/team_internal team@team-35-nn
ssh -i ~/.ssh/team_internal team@team-35-00
ssh -i ~/.ssh/team_internal team@team-35-01
```

## Оригинальная инфраструктура

Четыре Linux-сервера. Доступ извне есть только к **edge**. Остальные узлы находятся во внутренней сети.

```text
Ваш компьютер
    |
    | SSH с внешним ключом
    v
edge / team-35-en
публичный адрес: 2.59.80.26
внутренний IP: 10.35.0.10
    |
    | SSH с ключом ~/.ssh/team_internal, хранящимся на edge
    +---- team-35-nn  10.35.0.11  (NameNode)
    +---- team-35-00  10.35.0.12  (DataNode 0)
    +---- team-35-01  10.35.0.13  (DataNode 1)
```

| Узел | Hostname | Внутренний IP | Предполагаемое назначение |
|---|---|---|---|
| Edge | `team-35-en` | `10.35.0.10` | Точка входа, Hadoop-клиент |
| NameNode | `team-35-nn` | `10.35.0.11` | Метаданные HDFS |
| DataNode 0 | `team-35-00` | `10.35.0.12` | Хранение блоков HDFS |
| DataNode 1 | `team-35-01` | `10.35.0.13` | Хранение блоков HDFS |

Подключение к оригинальной среде:

```bash
ssh -i ~/.ssh/<ваш_ключ> team@2.59.80.26
# Уже на edge:
ssh -i ~/.ssh/team_internal team@team-35-nn
```

На всех серверах Пользователь `team` с `sudo` без пароля (sudo -i).

## Локальная реализация Docker

Docker Compose создаёт **четыре контейнера Ubuntu 24.04** с OpenSSH, пользователем `team`, Python 3 и sudo, объединённые в сеть `hadoop_net`.

```text
Ваш компьютер
    |
    | ssh -i ssh/host_edge -p 2222 team@127.0.0.1
    v
Docker host: 127.0.0.1:2222 -> edge:22
    |
    +---- edge       team-35-en  10.35.0.10
              |
              | ~/.ssh/team_internal
              +---- namenode  team-35-nn  10.35.0.11
              +---- datanode0 team-35-00  10.35.0.12
              +---- datanode1 team-35-01  10.35.0.13

              Docker bridge-сеть: 10.35.0.0/24
```

В Compose опубликован **только SSH-порт edge** на `127.0.0.1:2222`. SSH остальных контейнеров не публикуется на хост. Внутри сети имена `team-35-nn`, `team-35-00`, `team-35-01` работают благодаря Docker network aliases.

### Cтруктура проекта

```text
hadoop-lab/
├── compose.yaml
├── docker/
│   ├── Dockerfile         # создаёт пользователя и ставит OpenSSH
│   └── entrypoint.sh      # загружает нужные SSH-ключи из bind mounts, создаёт host keys SSH и запускает `sshd` как основной процесс
├── ssh/
│   ├── host_edge
│   ├── host_edge.pub
│   ├── team_internal
│   └── team_internal.pub
├── downloads/             # опционально: например hadoop-3.4.0.tar.gz
└── manual-docs/           # инструкции
```

- `Dockerfile` создаёт пользователя и ставит OpenSSH
- `entrypoint.sh` загружает нужные SSH-ключи из bind mounts, создаёт host keys SSH и запускает `sshd` как основной процесс

### SSH-ключи

| Ключ | Где хранится приватная часть | Для чего |
|---|---|---|
| `host_edge` | На компьютере | Компьютер → edge |
| `team_internal` | На компьютере при подготовке проекта; монтируется в edge | Edge → внутренние узлы |

На внутренних узлах `team_internal.pub` используется как `authorized_keys`, а на edge — `host_edge.pub`. Это локальные учебные ключи.


### Перенос файлов

В compose к edge ноде смонтирован volume ./downloads:~/downloads:ro для удобства.

Например, внутри контейнера долго скачивается hadoop-3.4.0.tar.gz. Можно скачать на ваш компьютер сюда, в папку downloads

```bash
# Скопировать локальный архив в контейнер NameNode (на компьютере):
docker compose cp ~/Downloads/hadoop-3.4.0.tar.gz namenode:~/

# Либо через SSH с компьютера на edge:
scp -i ssh/host_edge -P 2222 ~/Downloads/hadoop-3.4.0.tar.gz team@127.0.0.1:~/

# Уже на edge — передать архив на внутренний узел:
scp -i ~/.ssh/team_internal /tmp/hadoop-3.4.0.tar.gz team@team-35-nn:~/
```


## Перезагрузка или очистка

### Вариант A: сохранить текущее состояние

```bash
docker compose stop
docker compose start
```

Пакеты и файлы, созданные внутри **существующих** контейнеров, сохранятся.

### Вариант B: вернуть чистую версию

```bash
# На компьютере, из корня проекта
docker compose down
docker compose up -d --build
```

Это удалит текущие контейнеры и создаст новые из Dockerfile.
