FROM mcr.microsoft.com/azure-sql-edge

USER root

ENV ACCEPT_EULA=Y
ENV SA_PASSWORD=${SA_PASSWORD:-P@ssword1!}
ENV SQLCMDPASSWORD=${SA_PASSWORD}
ENV MSSQL_PID=${MSSQL_PID:-Developer}
ENV INSERT_SIMULATED_DATA=${INSERT_SIMULATED_DATA:-false}

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy in scripts
COPY docker-entrypoint.sh /
COPY healthcheck.sh /
COPY scripts /scripts
COPY sqlcmd /sqlcmd

# Install sqlcmd based on architecture
ARG TARGETARCH
RUN echo "Building for architecture: $TARGETARCH" && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        echo "Installing ARM64 binaries"; \
        cp sqlcmd/linux-arm64 /usr/bin/sqlcmd; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        echo "Installing AMD64 binaries"; \
        cp sqlcmd/linux-x64 /usr/bin/sqlcmd; \
    else \
        echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi

# Install .NET 8.0 runtime and SDK, then sqlpackage via dotnet tool
RUN echo "Installing .NET 8.0 SDK and runtime..." && \
    wget -q https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh && \
    chmod +x dotnet-install.sh && \
    ./dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet && \
    echo "Installing sqlpackage via dotnet tool..." && \
    export PATH="$PATH:/usr/share/dotnet" && \
    /usr/share/dotnet/dotnet tool install --global microsoft.sqlpackage && \
    echo "Setting up sqlpackage for mssql user..." && \
    mkdir -p /opt/sqlpackage && \
    cp -r /root/.dotnet/tools/.store /opt/sqlpackage/ && \
    cp /root/.dotnet/tools/sqlpackage /opt/sqlpackage/sqlpackage && \
    chmod +x /opt/sqlpackage/sqlpackage && \
    chown -R mssql:root /opt/sqlpackage && \
    rm dotnet-install.sh && \
    echo "Verifying sqlpackage installation:" && \
    file /opt/sqlpackage/sqlpackage && \
    ls -la /opt/sqlpackage/sqlpackage && \
    echo "Available .NET runtimes:" && \
    /usr/share/dotnet/dotnet --list-runtimes && \
    echo "sqlpackage installation complete"

# Set a Simple Health Check
HEALTHCHECK \
    --interval=30s \
    --retries=3 \
    --start-period=10s \
    --timeout=30s \
    CMD /healthcheck.sh

# Put CLI tools on the PATH (including sqlpackage)
ENV PATH /opt/mssql-tools/bin:/opt/sqlpackage:/root/.dotnet:/root/.dotnet/tools:$PATH

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