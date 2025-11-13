# Use the official Microsoft Dev Container Python image as a more robust base
# This image already includes a 'vscode' user and many necessary tools.
FROM mcr.microsoft.com/devcontainers/python:3.11-bullseye

# Set environment variables for Python
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Switch to the root user to install system packages
USER root

# This is the single, correct, and comprehensive RUN command block.
RUN apt-get update && \
    # Add prerequisites for adding new repositories
    apt-get install -y lsb-release curl gnupg && \
    # Add the official PostgreSQL repository for the v16 client
    curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgres-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/postgres-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    # Update package lists again to include the new repository
    apt-get update && \
    # Install all system dependencies
    apt-get install -y \
        bat build-essential cron default-jre dnsutils fzf gdal-bin git graphviz \
        htop iputils-ping jq less libpq-dev lsof nano net-tools postgresql-client-16 \
        procps ripgrep sudo tree unzip vim wget zsh && \
    # Clean up APT cache to keep the final image size smaller
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# The 'mcr.microsoft.com/devcontainers/python' base image already creates a 'vscode' user.
# We just need to add them to the sudo group.
RUN usermod -aG sudo vscode

# Switch back to the non-root 'vscode' user
USER vscode

# Set the working directory
WORKDIR /workspace

# Set the PATH to include user-installed pip packages
ENV PATH="/home/vscode/.local/bin:${PATH}"

# This command keeps the container running for VS Code to attach to
CMD ["sleep", "infinity"]