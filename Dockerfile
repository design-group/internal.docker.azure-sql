FROM mcr.microsoft.com/azure-sql-edge

USER root

ENV ACCEPT_EULA=Y
ENV SA_PASSWORD=${SA_PASSWORD:-P@ssword1!}
ENV SQLCMDPASSWORD=${SA_PASSWORD}
ENV MSSQL_PID=${MSSQL_PID:-Developer}
ENV INSERT_SIMULATED_DATA=${INSERT_SIMULATED_DATA:-false}

# Install dependencies for sqlpackage
RUN apt-get update && \
    apt-get install -y \
    wget \
    unzip \
    libicu-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy in scripts
COPY docker-entrypoint.sh /
COPY healthcheck.sh /
COPY scripts /scripts
COPY sqlcmd /sqlcmd

# Install sqlcmd
RUN cp sqlcmd/linux-x64 /usr/bin/sqlcmd;

# Install sqlpackage
RUN echo "Downloading sqlpackage for Linux..." && \
    wget -q "https://aka.ms/sqlpackage-linux" -O /tmp/sqlpackage.zip && \
    unzip -q /tmp/sqlpackage.zip -d /opt/sqlpackage && \
    chmod +x /opt/sqlpackage/sqlpackage && \
    echo "Verifying sqlpackage installation:" && \
    file /opt/sqlpackage/sqlpackage && \
    ls -la /opt/sqlpackage/sqlpackage && \
    rm /tmp/sqlpackage.zip && \
    echo "sqlpackage installation complete"

# Set a Simple Health Check
HEALTHCHECK \
    --interval=30s \
    --retries=3 \
    --start-period=10s \
    --timeout=60s \
    CMD /healthcheck.sh

# Put CLI tools on the PATH (including sqlpackage)
ENV PATH /opt/mssql-tools/bin:/opt/sqlpackage:$PATH

# Create some base paths and place our provisioning script
RUN mkdir /docker-entrypoint-initdb.d && \
    chown mssql:root /docker-entrypoint-initdb.d && \
    mkdir /backups && \
    chown mssql:root /backups && \
    mkdir -p /var/opt/mssql

# Return to mssql user
USER mssql

# Run SQL Server process.
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "/opt/mssql/bin/sqlservr" ]