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
# Check for the `INSERT_SIMULATED_DATA` environment variable, and if so, insert the csvs from the `/simulated-data` directory into the database.
#
# This image will automatically insert simulated data into the database if the `INSERT_SIMULATED_DATA` environment variable is set to `true`. This is useful for testing purposes, but should not be used in production. To make these files available to the image, you can mount a volume to `/simulated-data`. The files should be in the format `table_name.csv` and should be comma separated. The first line of the file should be the column names. The files should be mounted in the `/simulated-data` directory. For example, if you have a file named `users.csv` that you want to insert into the `users` table, you would mount the file to `/simulated-data/users.csv`.
################################################################################
copy_simulation_scripts() {
	if [ "$INSERT_SIMULATED_DATA" = "true" ]; then
		# Iterate through any CSV files in the /simulated-data directory and insert them into the database
		for f in /simulated-data/*.csv; do
			case "$f" in
				*.csv)    echo "$0: inserting $f"; sqlcmd -S localhost -U sa -i /scripts/insert-simulated-data.sql -v csvFile="$f"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done
	fi
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

	copy_simulation_scripts


    echo "Startup Complete."

    # Attach and wait for exit
    wait "$pid"
else
    exec "$@"
fi