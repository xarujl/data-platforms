#!/bin/bash
set -e

SSH_DIR=/home/team/.ssh

# Настройка публичного ключа для входа в контейнер
cp /run/keys/authorized.pub "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

# Только edge получает приватный ключ внутренней сети
if [ -f /run/keys/team_internal ]; then
    cp /run/keys/team_internal "$SSH_DIR/team_internal"
    chmod 600 "$SSH_DIR/team_internal"
fi

chown -R team:team "$SSH_DIR"
chmod 700 "$SSH_DIR"

# У каждого контейнера собственные SSH host keys
ssh-keygen -A

# Запуск SSH-сервера
exec /usr/sbin/sshd -D -e
