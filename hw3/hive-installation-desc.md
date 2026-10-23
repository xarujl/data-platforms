# Автоматизированное развертывание Apache Hive поверх HDFS и YARN

## 0. Исходное состояние и целевая архитектура

HDFS и YARN запущены. Hadoop 3.4.0 установлен в `/opt/hadoop-3.4.0`; демоны работают от `hdfs` (группа `hadoop`).

| Узел | Приватный IP | Уже работающие службы | Добавляемые службы |
|---|---|---|---|
| Edge `team-35-en` | `10.35.0.10` | Доступ и управление кластером | — |
| NameNode `team-35-nn` | `10.35.0.11` | NameNode, DataNode, ResourceManager, NodeManager, JobHistoryServer | PostgreSQL, Hive Metastore, HiveServer2 |
| `team-35-00` | `10.35.0.12` | SecondaryNameNode, DataNode, NodeManager | — |
| `team-35-01` | `10.35.0.13` | DataNode, NodeManager | — |

Hive 4.0.1: хранение данных - HDFS, выполнение запросов - MapReduce/YARN.

| Компонент | Адрес на `team-35-nn` |
|---|---|
| PostgreSQL | `127.0.0.1:5432` |
| Hive Metastore | `thrift://127.0.0.1:9083` |
| HiveServer2 JDBC | `jdbc:hive2://127.0.0.1:10000` |
| HiveServer2 web UI | `http://10.35.0.11:10002` |

HiveServer2 обслуживает JDBC-клиентов через отдельный Metastore (Thrift). Метаданные хранятся в PostgreSQL; Derby не используется.

Развертывание запускается от `team` через `sudo`, команды Hive от `hdfs`. HDFS и YARN не переустанавливаются.

Требуется Ubuntu 24.04 amd64 с `apt`, `systemd` и репозиторием, содержащим `openjdk-8-jdk-headless`. Пути Java 8/11 должны совпадать со скриптом; Java 11 и `/opt/hadoop-3.4.0/etc/hadoop` необходимы на всех NodeManager. Повторное развертывание сохраняет пароль, БД и схему. Для перезапуска без развертывания см. шаг 6.

---

## Шаг 1. Подключиться к NameNode

С локального компьютера подключитесь к edge, затем к NameNode:

```bash
ssh team@2.59.80.26
ssh -i ~/.ssh/team_internal team@team-35-nn
```

---

## Шаг 2. Автоматически развернуть Hive

**Сохраните код блоков 2.1–2.8 по порядку в один файл** `deploy.sh`**, без заголовков и пояснений.** Запустите его по шагу 2.9. Отдельно блоки не выполняйте: они используют общие переменные. XML и пароль PostgreSQL настраиваются автоматически. 

### 2.1. Задать пути установки

Задаются пути установки. `set -euo pipefail` завершает скрипт при ошибке. 

```bash
#!/usr/bin/env bash
set -euo pipefail

# Запускать на team-35-nn: sudo bash deploy.sh
HADOOP=/opt/hadoop-3.4.0
HIVE=/opt/apache-hive-4.0.1-bin
BASE=/var/lib/hadoop/hive
JAVA11=/usr/lib/jvm/java-11-openjdk-amd64
cd /
```

### 2.2. Установить зависимости и запустить PostgreSQL

Устанавливаются Java 8, PostgreSQL и JDBC-драйвер; запускается PostgreSQL. 

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    openjdk-8-jdk-headless postgresql postgresql-client \
    libpostgresql-jdbc-java wget python3 ca-certificates
systemctl enable --now postgresql

```

### 2.3. Скачать и распаковать Hive

Hive 4.0.1 скачивается при отсутствии. Перед обновлением конфигураций останавливаются systemd-службы; устанавливается JDBC-драйвер и создаются каталоги. При переходе с `nohup` сначала завершите старые процессы по предыдущей инструкции.

```bash
for service in hive-hiveserver2 hive-metastore; do
    if [[ -f "/etc/systemd/system/$service.service" ]]; then
        systemctl stop "$service"
    fi
done
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"
archive=apache-hive-4.0.1-bin.tar.gz
url=https://archive.apache.org/dist/hive/hive-4.0.1
if [[ ! -x "$HIVE/bin/hive" ]]; then
    wget -q "$url/$archive"
    tar -xzf "$archive" -C /opt
fi
chown -R hdfs:hadoop "$HIVE"
install -m 0644 /usr/share/java/postgresql.jar "$HIVE/lib/postgresql.jar"
install -d -o hdfs -g hadoop -m 0750 \
    "$BASE" "$BASE/data" "$BASE/logs" "$BASE/tmp" "$BASE/hadoop-conf"
cd /
```

### 2.4. Создать окружение Hive и настройки MapReduce

Копируются конфигурации Hadoop и создается окружение Hive. Процессы Hive используют Java 8, контейнеры MapReduce - Java 11. 

```bash
for name in core-site hdfs-site yarn-site mapred-site; do
    install -o hdfs -g hadoop -m 0640 "$HADOOP/etc/hadoop/$name.xml" "$BASE/hadoop-conf/"
done
cat > "$BASE/hadoop-conf/hadoop-env.sh" <<'HADOOP_ENV'
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=/opt/hadoop-3.4.0
export HADOOP_CONF_DIR=/var/lib/hadoop/hive/hadoop-conf
HADOOP_ENV
cat > "$BASE/env.sh" <<'HIVE_ENV'
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=/opt/hadoop-3.4.0
export HADOOP_CONF_DIR=/var/lib/hadoop/hive/hadoop-conf
export HIVE_HOME=/opt/apache-hive-4.0.1-bin
export HIVE_CONF_DIR=$HIVE_HOME/conf
export HIVE_LOG_DIR=/var/lib/hadoop/hive/logs
export HIVESERVER2_PID_DIR=/var/lib/hadoop/hive
export HADOOP_LOG_DIR=/var/lib/hadoop/hive/logs
export HADOOP_CLIENT_OPTS=-Djava.io.tmpdir=/var/lib/hadoop/hive/tmp
export HADOOP_HEAPSIZE_MAX=${HADOOP_HEAPSIZE_MAX:-256}
export PATH=$JAVA_HOME/bin:$HIVE_HOME/bin:$HADOOP_HOME/bin:$PATH
HIVE_ENV

# Добавляем свойства в копию XML, без nano и дубликатов свойств.
python3 - <<'MAPRED_PY'
from pathlib import Path
import xml.etree.ElementTree as ET
p = Path('/var/lib/hadoop/hive/hadoop-conf/mapred-site.xml')
tree = ET.parse(p)
root = tree.getroot()
keys = ('yarn.app.mapreduce.am.env', 'mapreduce.map.env', 'mapreduce.reduce.env')
for prop in list(root.findall('property')):
    if prop.findtext('name') in keys:
        root.remove(prop)
for key in keys:
    prop = ET.SubElement(root, 'property')
    ET.SubElement(prop, 'name').text = key
    ET.SubElement(prop, 'value').text = (
        'JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64,'
        'HADOOP_CONF_DIR=/opt/hadoop-3.4.0/etc/hadoop')
tree.write(p, encoding='UTF-8', xml_declaration=True)
MAPRED_PY
```

### 2.5. Создать базу метаданных

Пароль сохраняется в `$BASE/postgres-password` с правами `0600`. При повторном развертывании он берется из файла, при переходе со старой версии - из `hive-site.xml`. Роль и БД `hive_metastore` создаются только при отсутствии; существующие пароль и данные сохраняются.

```bash
password_file="$BASE/postgres-password"
if [[ -s "$password_file" ]]; then
    password=$(cat "$password_file")
elif [[ -f "$HIVE/conf/hive-site.xml" ]]; then
    password=$(python3 - "$HIVE/conf/hive-site.xml" <<'READ_PASSWORD'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
password = next((p.findtext('value') for p in root.findall('property')
                 if p.findtext('name') == 'javax.jdo.option.ConnectionPassword'), None)
if not password or password == 'POSTGRES_PASSWORD':
    raise SystemExit('В существующем hive-site.xml нет сохраненного пароля PostgreSQL.')
print(password)
READ_PASSWORD
    )
else
    role_exists=$(runuser -u postgres -- psql -X -At -v ON_ERROR_STOP=1 -d postgres \
        -c "SELECT EXISTS (SELECT FROM pg_roles WHERE rolname='hive_metastore');")
    if [[ "$role_exists" == t ]]; then
        echo 'Роль hive_metastore существует, но ее пароль не найден. Восстановите postgres-password; пароль роли не изменен.' >&2
        exit 1
    fi
    password=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
fi
install -o root -g root -m 0600 /dev/null "$password_file"
printf '%s' "$password" > "$password_file"
# Экранируем одинарные кавычки на случай пароля из старого XML.
sql_password=${password//\'/\'\'}
runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -d postgres <<SQL
SET standard_conforming_strings = on;
SELECT format('CREATE ROLE hive_metastore LOGIN PASSWORD %L', '$sql_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='hive_metastore')
\gexec
SELECT 'CREATE DATABASE hive_metastore OWNER hive_metastore ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='hive_metastore')
\gexec
SQL
unset sql_password
```

### 2.6. Сформировать конфигурацию Hive

Создается `hive-site.xml` с настройками PostgreSQL, Metastore (включая API уведомлений), JDBC и MapReduce. Пароль и адрес HDFS из `fs.defaultFS` подставляются автоматически. Доступ к файлу ограничен пользователем `hdfs`.

```bash
cat > "$HIVE/conf/hive-site.xml" <<'HIVE_XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:postgresql://127.0.0.1:5432/hive_metastore</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>org.postgresql.Driver</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>hive_metastore</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>POSTGRES_PASSWORD</value>
  </property>
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://127.0.0.1:9083</value>
  </property>
  <property>
    <name>hive.metastore.thrift.bind.host</name>
    <value>127.0.0.1</value>
  </property>
  <property>
    <name>hive.metastore.event.db.notification.api.auth</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>true</value>
  </property>
  <property>
    <name>datanucleus.schema.autoCreateAll</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>hdfs://10.35.0.11:8020/user/hive/warehouse</value>
  </property>
  <property>
    <name>hive.metastore.warehouse.external.dir</name>
    <value>hdfs://10.35.0.11:8020/user/hive/warehouse</value>
  </property>
  <property>
    <name>hive.server2.thrift.bind.host</name>
    <value>127.0.0.1</value>
  </property>
  <property>
    <name>hive.server2.thrift.port</name>
    <value>10000</value>
  </property>
  <property>
    <name>hive.server2.webui.host</name>
    <value>10.35.0.11</value>
  </property>
  <property>
    <name>hive.server2.webui.port</name>
    <value>10002</value>
  </property>
  <property>
    <name>hive.server2.authentication</name>
    <value>NONE</value>
  </property>
  <property>
    <name>hive.server2.enable.doAs</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.security.authorization.enabled</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.execution.engine</name>
    <value>mr</value>
  </property>
  <property>
    <name>hive.exec.mode.local.auto</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.exec.local.scratchdir</name>
    <value>/var/lib/hadoop/hive/tmp</value>
  </property>
</configuration>
HIVE_XML
# Адрес HDFS берется из действующей конфигурации кластера.
fs_uri=$(runuser -u hdfs -- env JAVA_HOME="$JAVA11" \
    HADOOP_CONF_DIR="$HADOOP/etc/hadoop" "$HADOOP/bin/hdfs" getconf -confKey fs.defaultFS)
# Передаем пароль через stdin; ElementTree корректно записывает XML.
printf '%s' "$password" | python3 -c '
import sys
import xml.etree.ElementTree as ET
p = "/opt/apache-hive-4.0.1-bin/conf/hive-site.xml"
t = ET.parse(p)
for prop in t.getroot().findall("property"):
    name = prop.findtext("name")
    if name == "javax.jdo.option.ConnectionPassword":
        prop.find("value").text = sys.stdin.read()
    elif name in ("hive.metastore.warehouse.dir", "hive.metastore.warehouse.external.dir"):
        prop.find("value").text = sys.argv[1].rstrip("/") + "/user/hive/warehouse"
t.write(p, encoding="UTF-8", xml_declaration=True)
' "$fs_uri"
unset password
chown hdfs:hadoop "$BASE/env.sh" "$BASE/hadoop-conf/"* "$HIVE/conf/hive-site.xml"
chmod 0640 "$BASE/env.sh" "$BASE/hadoop-conf/"*
chmod 0600 "$HIVE/conf/hive-site.xml"
cd /
```

### 2.7. Подготовить HDFS и инициализировать схему

От `hdfs` создаются HDFS-каталоги и права. При отсутствии `public."VERSION"` схема инициализируется через `schematool`; иначе метаданные сохраняются.

```bash
schema_exists=$(runuser -u postgres -- psql -X -At -v ON_ERROR_STOP=1 -d hive_metastore \
    -c "SELECT to_regclass('public.\"VERSION\"') IS NOT NULL;")
init_schema=0
if [[ "$schema_exists" == f ]]; then
    init_schema=1
fi
runuser -u hdfs -- env INIT_SCHEMA="$init_schema" bash <<'INIT'
set -euo pipefail
cd /var/lib/hadoop/hive
source ./env.sh
hdfs dfs -mkdir -p /tmp /user/hive/warehouse /input/colours
hdfs dfs -chmod 1777 /tmp
hdfs dfs -chmod g+w /user/hive/warehouse
if [[ "$INIT_SCHEMA" == 1 ]]; then
    schematool -dbType postgres -initSchema
else
    echo 'Существующая схема метаданных сохранена.'
fi
INIT
```

### 2.8. Запустить Metastore и HiveServer2

Создаются systemd-службы и `start-hive.sh`; автозапуск отключен. Порядок запуска: Metastore → HiveServer2. Лимиты JVM: 384 MiB, 512 MiB и 256 MiB для Metastore, HiveServer2 и Beeline соответственно. PID-каталог HiveServer2 -`/var/lib/hadoop/hive`. После проверки SQL-интерфейса выполняется `data/colours.sql`, создающий `test.colours`.

```bash
cat > /etc/systemd/system/hive-metastore.service <<'METASTORE_UNIT'
[Unit]
Description=Apache Hive Metastore
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=hdfs
Group=hadoop
WorkingDirectory=/var/lib/hadoop/hive
Environment=HADOOP_HEAPSIZE_MAX=384
ExecStart=/bin/bash -c 'source /var/lib/hadoop/hive/env.sh; exec /opt/apache-hive-4.0.1-bin/bin/hive --service metastore -p 9083'
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
METASTORE_UNIT
cat > /etc/systemd/system/hive-hiveserver2.service <<'HS2_UNIT'
[Unit]
Description=Apache HiveServer2
After=network.target hive-metastore.service
Requires=hive-metastore.service

[Service]
Type=simple
User=hdfs
Group=hadoop
WorkingDirectory=/var/lib/hadoop/hive
Environment=HADOOP_HEAPSIZE_MAX=512
ExecStart=/bin/bash -c 'source /var/lib/hadoop/hive/env.sh; exec /opt/apache-hive-4.0.1-bin/bin/hive --service hiveserver2'
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
HS2_UNIT
systemctl daemon-reload
systemctl disable hive-metastore hive-hiveserver2

# Сценарий запуска выполняется от root, сами службы работают от hdfs.
cat > "$BASE/start-hive.sh" <<'START_HIVE'
#!/usr/bin/env bash
set -euo pipefail
systemctl start hive-metastore
timeout 120 bash -c 'until (echo > /dev/tcp/127.0.0.1/9083) 2>/dev/null; do sleep 2; done'
systemctl start hive-hiveserver2
runuser -u hdfs -- bash <<'WAIT_SQL'
set -euo pipefail
cd /var/lib/hadoop/hive
source ./env.sh
ready=0
for attempt in $(seq 1 30); do
    if timeout 20 beeline -u 'jdbc:hive2://127.0.0.1:10000/default' -n hdfs \
        --force=false -e 'SELECT 1;' > logs/readiness.log 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [[ "$ready" != 1 ]]; then
    echo 'HiveServer2 не готов. Проверьте journalctl -u hive-metastore -u hive-hiveserver2 и logs/readiness.log.' >&2
    exit 1
fi
WAIT_SQL
START_HIVE
chown root:root "$BASE/start-hive.sh"
chmod 0750 "$BASE/start-hive.sh"
"$BASE/start-hive.sh"

cat > "$BASE/data/colours.sql" <<'HIVE_SCHEMA'
CREATE DATABASE IF NOT EXISTS test;
USE test;

CREATE EXTERNAL TABLE IF NOT EXISTS colours (
  colour STRING,
  number INT
)
PARTITIONED BY (dt STRING)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION '/user/hive/warehouse/test.db/colours';

HIVE_SCHEMA
chown hdfs:hadoop "$BASE/data/colours.sql"
chmod 0640 "$BASE/data/colours.sql"
runuser -u hdfs -- bash <<'CREATE_TABLE'
set -euo pipefail
cd /var/lib/hadoop/hive
source ./env.sh
beeline -u 'jdbc:hive2://127.0.0.1:10000/default' -n hdfs \
    --force=false -f /var/lib/hadoop/hive/data/colours.sql
CREATE_TABLE
echo 'Hive развернут. Таблица test.colours создана. Далее запустите загрузку по инструкции.'
```

### 2.9. Выполнить автоматическое развертывание

На NameNode от `team` запустите скрипт:

```bash
sudo bash deploy.sh
```

При первом запуске ожидается `Initialization script completed`, при повторном - сообщение о сохранении схемы. После создания таблицы выводится сообщение о завершении; при ошибке скрипт останавливается.

`hive.metastore.uris` задает адрес Metastore, `org.postgresql.Driver` и JDBC URL - PostgreSQL. При `doAs=false` запросы выполняются от `hdfs`; `authentication=NONE` отключает проверку паролей клиентов. JDBC слушает только `127.0.0.1`. `hive-site.xml` содержит пароль PostgreSQL и не должен публиковаться.

Перейдите в оболочку `hdfs`:

```bash
sudo -u hdfs /bin/bash
cd /var/lib/hadoop/hive
source /var/lib/hadoop/hive/env.sh
```

Дальнейшие команды выполняйте от `hdfs`.

---

## Шаг 3. Создать партиционированную таблицу

Таблица создается автоматически в 2.8 через `/var/lib/hadoop/hive/data/colours.sql` и Beeline. `IF NOT EXISTS` сохраняет существующие объекты. `LOCATION` использует HDFS из `fs.defaultFS`. Поля: `colour`, `number`; партиция - `dt`. TSV содержит только два поля, дата задается при загрузке.

---

## Шаг 4. Подготовить файлы и загрузку в партиции

На NameNode от `hdfs` создайте два TSV без заголовка:

```bash
printf 'rouge\t10\nbleu\t20\nrouge\t30\n' > /var/lib/hadoop/hive/data/colours-2026-10-22.tsv
printf 'vert\t40\nbleu\t50\nrouge\t60\n' > /var/lib/hadoop/hive/data/colours-2026-10-23.tsv
```

Создайте и запустите скрипт загрузки:

```bash
cat > /var/lib/hadoop/hive/load-colours.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /var/lib/hadoop/hive/env.sh

for dt in 2026-10-22 2026-10-23; do
    hdfs dfs -mkdir -p "/input/colours/$dt"
    hdfs dfs -put -f "/var/lib/hadoop/hive/data/colours-$dt.tsv" "/input/colours/$dt/colours.tsv"
    timeout 600 beeline -u 'jdbc:hive2://127.0.0.1:10000/test' -n hdfs \
        --force=false -e "LOAD DATA INPATH '/input/colours/$dt/colours.tsv' OVERWRITE INTO TABLE colours PARTITION (dt='$dt');"
done
EOF

chmod 0750 /var/lib/hadoop/hive/load-colours.sh
/var/lib/hadoop/hive/load-colours.sh
```

`hdfs dfs -put` копирует TSV в HDFS; `LOAD DATA` без `LOCAL` перемещает их в партиции. `OVERWRITE` заменяет данные при повторной загрузке без дубликатов.

---

## Шаг 5. Показать работу двух клиентов и загрузку в партиции

На NameNode от `hdfs` создайте и запустите `check-hive.sh`. Два Beeline-клиента параллельно выполняют агрегацию по датам с `SET hive.fetch.task.conversion=none` (тайм-аут 600 с). Результаты сверяются с ожидаемыми; при ошибке сохраняются логи и вывод, при успехе временные файлы удаляются.

```bash
cat > /var/lib/hadoop/hive/check-hive.sh <<'CHECK_HIVE'
#!/usr/bin/env bash
set -euo pipefail
source /var/lib/hadoop/hive/env.sh
cd /var/lib/hadoop/hive
workdir=$(mktemp -d tmp/check-hive.XXXXXX)
first=''
second=''
cleanup() {
    local exit_code=$?
    for pid in "$first" "$second"; do
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    if [[ "$exit_code" == 0 ]]; then
        rm -rf "$workdir"
    else
        printf 'Логи проверки сохранены: %s/%s\n' "$PWD" "$workdir" >&2
    fi
    return "$exit_code"
}
trap cleanup EXIT
query='SELECT dt, COUNT(*), SUM(number) FROM colours GROUP BY dt ORDER BY dt;'
# Два отдельных JDBC-клиента запускаются одновременно; агрегация использует MR.
for client in client1 client2; do
    timeout 600 beeline -u 'jdbc:hive2://127.0.0.1:10000/test' -n "$client" \
        --force=false --silent=true --showHeader=false --outputformat=tsv2 \
        -e "SET hive.fetch.task.conversion=none; $query" > "$workdir/$client.out" 2> "$workdir/$client.log" &
    if [[ "$client" == client1 ]]; then first=$!; else second=$!; fi
done
status=0
wait "$first" || status=1
first=''
wait "$second" || status=1
second=''
if [[ "$status" != 0 ]]; then
    cat "$workdir/"*.log >&2
    exit 1
fi
for client in client1 client2; do
    if ! diff -u <(printf '2026-10-22\t3\t60\n2026-10-23\t3\t150\n') "$workdir/$client.out"; then
        cat "$workdir/$client.log" >&2
        exit 1
    fi
done
printf 'Два JDBC-клиента: по две партиции, 6 строк, сумма 210.\n'
CHECK_HIVE
chmod 0750 /var/lib/hadoop/hive/check-hive.sh
/var/lib/hadoop/hive/check-hive.sh
```

Каждый клиент должен получить две строки агрегации: `2026-10-22` - 3 записи, сумма `60`; `2026-10-23` - 3 записи, сумма `150`. Всего 6 записей, сумма `210`. `client1` и `client2` - отдельные JDBC-сессии.

---

## Шаг 6. Остановить и повторно запустить Hive

На NameNode вернитесь из оболочки `hdfs` к `team`:

```bash
exit
```

Остановите службы:

```bash
sudo systemctl stop hive-hiveserver2 hive-metastore
```

Запустите службы с проверкой готовности HiveServer2:

```bash
sudo /var/lib/hadoop/hive/start-hive.sh
```

Автозапуск отключен. Логи служб — в journal systemd:

```bash
sudo journalctl -u hive-metastore -u hive-hiveserver2 -n 100 --no-pager
```

Лог проверки SQL-интерфейса: `/var/lib/hadoop/hive/logs/readiness.log`.

Для запуска необходимы PostgreSQL, HDFS и YARN. Повторная инициализация схемы, форматирование NameNode и загрузка данных не требуются.

---

## Ожидаемый результат

HiveServer2 обслуживает два одновременных JDBC-клиента. Отдельный Metastore хранит метаданные в PostgreSQL. Таблица `test.colours` в HDFS имеет две партиции по `dt`; загрузка выполняется через `load-colours.sh`.
