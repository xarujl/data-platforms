# Ручной запуск Apache Spark под YARN с записью таблицы Hive

## Перед началом

Исходим из того что выполнены предыдущие задания, в частности:

1) работают три DataNode.

2) работают ResourceManager и три NodeManager.

3) работают PostgreSQL, Metastore и HiveServer2, таблица `test.colours` заполнена.

Hadoop 3.4.0 установлен в `/opt/hadoop-3.4.0`, Hive 4.0.1 - в `/opt/apache-hive-4.0.1-bin`. Службы работают от `hdfs`, группа `hadoop`.

Подключаться нужно под `team`; для административных команд нужен `sudo`. У `hdfs` shell `nologin`, поэтому его оболочку запускаем через `sudo -u hdfs /bin/bash`.

| Узел | Внутренний IP | Что требуется для ДЗ4 |
|---|---|---|
| Edge `team-35-en` | `10.35.0.10` | SSH-доступ к внутренним узлам |
| NameNode `team-35-nn` | `10.35.0.11` | Java 17, Spark 4.0.3; здесь запускается driver |
| `team-35-00` | `10.35.0.12` | Java 17 для контейнеров Spark |
| `team-35-01` | `10.35.0.13` | Java 17 для контейнеров Spark |

Spark запускается под YARN в режиме `client`. Driver работает на `nn` и обращается к Metastore по `thrift://127.0.0.1:9083`. Spark установите только на `nn`: YARN передаст его библиотеки контейнерам.

На `nn` нужен доступ к Apache Archive и Maven Central. Python 3 уже установлен на узлах; используется `/usr/bin/python3`.

Из `test.colours` читаем шесть строк в двух партициях по дате. Для каждой даты и цвета считаем число записей и сумму `number`, результат записываем в `test.colours_summary`.

## Шаг 1. Проверить HDFS, YARN и Hive

С ноутбука подключитесь к edge:

```bash
ssh team@2.59.80.26
```

На edge подключитесь к NameNode:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
```

На `team-35-nn` от `team`:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfsadmin -report
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs getconf -confKey fs.defaultFS
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn node -list
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn application -list
sudo systemctl is-active postgresql hive-metastore hive-hiveserver2
```

Ожидаются `Live datanodes (3)`, адрес `hdfs://10.35.0.11:8020`, три узла YARN в состоянии `RUNNING` и `active` для трёх служб. На время задания дождитесь завершения других YARN-приложений: памяти кластера недостаточно для нескольких одновременных вычислений с указанными ниже ресурсами.

Проверьте адреса узлов:

```bash
getent hosts team-35-nn team-35-00 team-35-01
```

Имена должны разрешаться во внутренние IP из таблицы выше. Если `team-35-nn` разрешается в `127.0.1.1`, исправьте `/etc/hosts` по ДЗ2 перед запуском Spark.

Проверьте исходную таблицу через Beeline. На `nn` перейдите в оболочку `hdfs`:

```bash
sudo -u hdfs /bin/bash
cd /var/lib/hadoop/hive
source /var/lib/hadoop/hive/env.sh
beeline -u 'jdbc:hive2://127.0.0.1:10000/test' -n hdfs \
  --force=false --silent=true --showHeader=false --outputformat=tsv2 \
  -e 'SHOW PARTITIONS colours; SELECT colour, number, dt FROM colours;'
exit
```

В выводе должны быть партиции `dt=2026-10-22`, `dt=2026-10-23` и следующие записи; порядок строк может отличаться:

```text
rouge  10  2026-10-22
bleu   20  2026-10-22
rouge  30  2026-10-22
vert   40  2026-10-23
bleu   50  2026-10-23
rouge  60  2026-10-23
```

Если таблица пуста, выполните загрузку из шага 4 ДЗ3.

## Шаг 2. Установить Java 17 на три узла

Spark 4.0.3 требует Java 17. Hadoop продолжает использовать Java 11, Hive - Java 8, как в предыдущих заданиях. Их файлы окружения менять не требуется.

На `team-35-nn` от `team`:

```bash
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk-headless
/usr/lib/jvm/java-17-openjdk-amd64/bin/java -version
/usr/bin/python3 --version
```

Ожидаются Java `17` и Python не ниже `3.9`. На текущих VM установлен Python 3.12.

Вернитесь на edge:

```bash
exit
```

Подключитесь к `team-35-00` и выполните установку:

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk-headless
/usr/lib/jvm/java-17-openjdk-amd64/bin/java -version
/usr/bin/python3 --version
exit
```

Повторите на `team-35-01`:

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk-headless
/usr/lib/jvm/java-17-openjdk-amd64/bin/java -version
/usr/bin/python3 --version
exit
```

Вернитесь на `nn` под `team`:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
```

## Шаг 3. Скачать и установить Spark

На `nn`:

```bash
cd /tmp
wget -c https://archive.apache.org/dist/spark/spark-4.0.3/spark-4.0.3-bin-hadoop3.tgz
wget -O spark-4.0.3-bin-hadoop3.tgz.sha512 \
  https://archive.apache.org/dist/spark/spark-4.0.3/spark-4.0.3-bin-hadoop3.tgz.sha512
sha512sum -c spark-4.0.3-bin-hadoop3.tgz.sha512
```

Продолжайте после результата `spark-4.0.3-bin-hadoop3.tgz: OK`.

```bash
sudo tar -xzf /tmp/spark-4.0.3-bin-hadoop3.tgz -C /opt
sudo chown -R root:root /opt/spark-4.0.3-bin-hadoop3
sudo install -d -o hdfs -g hadoop -m 0750 \
  /var/lib/hadoop/spark \
  /var/lib/hadoop/spark/tmp \
  /var/lib/hadoop/spark/ivy
```

Сборка `bin-hadoop3` содержит клиентские библиотеки Hadoop. Конфигурацию кластера Spark читает из `HADOOP_CONF_DIR`.

## Шаг 4. Настроить окружение Spark

Все файлы этого шага создаются на `nn` от `team` через `sudo`.

### 4.1. Переменные окружения

```bash
sudo tee /var/lib/hadoop/spark/env.sh > /dev/null <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export SPARK_HOME=/opt/spark-4.0.3-bin-hadoop3
export SPARK_CONF_DIR=$SPARK_HOME/conf
export HADOOP_HOME=/opt/hadoop-3.4.0
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export SPARK_LOCAL_DIRS=/var/lib/hadoop/spark/tmp
export PATH=$JAVA_HOME/bin:$SPARK_HOME/bin:/usr/local/bin:/usr/bin:/bin
EOF
sudo chown root:hadoop /var/lib/hadoop/spark/env.sh
sudo chmod 0640 /var/lib/hadoop/spark/env.sh
```

### 4.2. Подключение к Hive Metastore

Создайте отдельный `hive-site.xml` для Spark:

```bash
sudo tee /opt/spark-4.0.3-bin-hadoop3/conf/hive-site.xml > /dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://127.0.0.1:9083</value>
  </property>
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>hdfs://10.35.0.11:8020/user/hive/warehouse</value>
  </property>
  <property>
    <name>hive.exec.dynamic.partition</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.exec.dynamic.partition.mode</name>
    <value>nonstrict</value>
  </property>
</configuration>
EOF
```

Режим `nonstrict` разрешает создавать партиции по значениям `dt` из DataFrame.

### 4.3. Параметры сессии и контейнеров YARN

```bash
sudo tee /opt/spark-4.0.3-bin-hadoop3/conf/spark-defaults.conf > /dev/null <<'EOF'
spark.master                              yarn
spark.submit.deployMode                    client
spark.driver.host                         10.35.0.11
spark.driver.bindAddress                  10.35.0.11
spark.driver.memory                       512m
spark.executor.instances                  1
spark.executor.cores                      1
spark.executor.memory                     1g
spark.executor.memoryOverhead             384m
spark.dynamicAllocation.enabled           false
spark.yarn.am.memory                      1g
spark.yarn.am.memoryOverhead              384m
spark.yarn.am.cores                       1
spark.yarn.appMasterEnv.JAVA_HOME          /usr/lib/jvm/java-17-openjdk-amd64
spark.executorEnv.JAVA_HOME                /usr/lib/jvm/java-17-openjdk-amd64
spark.pyspark.python                      /usr/bin/python3
spark.sql.catalogImplementation           hive
spark.sql.hive.metastore.version           4.0.1
spark.sql.hive.metastore.jars              maven
spark.sql.warehouse.dir                    hdfs://10.35.0.11:8020/user/hive/warehouse
spark.sql.shuffle.partitions               2
spark.sql.sources.partitionColumnTypeInference.enabled false
spark.jars.ivy                            /var/lib/hadoop/spark/ivy
EOF
```

При первом обращении к Metastore Spark скачает клиент Hive 4.0.1 из Maven Central. Это может занять несколько минут.

В ДЗ2 YARN настроен на 1024 MiB памяти для `nn` и по 2048 MiB для `team-35-00` и `team-35-01`. Каждый контейнер Spark запрашивает `1024 + 384 = 1408 MiB`, которые YARN округляет до `1536 MiB` с шагом `512 MiB`. Такой контейнер не помещается на `nn`. На одном из двух остальных узлов запустится ApplicationMaster, на другом - executor. Driver работает отдельным процессом на `nn` с Java heap 512 MiB; расход процесса будет выше из-за памяти JVM и Python.

Проверьте версию с окружением Spark:

```bash
sudo -u hdfs /bin/bash
source /var/lib/hadoop/spark/env.sh
cd /var/lib/hadoop/spark
java -version
spark-submit --version
exit
```

Ожидаются Java `17` и Spark `4.0.3`.

## Шаг 5. Проверить расположение исходных данных

На `nn` от `team`:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfs -ls -R \
  /user/hive/warehouse/test.db/colours
```

Должны быть два файла:

```text
/user/hive/warehouse/test.db/colours/dt=2026-10-22/colours.tsv
/user/hive/warehouse/test.db/colours/dt=2026-10-23/colours.tsv
```

Проверьте их содержимое:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfs -cat \
  /user/hive/warehouse/test.db/colours/dt=2026-10-22/colours.tsv
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfs -cat \
  /user/hive/warehouse/test.db/colours/dt=2026-10-23/colours.tsv
```

В TSV находятся только `colour` и `number`. Дата хранится в имени каталога партиции. После `LOAD DATA` из ДЗ3 файлы перемещены сюда из `/input/colours`; читать нужно warehouse.

## Шаг 6. Запустить сессию PySpark под YARN

На `nn` перейдите в оболочку `hdfs` и загрузите окружение Spark:

```bash
sudo -u hdfs /bin/bash
source /var/lib/hadoop/spark/env.sh
cd /var/lib/hadoop/spark
pyspark --master yarn --deploy-mode client --name hw4-colours
```

После появления `>>>` выполняйте Python-блоки шагов 6–8 в этой оболочке. Сессия доступна в переменной `spark`.

Проверьте кластер и каталог:

```python
spark.sparkContext.setLogLevel("WARN")
print(spark.version)
print(spark.sparkContext.master)
print(spark.sparkContext.applicationId)
print(spark.conf.get("spark.sql.catalogImplementation"))
print(spark.sparkContext._jsc.hadoopConfiguration().get("fs.defaultFS"))
spark.sql("SHOW TABLES IN test").show(truncate=False)
```

Ожидаются `4.0.3`, `yarn`, идентификатор вида `application_...`, `hive`, `hdfs://10.35.0.11:8020` и таблица `colours` в базе `test`. Сохраните идентификатор приложения для проверки YARN.

## Шаг 7. Прочитать данные из HDFS и выполнить преобразования

В той же сессии PySpark:

```python
from pyspark.sql import functions as F

source_path = "hdfs://10.35.0.11:8020/user/hive/warehouse/test.db/colours"
raw = (
    spark.read
    .option("sep", "\t")
    .option("mode", "FAILFAST")
    .option("basePath", source_path)
    .schema("colour STRING, number STRING")
    .csv(source_path)
)

raw.printSchema()
raw.orderBy("dt", "colour", "number").show(truncate=False)
assert raw.count() == 6
```

У `raw` должны быть три поля типа `string`: `colour`, `number`, `dt`.

Приведите названия цветов к верхнему регистру, числа к `bigint`, дату к `date`; отберите заполненные записи:

```python
prepared = (
    raw.select(
        F.upper(F.trim(F.col("colour"))).alias("colour"),
        F.col("number").cast("bigint").alias("number"),
        F.to_date(F.col("dt"), "yyyy-MM-dd").alias("dt"),
    )
    .filter(
        F.col("colour").isNotNull()
        & (F.col("colour") != "")
        & F.col("number").isNotNull()
        & F.col("dt").isNotNull()
    )
)

prepared.printSchema()
assert prepared.count() == 6
```

Сгруппируйте записи по дате и цвету:

```python
summary = (
    prepared.groupBy("dt", "colour")
    .agg(
        F.count("*").alias("records"),
        F.sum("number").alias("total_number"),
    )
    .select("colour", "records", "total_number", "dt")
)

summary.orderBy("dt", "colour").show(truncate=False)
assert summary.count() == 5
totals = summary.agg(F.sum("records"), F.sum("total_number")).first()
assert tuple(totals) == (6, 210)
```

Ожидаемый результат:

| colour | records | total_number | dt |
|---|---:|---:|---|
| BLEU | 1 | 20 | 2026-10-22 |
| ROUGE | 2 | 40 | 2026-10-22 |
| BLEU | 1 | 50 | 2026-10-23 |
| ROUGE | 1 | 60 | 2026-10-23 |
| VERT | 1 | 40 | 2026-10-23 |

## Шаг 8. Сохранить партиционированную таблицу

В той же сессии PySpark:

```python
result_path = "hdfs://10.35.0.11:8020/user/hive/warehouse/test.db/colours_summary"
(
    summary.write
    .mode("overwrite")
    .format("hive")
    .option("fileFormat", "parquet")
    .option("path", result_path)
    .partitionBy("dt")
    .saveAsTable("test.colours_summary")
)
```

Spark создаст внешнюю таблицу с Hive Parquet SerDe и сохранит её метаданные в Metastore .

Повторный запуск этого блока заменяет результат `test.colours_summary`.

Проверьте таблицу через Spark:

```python
spark.sql("SHOW PARTITIONS test.colours_summary").show(truncate=False)
spark.sql("DESCRIBE test.colours_summary").show(truncate=False)
spark.sql("""
    SELECT colour, records, total_number, dt
    FROM test.colours_summary
    ORDER BY dt, colour
""").show(truncate=False)
```

Должны быть две партиции `dt=2026-10-22`, `dt=2026-10-23`. Типы столбцов: `colour string`, `records bigint`, `total_number bigint`, `dt date`.

Завершите сессию, затем выйдите из оболочки `hdfs`:

```python
spark.stop()
exit()
```

```bash
exit
```

## Шаг 9. Проверить файлы HDFS и приложение YARN

На `nn` от `team`:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfs -ls -R \
  /user/hive/warehouse/test.db/colours_summary
```

В каталогах `dt=2026-10-22` и `dt=2026-10-23` должны лежать файлы `part-*`. При записи через Hive их имена могут заканчиваться на `.c000` без расширения `.parquet`. Поле `dt` задаётся каталогом партиции и не дублируется в файлах.

Формат проверьте на шаге 10: `DESCRIBE FORMATTED colours_summary` должен показать `org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe`, а запросы через Beeline — вернуть ожидаемые строки и итоговые значения.

Для проверки приложения подставьте вместо `application_...` идентификатор из шага 6:

```bash
APP_ID=application_...
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn application -status "$APP_ID"
```

После завершения сессии ожидаются `Application-Type: SPARK`, `State: FINISHED` и `Final-State: SUCCEEDED`.

Веб-интерфейс ResourceManager можно открыть через туннель. В отдельном терминале ноутбука:

```bash
ssh -N -L 127.0.0.1:8088:10.35.0.11:8088 team@2.59.80.26
```

Откройте [http://127.0.0.1:8088](http://127.0.0.1:8088). В списке приложений должно быть `hw4-colours` с типом `SPARK`.

## Шаг 10. Прочитать результат стандартным клиентом Hive

На `nn` от `team` откройте новую оболочку `hdfs` с окружением Hive:

```bash
sudo -u hdfs /bin/bash
cd /var/lib/hadoop/hive
source /var/lib/hadoop/hive/env.sh
beeline -u 'jdbc:hive2://127.0.0.1:10000/test' -n hdfs --force=false
```

В приглашении Beeline выполните:

```sql
SHOW TABLES LIKE 'colours_summary';
SHOW PARTITIONS colours_summary;
DESCRIBE FORMATTED colours_summary;

SELECT colour, records, total_number, dt
FROM colours_summary
ORDER BY dt, colour;

SELECT COUNT(*) AS result_rows,
       SUM(records) AS source_rows,
       SUM(total_number) AS total_number
FROM colours_summary;
```

В описании должны быть `Table Type: EXTERNAL_TABLE`, путь `/user/hive/warehouse/test.db/colours_summary` и `org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe`. Запрос строк должен вернуть таблицу из шага 7, а итоговый запрос:

| result_rows | source_rows | total_number |
|---:|---:|---:|
| 5 | 6 | 210 |

Выйдите из Beeline и оболочки `hdfs`:

```text
!quit
```

```bash
exit
```

## Повторный запуск и диагностика

Для повторного запуска выполните шаги 6–10.

Если приложение остаётся в `ACCEPTED`, проверьте состояния узлов и список приложений:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn node -list
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn application -list
```

Если контейнер завершился с ошибкой, запросите логи, используя свой `APP_ID` из шага 9:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn logs -applicationId "$APP_ID"
```

Ошибки driver в режиме `client` выводятся в терминал PySpark. При ошибке подключения к Metastore проверьте службу и порт на `nn`:

```bash
sudo systemctl status hive-metastore --no-pager
sudo journalctl -u hive-metastore -n 50 --no-pager
sudo ss -lntp 'sport = :9083'
```

Если в журнале есть ошибка скачивания JAR, проверьте доступ `nn` к Maven Central и права на `/var/lib/hadoop/spark/ivy`. Если возникает `UnsupportedClassVersionError`, проверьте Java 17 на всех трёх узлах и значения `JAVA_HOME` в шаге 4.3.
