FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        sudo \
        python3 \
        iputils-ping \
        iproute2 \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash team && \
    echo "team ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/team && \
    chmod 440 /etc/sudoers.d/team && \
    mkdir -p /home/team/.ssh /run/sshd && \
    chown team:team /home/team/.ssh && \
    chmod 700 /home/team/.ssh

RUN printf '%s\n' \
    'PasswordAuthentication no' \
    'PermitRootLogin no' \
    'PubkeyAuthentication yes' \
    > /etc/ssh/sshd_config.d/99-lab.conf && \
    rm -f /etc/ssh/ssh_host_*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

CMD ["/usr/local/bin/entrypoint.sh"]
