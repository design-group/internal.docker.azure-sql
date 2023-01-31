FROM mcr.microsoft.com/azure-sql-edge

USER root

ENV ACCEPT_EULA=Y
ENV SA_PASSWORD=${SA_PASSWORD:-P@ssword1!}
ENV SQLCMDPASSWORD=${SA_PASSWORD}
ENV MSSQL_PID=${MSSQL_PID:-Developer}

# Copy in scripts
COPY docker-entrypoint.sh /
COPY healthcheck.sh /
COPY scripts /scripts

COPY sqlcmd /sqlcmd

# If the architecture is arm copy in the correct sqlcmd
RUN if [ "$(uname -m)" = "aarch64" ]; then \
	cp sqlcmd/linux-arm64 /usr/bin/sqlcmd; \
	elif [ "$(uname -m)" = "x86_64" ]; then \
	cp sqlcmd/linux-x64 /usr/bin/sqlcmd; \
	fi

# Set a Simple Health Check
HEALTHCHECK \
    --interval=30s \
    --retries=3 \
    --start-period=10s \
    --timeout=30s \
    CMD /healthcheck.sh

# Put CLI tools on the PATH
ENV PATH /opt/mssql-tools/bin:$PATH

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