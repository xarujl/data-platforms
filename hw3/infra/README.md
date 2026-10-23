# ДЗ3 — Apache Hive

## Схема

| Узел | Добавляемые службы |
| --- | --- |
| nn | PostgreSQL, Hive Metastore, HiveServer2 |
| dn0, dn1 | Используются существующие HDFS и NodeManager |
| edge | Запуск Ansible |

## Запуск с ноутбука

На ноутбуке нужны Ansible, Python 3 и SSH. Заполните существующие `hw1/infra/control-inventory.ini` и `hw1/infra/edge/inventory.ini`, как в ДЗ1.

Из корня репозитория:

```bash
./hw3/infra/deploy.sh
```

Сначала выполняется ДЗ2, которое само вызывает ДЗ1. После этого проект копируется на edge в `/home/team/hive-ansible`, и там запускается этап ДЗ3.

## Запуск с edge

Минимально на edge нужны Git, Python 3. Ansible заранее устанавливать не нужно - при необходимости его установит ДЗ1.

Клонируйте репозиторий и перейдите в его каталог:

```bash
git clone -b hw3 https://github.com/xarujl/data-platforms.git
cd data-platforms
```

Создайте внутренний inventory:

```bash
cp hw1/infra/edge/inventory.ini.example hw1/infra/edge/inventory.ini
```

Укажите в нём внутренние IP трёх VM и путь к SSH-ключу на edge. Затем из корня репозитория запустите:

```bash
./hw3/infra/edge/deploy.sh
```

Команда последовательно выполнит ДЗ1, ДЗ2 и ДЗ3. Внешний inventory для этого способа не нужен.

## Что выполняется

1. `prepare.yml` — устанавливает Hive и PostgreSQL на nn, создаёт БД метаданных, окружение и XML, каталоги HDFS, инициализирует новую схему Metastore.
2. `hive.yml` — запускает Metastore и HiveServer2, ожидает готовности SQL через Beeline.
3. `load.yml` — создаёт внешнюю таблицу `test.colours`, загружает TSV в HDFS и выполняет `LOAD DATA ... PARTITION` для дат `2026-10-22` и `2026-10-23`.
4. `check.yml` — запускает два JDBC-клиента параллельно, выполняет агрегацию через MapReduce и сверяет результаты: по три строки на дату, суммы 60 и 150.

Пароль PostgreSQL генерируется на nn один раз и хранится в `/var/lib/hadoop/hive/postgres-password`.

Повторная загрузка заменяет только две партиции таблицы `test.colours`, без добавления дубликатов. TSV-файлы находятся в `edge/files/`, SQL — в `edge/templates/colours.sql.j2`, скрипты на nn — в `/var/lib/hadoop/hive/`.

Автозапуск Metastore и HiveServer2 отключён. После перезагрузки запускайте полную цепочку через `deploy.sh`. При ошибке проверки каталог с логами сохраняется, его путь выводится в сообщении об ошибке.

## Подключение и проверка

JDBC `127.0.0.1:10000`, Metastore `127.0.0.1:9083` и PostgreSQL используются локально на nn. Веб-интерфейс HiveServer2 слушает внутренний IP nn на порту `10002`.

На nn:

```bash
sudo -u hdfs /bin/bash
source /var/lib/hadoop/hive/env.sh
beeline -u 'jdbc:hive2://127.0.0.1:10000/test' -n hdfs
```

В Beeline:

```sql
SHOW PARTITIONS colours;
SELECT dt, COUNT(*), SUM(number) FROM colours GROUP BY dt ORDER BY dt;
```

В двух терминалах можно открыть Beeline с `-n client1` и `-n client2`. В ResourceManager ДЗ2 будут видны MapReduce-приложения проверки.

Чтобы повторить только загрузку или проверку на nn:

```bash
sudo -u hdfs /var/lib/hadoop/hive/load-colours.sh
sudo -u hdfs /var/lib/hadoop/hive/check-hive.sh
```

Логи и управление службами на nn:

```bash
sudo journalctl -u hive-metastore -u hive-hiveserver2 -n 100 --no-pager
sudo systemctl stop hive-hiveserver2 hive-metastore
sudo systemctl start hive-metastore hive-hiveserver2
```
