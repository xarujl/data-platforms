# ДЗ1 - кластер HDFS

## Схема
| Узел | Сервисы |
| --- | --- |
| edge | Ansible для управления кластером |
| nn | NameNode и DataNode |
| dn0 (00) | SecondaryNameNode и DataNode |
| dn1 (01) | DataNode |

Java и Hadoop устанавливаются на `nn`, `00`, `01`.

## Перед запуском

Клонируйте репозиторий на машину, с которой будете запускать деплой:
```bash
git clone -b infra https://github.com/xarujl/data-platforms.git
cd data-platforms/hw1
```

Дальше выберите один из двух способов.

## Запуск с внешнего устройства

На устройстве должны быть установлены Ansible и Python.
Из каталога `hw1`:
```bash
cd infra
cp control-inventory.ini.example control-inventory.ini
cp edge/inventory.ini.example edge/inventory.ini
```

Заполните адреса:

- `EDGE_PUBLIC_IP` в `control-inventory.ini` - внешний адрес edge;
- `NN_IP`, `DN0_IP`, `DN1_IP` в `edge/inventory.ini` - внутренние адреса узлов.

Запустите:
```bash
./deploy.sh
```
Скрипт подготовит edge, скопирует проект в `/home/team/hdfs-ansible` и запустит весь цикл деплоя.

## Запуск с edge

Клонируйте репозиторий на edge. Из каталога `hw1`:
```bash
cd infra/edge
cp inventory.ini.example inventory.ini
```

Заполните `NN_IP`, `DN0_IP`, `DN1_IP` внутренними адресами узлов.
```bash
./deploy.sh
```

Скрипт установит Ansible, если его ещё нет, и выполнит весь деплой. Если файлы уже скопированы с внешнего устройства, тот же скрипт можно запустить из `/home/team/hdfs-ansible`.

## Что выполняется

Общий плейбук `infra/edge/site.yml` запускает:

1. `prepare.yml` - установка Java и Hadoop, создание пользователя, каталогов и настройка окружения.
2. `namenodes.yml` - копирование XML-конфигураций, первое форматирование NameNode, запуск NameNode и SecondaryNameNode.
3. `datanodes.yml` - запуск трёх DataNode и ожидание их регистрации в NameNode.
