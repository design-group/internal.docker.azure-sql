#!/bin/bash
# shellcheck source=/dev/null

################################################################################
# FUNCTION DEFINITIONS - Must be defined before use
################################################################################

# Execute any startup .sql scripts
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

# Check for the `INSERT_SIMULATED_DATA` environment variable
copy_simulation_scripts() {
    if [ "$INSERT_SIMULATED_DATA" = "true" ]; then
        # Iterate through any CSV files in the /simulated-data directory and insert them into the database
        for f in /simulated-data/*; do
            case "$f" in
                *.sh)     echo "$0: running $f"; . "$f" ;;
                *.sql)    echo "$0: running $f"; sqlcmd -S localhost -U sa -i "$f"; echo ;;
                *)        echo "$0: ignoring $f" ;;
            esac
            echo
        done
    fi
}

# Restore .bak files (SQL Server native backups)
restore_bak_files() {
    local bak_count=0
    echo "=== Restoring .bak files ==="
    
    # Create restore script if it doesn't exist
    if [ ! -f /scripts/restore-database.sql ]; then
        mkdir -p /scripts
        cat > /scripts/restore-database.sql << 'EOF'
-- Restore database from .bak file
DECLARE @DatabaseName NVARCHAR(128) = '$(databaseName)';
DECLARE @BackupFile NVARCHAR(500) = '$(databaseBackup)';

-- Drop database if it exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName)
BEGIN
    PRINT 'Dropping existing database [' + @DatabaseName + ']...';
    EXEC('ALTER DATABASE [' + @DatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE');
    EXEC('DROP DATABASE [' + @DatabaseName + ']');
END

-- Restore the database
PRINT 'Restoring database [' + @DatabaseName + '] from ' + @BackupFile + '...';

-- Get file list from backup
CREATE TABLE #FileList (
    LogicalName NVARCHAR(128),
    PhysicalName NVARCHAR(260),
    Type CHAR(1),
    FileGroupName NVARCHAR(128),
    Size NUMERIC(20,0),
    MaxSize NUMERIC(20,0),
    FileId BIGINT,
    CreateLSN NUMERIC(25,0),
    DropLSN NUMERIC(25,0),
    UniqueId UNIQUEIDENTIFIER,
    ReadOnlyLSN NUMERIC(25,0),
    ReadWriteLSN NUMERIC(25,0),
    BackupSizeInBytes BIGINT,
    SourceBlockSize INT,
    FileGroupId INT,
    LogGroupGUID UNIQUEIDENTIFIER,
    DifferentialBaseLSN NUMERIC(25,0),
    DifferentialBaseGUID UNIQUEIDENTIFIER,
    IsReadOnly BIT,
    IsPresent BIT,
    TDEThumbprint VARBINARY(32),
    SnapshotUrl NVARCHAR(360)
);

INSERT INTO #FileList
EXEC('RESTORE FILELISTONLY FROM DISK = ''' + @BackupFile + '''');

-- Build restore command with file mapping
DECLARE @DataFile NVARCHAR(128);
DECLARE @LogFile renovations
DECLARE @RestoreCmd NVARCHAR(MAX);

SELECT @DataFile = LogicalName FROM #FileList WHERE Type = 'D' AND FileId = 1;
SELECT @LogFile = LogicalName FROM #FileList WHERE Type = 'L';

SET @RestoreCmd = 'RESTORE DATABASE [' + @DatabaseName + '] FROM DISK = ''' + @BackupFile + ''' WITH FILE = 1, ' +
    'MOVE ''' + @DataFile + ''' TO ''/var/opt/mssql/data/'ilibre
    'MOVE ''' + @LogFile + ''' TO ''/var/opt/mssql/data/' + @DatabaseName + '_log.ldf'', ' +
    'NOUNLOAD, REPLACE, STATS = 10';

EXEC(@RestoreCmd);

DROP TABLE #FileList;

PRINT 'Database [' + @DatabaseName + '] restored successfully.';
GO
EOF
    fi
    
    # Find and restore all .bak files
    for f in /backups/*.bak; do
        if [ -f "$f" ]; then
            ((bak_count++))
            echo "$0: restoring $f"
            if sqlcmd -S localhost -U sa -i /scripts/restore-database.sql -v databaseName="$(basename "$f" .bak)" -v databaseBackup="$f"; then
                echo "$0: successfully restored $f"
            else
                echo "$0: ERROR - failed to restore $f"
            fi
            echo
        fi
    done
    
    if [ $bak_count -eq 0 ]; then
        echo "$0: No .bak files found in /backups"
    else
        echo "$0: Restored $bak_count .bak file(s)"
    fi
    echo
}

# Restore .bacpac files
restore_bacpac_files() {
    local bacpac_count=0
    
    echo "=== Restoring .bacpac files - Dynamic Login Handling ==="
    
    # Create generic app_user login
    sqlcmd -S localhost -U sa -Q "
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_user')
        CREATE LOGIN [app_user] WITH PASSWORD = 'TempPassword123!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;" >> /tmp/login_creation.log 2>&1
    
    # Create extra logins from environment variable
    create_extra_logins() {
        if [ -n "$EXTRA_LOGINS" ]; then
            echo "$EXTRA_LOGINS" | tr ',' '\n' | while read -r login; do
                sqlcmd -S localhost -U sa -Q "
                IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$login')
                BEGIN
                    CREATE LOGIN [$login] WITH PASSWORD = 'TempPassword123!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
                    PRINT 'Created extra login: $login';
                END" >> /tmp/login_creation.log 2>&1
            done
        fi
    }
    create_extra_logins
    
    # Extract and create logins from all .bacpac files
    extract_and_create_logins() {
        local login_file="/tmp/all_logins.txt"
        rm -f "$login_file" 2>/dev/null
        touch "$login_file"
        
        for f in /backups/*.bacpac; do
            if [ -f "$f" ]; then
                local temp_dir="/tmp/bacpac_extract_$$_$((bacpac_count++))"
                mkdir -p "$temp_dir"
                unzip -q "$f" model.xml -d "$temp_dir" 2>>/tmp/login_creation.log || { echo "$0: Failed to extract model.xml from $f" >> /tmp/login_creation.log; continue; }
                if [ -f "$temp_dir/model.xml" ]; then
                    grep -oP '<Element Type="SqlUser".*?Name="\K[^"]+' "$temp_dir/model.xml" | grep -v '[\\]' | sort -u >> "$login_file"
                    rm -rf "$temp_dir"
                else
                    echo "$0: No model.xml found in $f" >> /tmp/login_creation.log
                fi
            fi
        done
        
        if [ -s "$login_file" ]; then
            while read -r login; do
                sqlcmd -S localhost -U sa -Q "
                IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$login')
                BEGIN
                    BEGIN TRY
                        CREATE LOGIN [$login] WITH PASSWORD = 'TempPassword123!', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
                        PRINT 'Created login: $login';
                    END TRY
                    BEGIN CATCH
                        PRINT 'Failed to create login $login: ' + ERROR_MESSAGE();
                    END CATCH
                END" >> /tmp/login_creation.log 2>&1
            done
        else
            echo "$0: No SQL logins found in .bacpac files" >> /tmp/login_creation.log
        fi
    }
    extract_and_create_logins
    
    bacpac_count=0  # Reset counter for restore loop
    # Process .bacpac files sequentially
    for f in /backups/*.bacpac; do
        if [ -f "$f" ]; then
            ((bacpac_count++))
            local database_name
            local log_file
            
            database_name="$(basename "$f" .bacpac)"
            log_file="/tmp/restore_${database_name}.log"
            
            echo "$0: Starting restore of $f to database [$database_name]" | tee -a "$log_file"
            
            # Drop existing database
            sqlcmd -S localhost -U sa -Q "
            IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$database_name')
            BEGIN
                ALTER DATABASE [$database_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [$database_name];
            END" >> "$log_file" 2>&1
            
            # Restore with sqlpackage
            echo "$0: Attempting sqlpackage restore for [$database_name]..." | tee -a "$log_file"
            for attempt in {1..3}; do
                if sqlpackage /Action:Import \
                    /SourceFile:"$f" \
                    /TargetServerName:localhost \
                    /TargetDatabaseName:"$database_name" \
                    /TargetUser:sa \
                    /TargetPassword:"${SA_PASSWORD}" \
                    /TargetTrustServerCertificate:True \
                    /Diagnostics:True \
                    /DiagnosticsFile:/tmp/sqlpackage_diagnostics.log \
                    /p:CommandTimeout=300 \
                    /p:LongRunningCommandTimeout=0 \
                    /p:HashObjectNamesInLogs=True \
                    >> "$log_file" 2>&1; then
                    echo "$0: sqlpackage completed for [$database_name]" | tee -a "$log_file"
                    break
                else
                    echo "$0: Retry $attempt failed for [$database_name]" >> "$log_file"
                    sleep 5
                fi
            done
            
            # Check database existence
            sleep 2
            if sqlcmd -S localhost -U sa -Q "SELECT name FROM sys.databases WHERE name = '$database_name'" 2>>"$log_file" | grep -q "$database_name"; then
                echo "$0: ✓ Successfully restored $f - database [$database_name] exists and is accessible" | tee -a "$log_file"
                
                # Map orphaned users to app_user or drop problematic users
                echo "$0: Mapping orphaned users to app_user in [$database_name]..." | tee -a "$log_file"
                sqlcmd -S localhost -U sa -d "$database_name" -Q "
                DECLARE @sql NVARCHAR(MAX) = '';
                DECLARE @username NVARCHAR(128);
                
                DECLARE user_cursor CURSOR FOR
                SELECT name FROM sys.database_principals
                WHERE type IN ('S', 'U')
                  AND principal_id > 4
                  AND name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys')
                  AND sid NOT IN (SELECT sid FROM master.sys.server_principals);
                
                OPEN user_cursor;
                FETCH NEXT FROM user_cursor INTO @username;
                
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    BEGIN TRY
                        SET @sql = 'ALTER USER [' + @username + '] WITH LOGIN = [app_user]';
                        EXEC sp_executesql @sql;
                        PRINT 'Mapped user: ' + @username + ' to app_user';
                    END TRY
                    BEGIN CATCH
                        PRINT 'Could not map user: ' + @username + ' - ' + ERROR_MESSAGE();
                        -- Drop user if mapping fails (e.g., Windows user)
                        BEGIN TRY
                            SET @sql = 'DROP USER [' + @username + ']';
                            EXEC sp_executesql @sql;
                            PRINT 'Dropped problematic user: ' + @username;
                        END TRY
                        BEGIN CATCH
                            PRINT 'Could not drop user: ' + @username + ' - ' + ERROR_MESSAGE();
                        END CATCH
                    END CATCH
                    FETCH NEXT FROM user_cursor INTO @username;
                END
                
                CLOSE user_cursor;
                DEALLOCATE user_cursor;" >> "$log_file" 2>&1
                
                rm -f "$log_file" 2>/dev/null
            else
                echo "$0: ✗ ERROR - Failed to restore $f - database [$database_name] was not created" | tee -a "$log_file"
                echo "$0: sqlpackage error details:" | tee -a "$log_file"
                if [ -f "$log_file" ]; then
                    tail -30 "$log_file" | tee -a "$log_file"
                    echo "--- Full log saved at: $log_file ---" | tee -a "$log_file"
                else
                    echo "No log file found" | tee -a "$log_file"
                fi
            fi
            echo
        fi
    done
    
    if [ $bacpac_count -eq 0 ]; then
        echo "$0: No .bacpac files found in /backups"
    else
        echo "$0: Processed $bacpac_count .bacpac file(s)"
        echo "$0: Final database list:"
        sqlcmd -S localhost -U sa -Q "SELECT name, create_date, state_desc FROM sys.databases WHERE database_id > 4 ORDER BY name" >> /tmp/database_list.log 2>&1 || true
        cat /tmp/database_list.log
    fi
    echo
}

# Main restore function that handles both .bak and .bacpac files
restore_database_backups() {
    echo "=== Starting Database Restore Process ==="
    echo "Backup directory: /backups"
    echo
    
    # First, restore all .bak files
    restore_bak_files
    
    # Then, restore all .bacpac files
    restore_bacpac_files
    
    echo "=== Database Restore Process Complete ==="
}

################################################################################
# MAIN SCRIPT EXECUTION
################################################################################

MSSQL_BASE=${MSSQL_BASE:-/var/opt/mssql}

# Check for Init Complete
if [ ! -f "${MSSQL_BASE}/.docker-init-complete" ]; then
    # Mark Initialization Complete
    mkdir -p "${MSSQL_BASE}"
    touch "${MSSQL_BASE}/.docker-init-complete"

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

    # Restore database backups (.bak first, then .bacpac)
    restore_database_backups

    # Execute startup scripts
    execute_startup_scripts

    # Copy simulation scripts
    copy_simulation_scripts

    echo "Startup Complete."

    # Attach and wait for exit
    wait "$pid"
else
    exec "$@"
fi