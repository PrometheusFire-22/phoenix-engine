FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# This is the block to replace
RUN apt-get update && \
    apt-get install -y lsb-release curl gnupg && \
    curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgres-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/postgres-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y \
        build-essential \
        git \
        postgresql-client-16 \
        wget \
        vim \
        nano \
        sudo \
        zsh \
        iputils-ping \
        dnsutils \
        cron && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/zsh \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

WORKDIR /workspace

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir \
        black \
        ruff \
        pytest \
        pytest-cov \
        ipython \
        ipdb

USER $USERNAME

# ADD THIS LINE RIGHT HERE
ENV PATH="/home/vscode/.local/bin:${PATH}"

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1

CMD ["sleep", "infinity"]
