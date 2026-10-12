# Развертывание учебного кластера HDFS

## 0. Исходное состояние и целевая архитектура

Четыре отдельные виртуальные машины соединены частной сетью. Из интернета напрямую доступна только **edge-нода** с внешним IP `2.59.80.26`. На всех VM исходно есть пользователь `team`, способный выполнить `sudo` без пароля.

| VM | Имя DNS/hostname | Приватный IP | Планируемые службы |
|---|---|---|---|
| Edge | `team-35-en` | `10.35.0.10` | **DataNode №3**, **SecondaryNameNode**, клиентские команды HDFS |
| NameNode | `team-35-nn` | `10.35.0.11` | **NameNode** |
| DataNode №1 | `team-35-00` | `10.35.0.12` | **DataNode №1** |
| DataNode №2 | `team-35-01` | `10.35.0.13` | **DataNode №2** |

По условию задания требуется развернуть hdfs, включающего в себя 3 DataNode и обязательные для функционирования кластера сервисы: NameNode, Secondary NameNode.
Имеется всего четыре VM, а нужны один отдельный NameNode и три DataNode. Поэтому один DataNode совмещаем с edge. SecondaryNameNode разместим там же.

**Роли:** 
- NameNode хранит метаданные и расположение блоков
- DataNode хранят сами блоки данных
- SecondaryNameNode периодически создаёт контрольные точки метаданных

---

## Шаг 0. Подключение и обновление Ubuntu на всех VM

### 0.1. Со своего компьютера войти на edge

```bash
ssh team@2.59.80.26
```

Обновить пакеты **на edge**:

```bash
sudo apt update
sudo apt upgrade
```

### 0.2. NameNode

На **edge**:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo apt update
sudo apt upgrade
exit
```

`exit` возвращает на edge.

### 0.3. DataNode №1

На **edge**:

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo apt update
sudo apt upgrade
exit
```

### 0.4. DataNode №2

На **edge**:

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo apt update
sudo apt upgrade
exit
```

**Замечание:** если вы находитесь на NameNode и хотите попасть на другой внутренний узел, сначала выполните `exit`, чтобы вернуться на edge, либо начните новое подключение.

---

## Шаг 1. Создать системного пользователя `hadoop` на каждой VM

### 1.1. Edge

Под `team` на edge:

```bash
sudo adduser hadoop
```

Задайте надежный пароль. Поля Full Name, Room Number, Work Phone, Home Phone, Other можно оставить пустыми.

### 1.2. NameNode

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo adduser hadoop
exit
```

### 1.3. DataNode №1

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo adduser hadoop
exit
```

### 1.4. DataNode №2

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo adduser hadoop
exit
```

---

## Шаг 2. Настроить SSH для пользователя `hadoop`

Создаём одну SSH-пару на edge под `hadoop`, затем копируем её на четыре VM. Это даёт SSH-доступ между всеми узлами.

### 2.1. На edge сгенерировать пару под `hadoop`

На edge под `team`:

```bash
sudo -iu hadoop
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
ls -la ~/.ssh
exit
```

### 2.2. Скопировать `.ssh` с edge на NameNode

На edge под `team`:

```bash
sudo tar -C /home/hadoop -cf - .ssh | \
  ssh -i ~/.ssh/team_internal team@team-35-nn \
  'sudo tar -C /home/hadoop -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/.ssh'
```

### 2.3. Скопировать `.ssh` на DataNode №1

```bash
sudo tar -C /home/hadoop -cf - .ssh | \
  ssh -i ~/.ssh/team_internal team@team-35-00 \
  'sudo tar -C /home/hadoop -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/.ssh'
```

### 2.4. Скопировать `.ssh` на DataNode №2

```bash
sudo tar -C /home/hadoop -cf - .ssh | \
  ssh -i ~/.ssh/team_internal team@team-35-01 \
  'sudo tar -C /home/hadoop -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/.ssh'
```


Ключ создали сразу под пользователем hadoop. В олтичие от лекции, ключи уже имеют hadoop:hadoop, но все равно делаем дополнительный `chown` для надежности.

### 2.5. Проверить беспарольное подключение

С edge:

```bash
sudo -iu hadoop
ssh hadoop@team-35-en hostname
ssh hadoop@team-35-nn hostname
ssh hadoop@team-35-00 hostname
ssh hadoop@team-35-01 hostname
```

Первое подключение к каждому адресу может запросить подтверждение отпечатка **ключа SSH-сервера**. Подтверждайте `yes`. **Пароль учётной записи `hadoop` вводиться не должен**.

---

## Шаг 3. Установить Java 11 на все четыре VM

Для Hadoop 3.4.0 выбираем **OpenJDK 11** — поддерживаемую версию JRE/JDK для ветки Hadoop 3.3/3.4.

На edge:

```bash
sudo apt update
apt-cache policy openjdk-11-jdk
sudo apt install openjdk-11-jdk
java -version
```

На NameNode:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo apt update
sudo apt install openjdk-11-jdk
java -version
exit
```

На DataNode №1:

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo apt update
sudo apt install openjdk-11-jdk
java -version
exit
```

На DataNode №2:

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo apt update
sudo apt install openjdk-11-jdk
java -version
exit
```

Проверка `java -version`: ожидается версия `11.x` на **каждом** узле.

---

## Шаг 4. Скачать бинарный дистрибутив Hadoop 3.4.0 на edge

Официальные страницы: https://hadoop.apache.org/releases.html и https://archive.apache.org/dist/hadoop/common/hadoop-3.4.0/.

На edge под `team`:

```bash
sudo -iu hadoop
cd ~
wget https://archive.apache.org/dist/hadoop/common/hadoop-3.4.0/hadoop-3.4.0.tar.gz
```

Ждем когда скачается. Затем:

```bash
tar -xzf hadoop-3.4.0.tar.gz
ls -ld ~/hadoop-3.4.0
ls ~/hadoop-3.4.0/etc/hadoop
exit
```

---

## Шаг 5. Перенести установленный Hadoop с edge на остальные VM

Будем копировать уже распакованную директорию. Действия **все ещё под `team` на edge**. `sudo tar` читает файлы `hadoop`, на удалённых узлах `sudo tar` записывает их в `/home/hadoop`. Для корректного владельца укажем явный `chown` после распаковки.

### NameNode

```bash
sudo tar -C /home/hadoop -cf - hadoop-3.4.0 | \
  ssh -i ~/.ssh/team_internal team@team-35-nn \
  'sudo tar -C /home/hadoop -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/hadoop-3.4.0'
```

### DataNode №1

```bash
sudo tar -C /home/hadoop -cf - hadoop-3.4.0 | \
  ssh -i ~/.ssh/team_internal team@team-35-00 \
  'sudo tar -C /home/hadoop -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/hadoop-3.4.0'
```

### DataNode №2

```bash
sudo tar -C /home/hadoop -cf - hadoop-3.4.0 | \
  ssh -i ~/.ssh/team_internal team@team-35-01 \
  'sudo tar -C /home/hadoop -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/hadoop-3.4.0'
```

---

## Шаг 6. Настроить переменные окружения и пути

Настроим вначале **edge**, затем аналогично остальные VM.

### 6.1. Edge

```bash
sudo -iu hadoop
nano ~/.bashrc
```

В конец файла дописать:

```bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/home/hadoop/hadoop-3.4.0
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
```

Применяем и проверяем:

```bash
source ~/.bashrc
printf '%s\n' "$JAVA_HOME" "$HADOOP_HOME"
hadoop version
exit
```

### 6.2. NameNode

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo -iu hadoop
nano ~/.bashrc
```

Допишите **те же четыре строки**, сохраните файл, выполните:

```bash
source ~/.bashrc
hadoop version
exit
exit
```

### 6.3. DataNode №1

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo -iu hadoop
nano ~/.bashrc
```

Допишите те же строки, затем:

```bash
source ~/.bashrc
hadoop version
exit
exit
```

### 6.4. DataNode №2

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo -iu hadoop
nano ~/.bashrc
```

Допишите те же строки, затем:

```bash
source ~/.bashrc
hadoop version
exit
exit
```

---

## Шаг 7. Создать локальные каталоги для данных HDFS

Это **обычные локальные директории Linux**, не HDFS-пути. NameNode хранит там метаданные, DataNode — блоки.

### 7.1. На NameNode

На edge под `team`:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo install -d -m 700 -o hadoop -g hadoop /home/hadoop/hdfs/namenode
ls -ld /home/hadoop/hdfs/namenode
exit
```

### 7.2. На каждом DataNode (включая edge)

Edge:

```bash
sudo install -d -m 700 -o hadoop -g hadoop /home/hadoop/hdfs/datanode
```

DataNode №1:

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo install -d -m 700 -o hadoop -g hadoop /home/hadoop/hdfs/datanode
exit
```

DataNode №2:

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo install -d -m 700 -o hadoop -g hadoop /home/hadoop/hdfs/datanode
exit
```

---

## Шаг 8. Настроить Hadoop XML-конфигурацию на edge

Удобно создать единую конфигурацию на **edge под `hadoop`**, а затем скопировать её на остальные узлы. Она указывает, где находится NameNode, какие узлы запускают DataNode и где располагать локальные данные.

```bash
sudo -iu hadoop
cd ~/hadoop-3.4.0/etc/hadoop
```

### 8.1. `hadoop-env.sh`

```bash
nano hadoop-env.sh
```

Найдите `export JAVA_HOME=` и установите путь:

```bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
```

### 8.2. `core-site.xml`

```bash
nano core-site.xml
```

Укажите:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://team-35-nn:8020</value>
  </property>
</configuration>
```

`fs.defaultFS` сообщает клиентам, где искать HDFS NameNode. Имя `team-35-nn` должно разрешаться **на каждой VM**.

### 8.3. `hdfs-site.xml`

```bash
nano hdfs-site.xml
```

Вставьте:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>3</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>file:///home/hadoop/hdfs/namenode</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>file:///home/hadoop/hdfs/datanode</value>
  </property>
  <property>
    <name>dfs.namenode.secondary.http-address</name>
    <value>team-35-en:9868</value>
  </property>
</configuration>
```

- `dfs.replication=3` создаёт три реплики новых файлов при наличии трёх исправных DataNode.
- `dfs.namenode.name.dir` фактически использует только NameNode.
- `dfs.datanode.data.dir` используется тремя DataNode.
- `dfs.namenode.secondary.http-address` задаёт адрес веб-интерфейса SecondaryNameNode. Для нашего кластера дополнительно разместим его на edge.

### 8.4. `workers`

```bash
nano workers
```

Заменить содержимое:

```text
team-35-en
team-35-00
team-35-01
```

В файле **три DataNode**, а `team-35-nn` здесь отсутствует. Файл `workers` используется shell-скриптами вроде `start-dfs.sh` для запуска процессов по SSH.

---

## Шаг 9. Перенести одинаковую конфигурацию на NameNode и DataNode

На edge под `team`. **Не копируем** каталог HDFS с блоками или метаданными: только `etc/hadoop`.

### 9.1. NameNode

```bash
sudo tar -C /home/hadoop/hadoop-3.4.0 -cf - etc/hadoop | \
  ssh -i ~/.ssh/team_internal team@team-35-nn \
  'sudo tar -C /home/hadoop/hadoop-3.4.0 -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/hadoop-3.4.0/etc/hadoop'
```

### 9.2. DataNode №1

```bash
sudo tar -C /home/hadoop/hadoop-3.4.0 -cf - etc/hadoop | \
  ssh -i ~/.ssh/team_internal team@team-35-00 \
  'sudo tar -C /home/hadoop/hadoop-3.4.0 -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/hadoop-3.4.0/etc/hadoop'
```

### 9.3. DataNode №2

```bash
sudo tar -C /home/hadoop/hadoop-3.4.0 -cf - etc/hadoop | \
  ssh -i ~/.ssh/team_internal team@team-35-01 \
  'sudo tar -C /home/hadoop/hadoop-3.4.0 -xpf - && sudo chown -R hadoop:hadoop /home/hadoop/hadoop-3.4.0/etc/hadoop'
```

На шаге 8.2 уже указывали корректный `JAVA_HOME`.

---

## Шаг 10. Один раз отформатировать НОВЫЙ NameNode

На edge под `team`:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo -iu hadoop
source ~/.bashrc
hdfs namenode -format
exit
exit
```

---

## Шаг 11. Запустить HDFS и SecondaryNameNode

Чтобы исключить разночтения с расположением SecondaryNameNode, запустим службы **вручную на нужных VM**. Это показывает, где реально работают демоны, и не зависит от автоматического выбора SecondaryNameNode скриптом.

### 11.1. NameNode (только `team-35-nn`)

На edge:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon start namenode
jps
exit
exit
```

Ожидается Java-процесс `NameNode`.

### 11.2. DataNode №3 на edge

```bash
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon start datanode
jps
exit
```

### 11.3. DataNode №1

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon start datanode
jps
exit
exit
```

### 11.4. DataNode №2

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon start datanode
jps
exit
exit
```

### 11.5. SecondaryNameNode на edge

```bash
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon start secondarynamenode
jps
exit
```

- на edge ожидаются **DataNode** и **SecondaryNameNode**
- на `team-35-nn` — **NameNode**
- на каждом из `team-35-00` и `team-35-01` — **DataNode**
- `jps` может показывать также сам `Jps`.

**Примечание про `start-dfs.sh`:** он запускает NameNode на текущем узле, DataNode — на узлах из `workers` по SSH, а SecondaryNameNode — на узлах, которые определяет конфигурация. После проверки конфигурации можно запускать его с NameNode под `hadoop`, но приведённый поузловой способ прозрачнее.

---

## Шаг 12. Проверить работоспособность HDFS

### 12.1. Отчёт о DataNode

На edge:

```bash
sudo -iu hadoop
source ~/.bashrc
hdfs dfsadmin -report
```

Ожидается `Live datanodes (3)` и три узла.

### 12.2. Создать файл в HDFS и скачать обратно

На edge под `hadoop`:

```bash
printf 'Hello from HDFS!\n' > ~/hdfs-test.txt
hdfs dfs -mkdir -p /user/hadoop
hdfs dfs -put ~/hdfs-test.txt /user/hadoop/
hdfs dfs -ls /user/hadoop/
hdfs dfs -cat /user/hadoop/hdfs-test.txt
hdfs dfs -get /user/hadoop/hdfs-test.txt ~/hdfs-test-from-cluster.txt
cat ~/hdfs-test-from-cluster.txt
```

`~/hdfs-test.txt` — **локальный файл edge**. `/user/hadoop/hdfs-test.txt` — **файл в HDFS**. Это две разные файловые системы.

Проверить репликацию и расположение блоков:

```bash
hdfs fsck /user/hadoop/hdfs-test.txt -files -blocks -locations
```

Ожидается `HEALTHY` и три расположения (реплики) блока, если все DataNode живы и репликация успела завершиться.

### 12.3. Веб-интерфейсы

По умолчанию NameNode HTTP UI: `http://team-35-nn:9870`, SecondaryNameNode: `http://team-35-en:9868`.

Для доступа к **NameNode UI** с ноутбука используйте туннель (запускать со своего ноута, не VM):

```bash
ssh -N -L 9870:10.35.0.11:9870 team@2.59.80.26
```

Откройте в браузере ноутбука: `http://localhost:9870`. SSH-туннель оставьте активным до окончания просмотра. Порт на ноутбуке должен быть свободен.

Для SecondaryNameNode UI (другой терминал ноутбука):

```bash
ssh -N -L 9868:10.35.0.10:9868 team@2.59.80.26
```

Откройте `http://localhost:9868`.

```bash
exit
```

---

## Шаг 13. Как корректно останавливать и снова запускать HDFS

Останавливать удобно сначала SecondaryNameNode, потом DataNode, затем NameNode. Все команды выполняются **под `hadoop`** на соответствующих хостах.

На edge:

```bash
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon stop secondarynamenode
hdfs --daemon stop datanode
exit
```

DataNode №1:

```bash
ssh -i ~/.ssh/team_internal team@team-35-00
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon stop datanode
exit
exit
```

DataNode №2:

```bash
ssh -i ~/.ssh/team_internal team@team-35-01
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon stop datanode
exit
exit
```

NameNode:

```bash
ssh -i ~/.ssh/team_internal team@team-35-nn
sudo -iu hadoop
source ~/.bashrc
hdfs --daemon stop namenode
exit
exit
```

Для последующего запуска **повторить Шаг 11 без Шага 10**. Проверьте `hdfs dfsadmin -report`.

---
