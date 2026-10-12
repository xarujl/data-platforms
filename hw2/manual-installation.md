# Ручное развертывание YARN поверх HDFS

Ручная настройка YARN на уже работающем кластере HDFS из `hw1`. Основываемся на том, что HDFS был установлен Ansible автоматизацией из hw1. Здесь настраиваются только YARN и MapReduce

## 0. Исходное состояние и целевая архитектура

В кластере четыре VM. Из интернета доступна edge-нода `2.59.80.26`, внутренние узлы доступны через неё. Hadoop 3.4.0 и Java 11 уже установлены Ansible на трёх узлах HDFS. Hadoop расположен в `/opt/hadoop-3.4.0`, системный пользователь демонов — `hdfs` (группа `hadoop`). У пользователя `hdfs` shell `nologin`, поэтому команды демонов запускаются через `sudo -u hdfs`, а не SSH-входом под `hdfs`, в отличие от семинара.

| Узел | Приватный IP | Уже работающие HDFS-службы | Добавляемые службы |
|---|---:|---|---|
| Edge `team-35-en` | `10.35.0.10` | — | Клиентский доступ/SSH-туннели; YARN-демоны не запускаются |
| NameNode `team-35-nn` | `10.35.0.11` | NameNode, DataNode | ResourceManager, JobHistoryServer, NodeManager |
| `team-35-00` | `10.35.0.12` | SecondaryNameNode, DataNode | NodeManager |
| `team-35-01` | `10.35.0.13` | DataNode | NodeManager |

В результате ResourceManager и JobHistoryServer работают на NameNode, а три NodeManager — на трех узлах, где уже установлен Hadoop

| Служба | Адрес/порт по умолчанию |
|---|---|
| ResourceManager web UI | `10.35.0.11:8088` |
| JobHistoryServer RPC | `10.35.0.11:10020` |
| JobHistoryServer web UI | `10.35.0.11:19888` |
| NodeManager web UI | каждый worker, порт `8042` |

Все действия с файлами конфигурации выполняются от `team` через `sudo`. Сами Hadoop/YARN-команды запускаются от пользователя `hdfs` с окружением, установленным Ansible.

---

## Шаг 1. Проверить существующий HDFS

С локального компьютера подключитесь к edge:

```bash
ssh team@2.59.80.26
```

На edge подключитесь к NameNode и проверьте, что он доступен и зарегистрированы три DataNode:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfsadmin -report
exit
```

В отчёте должно быть `Live datanodes (3)`. Если HDFS не работает, сначала восстановите его состояние с помощью `hw1`

Убедитесь также, что Hadoop и Java доступны на всех трёх узлах:

```text
/opt/hadoop-3.4.0
/usr/lib/jvm/java-11-openjdk-amd64
```

Ansible записывает переменные окружения в `/opt/hadoop-3.4.0/etc/hadoop/hadoop-env.sh`. Скрипты Hadoop читают этот файл при запуске, поэтому не требуется прописывать переменные в `.bashrc` пользователя `hdfs` или повторять их в каждой команде. Проверьте файл на `team-35-nn`, `team-35-00` и `team-35-01`:

```bash
sudo grep -E '^export (JAVA_HOME|HADOOP_HOME|HADOOP_CONF_DIR|PATH)=' \
  /opt/hadoop-3.4.0/etc/hadoop/hadoop-env.sh
```

В файле должны быть заданы `JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64`, `HADOOP_HOME=/opt/hadoop-3.4.0` и `HADOOP_CONF_DIR=/opt/hadoop-3.4.0/etc/hadoop`. 

**Замечание:** Переменные прописаны не в `.bashrc`, при ручном запуске команд используйте `sudo -u hdfs` и полный путь к исполняемому файлу Hadoop/YARN.

---

## Шаг 2. Подготовить локальные каталоги YARN

На каждом из трёх узлов `team-35-nn`, `team-35-00`, `team-35-01` создайте локальные каталоги NodeManager. Команды выполняются на каждом узле от `team`:

```bash
sudo install -d -o hdfs -g hadoop -m 0750 /var/lib/hadoop/yarn/local
sudo install -d -o hdfs -g hadoop -m 0750 /var/lib/hadoop/yarn/log
```

Эти каталоги используются для временных данных контейнеров и локальных логов NodeManager. Это локальные каталоги Linux, не директории HDFS.

---

## Шаг 3. Настроить MapReduce и JobHistoryServer

Создайте или отредактируйте `/opt/hadoop-3.4.0/etc/hadoop/mapred-site.xml` на `team-35-nn`:

```bash
sudo nano /opt/hadoop-3.4.0/etc/hadoop/mapred-site.xml
```

Укажите конфигурацию:

```xml
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
  <property>
    <name>mapreduce.application.classpath</name>
    <value>/opt/hadoop-3.4.0/share/hadoop/mapreduce/*,/opt/hadoop-3.4.0/share/hadoop/mapreduce/lib/*</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.address</name>
    <value>10.35.0.11:10020</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.webapp.address</name>
    <value>10.35.0.11:19888</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.intermediate-done-dir</name>
    <value>/mr-history/tmp</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.done-dir</name>
    <value>/mr-history/done</value>
  </property>
</configuration>
```

`mapreduce.framework.name=yarn` направляет MapReduce-приложения в YARN. JobHistoryServer использует RPC-порт `10020` и web-порт `19888`. Каталоги `/mr-history/tmp` и `/mr-history/done` — пути в HDFS, где сохраняются промежуточные и завершенные сведения о заданиях.

---

## Шаг 4. Настроить YARN

Создайте или отредактируйте `/opt/hadoop-3.4.0/etc/hadoop/yarn-site.xml` на `team-35-nn`:

```bash
sudo nano /opt/hadoop-3.4.0/etc/hadoop/yarn-site.xml
```

Укажите:

```xml
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>yarn.resourcemanager.hostname</name>
    <value>10.35.0.11</value>
  </property>
  <property>
    <name>yarn.resourcemanager.webapp.address</name>
    <value>10.35.0.11:8088</value>
  </property>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
  <property>
    <name>yarn.nodemanager.env-whitelist</name>
    <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
  </property>
  <property>
    <name>yarn.nodemanager.local-dirs</name>
    <value>/var/lib/hadoop/yarn/local</value>
  </property>
  <property>
    <name>yarn.nodemanager.log-dirs</name>
    <value>/var/lib/hadoop/yarn/log</value>
  </property>
</configuration>
```

Назначьте обоим новым файлам владельца `hdfs:hadoop`:

```bash
sudo chown hdfs:hadoop \
  /opt/hadoop-3.4.0/etc/hadoop/mapred-site.xml \
  /opt/hadoop-3.4.0/etc/hadoop/yarn-site.xml
```

ResourceManager располагается на `team-35-nn`; NodeManager на каждой из трёх VM регистрируется по указанному адресу `10.35.0.11`. Служба `mapreduce_shuffle` необходима для передачи промежуточных результатов MapReduce между map- и reduce-контейнерами.

---

## Шаг 5. Распространить YARN-конфигурацию на узлы

Клиентские и daemon-конфигурации должны быть одинаковыми на `nn`, `dn0` и `dn1`. Передайте два новых XML-файла с NameNode на остальные узлы через edge. Команды выполняются **на edge под `team`**. SSH-ключ `~/.ssh/team_internal` уже используется для доступа edge к внутренним узлам:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn \
  'sudo tar -C /opt/hadoop-3.4.0 -cf - etc/hadoop/mapred-site.xml etc/hadoop/yarn-site.xml' | \
  ssh -i ~/.ssh/team_internal team@team-35-00 \
  'sudo tar -C /opt/hadoop-3.4.0 -xpf - && sudo chown hdfs:hadoop /opt/hadoop-3.4.0/etc/hadoop/mapred-site.xml /opt/hadoop-3.4.0/etc/hadoop/yarn-site.xml'

ssh -i ~/.ssh/team_internal team@team-35-nn \
  'sudo tar -C /opt/hadoop-3.4.0 -cf - etc/hadoop/mapred-site.xml etc/hadoop/yarn-site.xml' | \
  ssh -i ~/.ssh/team_internal team@team-35-01 \
  'sudo tar -C /opt/hadoop-3.4.0 -xpf - && sudo chown hdfs:hadoop /opt/hadoop-3.4.0/etc/hadoop/mapred-site.xml /opt/hadoop-3.4.0/etc/hadoop/yarn-site.xml'
```

Файлы `core-site.xml` и `hdfs-site.xml` от HDFS не заменяйте: они уже настроены для работающего кластера.

---

## Шаг 6. Подготовить каталоги истории в HDFS

Создайте каталоги JobHistoryServer в HDFS и назначьте владельцем пользователя демонов `hdfs`. Команды выполняются на NameNode от `team`:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfs -mkdir -p /mr-history/tmp /mr-history/done

sudo -u hdfs /opt/hadoop-3.4.0/bin/hdfs dfs -chown -R hdfs:hadoop /mr-history
```

Проверьте, что HDFS продолжает показывать три живых DataNode. Форматировать NameNode не нужно.

---

## Шаг 7. Запустить ResourceManager и NodeManager

Из-за системного пользователя `hdfs` с shell `nologin` не запускайте `start-yarn.sh` от `hdfs`: этот скрипт ожидает возможность SSH-подключения к worker-узлам от пользователя, который его запускает. Запустите демоны адресно через `sudo`.

На `team-35-nn` запустите ResourceManager и NodeManager:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn --daemon start resourcemanager

sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn --daemon start nodemanager
```

На `team-35-00` и затем на `team-35-01` запустите NodeManager:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn --daemon start nodemanager
```

Проверьте процессы на каждом узле командой от пользователя `team`:

```bash
sudo -u hdfs /usr/lib/jvm/java-11-openjdk-amd64/bin/jps
```

Ожидаются `ResourceManager` и `NodeManager` на `nn`, а также по одному `NodeManager` на `dn0` и `dn1`.

---

## Шаг 8. Запустить JobHistoryServer

На `team-35-nn`:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/mapred --daemon start historyserver
```

На NameNode ожидаются процессы `NameNode`, `DataNode`, `ResourceManager`, `NodeManager` и `JobHistoryServer`.
- На `team-35-00` ожидаются `SecondaryNameNode`, `DataNode` и `NodeManager`
- На `team-35-01` ожидаются `DataNode` и `NodeManager`.

---

## Шаг 9. Проверить NodeManager и выполнить MapReduce-задачу

На `team-35-nn` выполните:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn node -list -all
```

Должны отображаться три NodeManager со статусом `RUNNING`.

Создайте тестовый файл от имени `hdfs`, загрузите его в HDFS и запустите стандартный WordCount:

```bash
sudo -u hdfs bash -c '
  set -e
  source /opt/hadoop-3.4.0/etc/hadoop/hadoop-env.sh
  printf "one two two three three three\\n" > /tmp/yarn-test.txt
  hdfs dfs -mkdir -p /user/hdfs/yarn-input
  hdfs dfs -put -f /tmp/yarn-test.txt /user/hdfs/yarn-input/input.txt
  hdfs dfs -rm -r -f /user/hdfs/yarn-output
  hadoop jar /opt/hadoop-3.4.0/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.0.jar \
    wordcount /user/hdfs/yarn-input /user/hdfs/yarn-output
  hdfs dfs -cat /user/hdfs/yarn-output/part-r-00000
'
```

Ожидаемый результат:

```text
one     1
three   3
two     2
```

ResourceManager UI также должен показывать выполненное приложение, а JobHistoryServer — завершённое задание.

---

## Шаг 10. Открыть веб-интерфейсы через SSH-туннель

Внутренние VM не доступны напрямую из интернета. Запустите на локальном компьютере SSH-туннель через edge:

```bash
ssh -N \
  -L 8088:10.35.0.11:8088 \
  -L 19888:10.35.0.11:19888 \
  -L 18042:10.35.0.11:8042 \
  -L 18043:10.35.0.12:8042 \
  -L 18044:10.35.0.13:8042 \
  team@2.59.80.26
```

Пока SSH-соединение открыто, доступны:

| Интерфейс | URL |
|---|---|
| ResourceManager | `http://localhost:8088` |
| JobHistoryServer | `http://localhost:19888` |
| NodeManager `team-35-nn` | `http://localhost:18042` |
| NodeManager `team-35-00` | `http://localhost:18043` |
| NodeManager `team-35-01` | `http://localhost:18044` |

Порты `8088`, `19888`, `18042`, `18043` и `18044` на локальном компьютере должны быть свободны.

---

## Шаг 11. Останавливать и повторно запускать YARN

Останавливайте демоны адресно с соответствующих VM и от пользователя `hdfs`.

На `team-35-nn` остановите JobHistoryServer, NodeManager и ResourceManager:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/mapred --daemon stop historyserver
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn --daemon stop nodemanager
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn --daemon stop resourcemanager
```

На `team-35-00` и `team-35-01` остановите NodeManager:

```bash
sudo -u hdfs /opt/hadoop-3.4.0/bin/yarn --daemon stop nodemanager
```

Чтобы запустить YARN снова, повторите шаги 7 и 8. Форматировать NameNode или перезапускать HDFS для этого не нужно.

---

## Результат

После выполнения инструкции продолжает работать исходный HDFS и добавляются службы YARN/MapReduce:

```text
team-35-nn: NameNode, DataNode, ResourceManager, NodeManager, JobHistoryServer
team-35-00: SecondaryNameNode, DataNode, NodeManager
team-35-01: DataNode, NodeManager
```

ResourceManager должен видеть три работающих NodeManager, тестовая WordCount-задача — завершиться, а её результат и история — быть доступны в HDFS и веб-интерфейсах.
