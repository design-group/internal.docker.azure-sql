#!/bin/bash
# shellcheck source=/dev/null

################################################################################
# Execute any startup .sql scripts
################################################################################
execute_startup_scripts() {
	# Execute any files in the /docker-entrypoint-initdb.d directory with sqlcmd
	for f in /docker-entrypoint-initdb.d/*; do
		case "$f" in
			*.sh)     echo "$0: running $f"; . "$f" ;;
			*.sql)    echo "$0: running $f"; sqlcmd -S localhost -U sa -i "$f"; echo ;;
			*)        echo "$0: ignoring $f" ;;
		esac
		echo
	done
}

################################################################################
# Restore and pre-prepared database backups
################################################################################
restore_database_backups() {
	# Restore any database backups located in the /backups directory
	for f in /backups/*; do
		case "$f" in
			*.bak)    echo "$0: restoring $f"; sqlcmd -S localhost -U sa -i /scripts/restore-database.sql -v databaseName="$(basename "$f" .bak)" -v databaseBackup="$f"; echo ;;
			*)        echo "$0: ignoring $f" ;;
		esac
		echo
	done

}

MSSQL_BASE=${MSSQL_BASE:-/var/opt/mssql}

# Check for Init Complete
if [ ! -f "${MSSQL_BASE}/.docker-init-complete" ]; then
    # Mark Initialization Complete
    mkdir -p "${MSSQL_BASE}"
    touch "${MSSQL_BASE}"/.docker-init-complete

    # Initialize MSSQL before attempting database creation
    "$@" &
    pid="$!"

    # Wait up to 60 seconds for database initialization to complete
    echo "Database Startup In Progress..."
    for ((i=${MSSQL_STARTUP_DELAY:=60};i>0;i--)); do
        if sqlcmd -S localhost -U sa -l 1 -V 16 -Q "SELECT 1" &> /dev/null; then
            echo "Database healthy, proceeding with provisioning..."
            break
        fi
        sleep 1
    done
    if [ "$i" -le 0 ]; then
        echo >&2 "Database initialization process failed after ${MSSQL_STARTUP_DELAY} delay."
        exit 1
    fi

	restore_database_backups

	execute_startup_scripts

    echo "Startup Complete."

    # Attach and wait for exit
    wait "$pid"
else
    exec "$@"
fi