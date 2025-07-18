#!/bin/bash
# shellcheck source=/dev/null

################################################################################
# FUNCTION DEFINITIONS - Must be defined before use
################################################################################

# Execute any startup .sql scripts
execute_startup_scripts() {
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
DECLARE @LogFile NVARCHAR(128);
DECLARE @RestoreCmd NVARCHAR(MAX);

SELECT @DataFile = LogicalName FROM #FileList WHERE Type = 'D' AND FileId = 1;
SELECT @LogFile = LogicalName FROM #FileList WHERE Type = 'L';

SET @RestoreCmd = 'RESTORE DATABASE [' + @DatabaseName + '] FROM DISK = ''' + @BackupFile + ''' WITH FILE = 1, ' +
    'MOVE ''' + @DataFile + ''' TO ''/var/opt/mssql/data/' + @DatabaseName + '.mdf'', ' +
    'MOVE ''' + @LogFile + ''' TO ''/var/opt/mssql/data/' + @DatabaseName + '_log.ldf'', ' +
    'NOUNLOAD, REPLACE, STATS = 10';

EXEC(@RestoreCmd);

DROP TABLE #FileList;

PRINT 'Database [' + @DatabaseName + '] restored successfully.';
GO
EOF
    fi
    
    for f in /backups/*.bak; do
        if [ -f "$f" ]; then
            ((bak_count++))
            echo "$0: restoring $f"
            if sqlcmd -S localhost -U sa -i /scripts/restore-database.sql -v databaseName="$(basename "$f" .bak)" -v databaseBackup="$f"; then
                echo "$0: successfully restored $f"
            else
                echo "$0: failed to restore $f"
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

# Extract and create logins from .bacpac files
extract_and_create_logins() {
    local login_file="/tmp/all_logins.txt"
    local extract_counter=0
    rm -f "$login_file" 2>/dev/null
    touch "$login_file"
    
    echo "$0: Extracting logins from .bacpac files..." >> /tmp/login_creation.log
    
    for f in /backups/*.bacpac; do
        if [ -f "$f" ]; then
            local temp_dir="/tmp/bacpac_extract_$_$((extract_counter++))"
            mkdir -p "$temp_dir"
            
            if unzip -q "$f" model.xml -d "$temp_dir" >>/tmp/login_creation.log; then
                if [ -f "$temp_dir/model.xml" ]; then
                    # Extract usernames and add to the login file
                    grep -oP '<Element Type="SqlUser".*?Name="\K[^"]+' "$temp_dir/model.xml" | grep -v '[\\]' | sort -u >> "$login_file"
                else
                    echo "$0: No model.xml found in $f" >> /tmp/login_creation.log
                fi
            else
                echo "$0: Failed to extract model.xml from $f" >> /tmp/login_creation.log
            fi
            
            rm -rf "$temp_dir"
        fi
    done
    
    # Create logins from extracted usernames
    if [ -s "$login_file" ]; then
        echo "$0: Creating logins from .bacpac files..." >> /tmp/login_creation.log
        
        # Use sqlcmd with individual commands instead of building a complex SQL file
        while IFS= read -r login; do
            # Skip empty lines and validate login name
            if [ -n "$login" ] && [ ${#login} -le 128 ]; then
                echo "$0: Processing login: '$login'" >> /tmp/login_creation.log
                
                # Use sqlcmd with properly escaped parameters
                if sqlcmd -S localhost -U sa -Q "
                IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$(printf '%s' "$login" | sed "s/'/''/g")')
                BEGIN
                    BEGIN TRY
                        CREATE LOGIN [$(printf '%s' "$login" | sed "s/\]/\]\]/g")] WITH PASSWORD = N'${SA_PASSWORD}', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
                        PRINT 'Successfully created login: $(printf '%s' "$login" | sed "s/'/''/g")';
                    END TRY
                    BEGIN CATCH
                        PRINT 'Failed to create login $(printf '%s' "$login" | sed "s/'/''/g"): ' + ERROR_MESSAGE();
                    END CATCH
                END
                ELSE
                BEGIN
                    PRINT 'Login already exists: $(printf '%s' "$login" | sed "s/'/''/g")';
                END" >> /tmp/login_creation.log 2>&1; then
                    echo "$0: Successfully processed login: '$login'" >> /tmp/login_creation.log
                else
                    echo "$0: Failed to process login: '$login'" >> /tmp/login_creation.log
                fi
            else
                echo "$0: Skipping invalid login name: '$login' (length: ${#login})" >> /tmp/login_creation.log
            fi
        done < "$login_file"
        
        # Cleanup
        rm -f "$login_file"
    else
        echo "$0: No SQL logins found in .bacpac files" >> /tmp/login_creation.log
    fi
}

# Restore .bacpac files
restore_bacpac_files() {
    local bacpac_count=0
    
    echo "=== Restoring .bacpac files - Dynamic Login Handling ==="
    
    # Clear the login creation log to prevent continuous growth
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting .bacpac restore process" > /tmp/login_creation.log
    
    # Create generic app_user login
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Creating generic app_user login" >> /tmp/login_creation.log
    sqlcmd -S localhost -U sa -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_user') CREATE LOGIN [app_user] WITH PASSWORD = N'${SA_PASSWORD}', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;" >> /tmp/login_creation.log 2>&1

    # Extract and create logins from all .bacpac files
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting login extraction and creation" >> /tmp/login_creation.log
    extract_and_create_logins
    
    # Reset counter for the main restoration loop
    bacpac_count=0
    for f in /backups/*.bacpac; do
        if [ -f "$f" ]; then
            ((bacpac_count++))
            local database_name log_file
            database_name="$(basename "$f" .bacpac)"
            log_file="/tmp/restore_${database_name}.log"
            
            echo "$0: Starting restore of $f to database [$database_name]" | tee -a "$log_file"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting restore of $f to database [$database_name]" >> /tmp/login_creation.log
            
            # Get file size for progress estimation
            file_size=$(du -h "$f" | cut -f1)
            echo "$0: File size: $file_size" | tee -a "$log_file"
            
            # Drop existing database if it exists
            sqlcmd -S localhost -U sa -Q "
            IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$database_name')
            BEGIN
                ALTER DATABASE [$database_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [$database_name];
            END" >> "$log_file" 2>&1
            
            echo "$0: Attempting sqlpackage restore for [$database_name]..." | tee -a "$log_file"
            
            # Start progress monitoring in background
            monitor_import_progress "$database_name" &
            local monitor_pid=$!
            
            # Start the import with CORRECT sqlpackage arguments
            for attempt in {1..3}; do
                echo "$0: Import attempt $attempt for [$database_name]..." | tee -a "$log_file"
                
                if sqlpackage /Action:Import \
                    /SourceFile:"$f" \
                    /TargetServerName:localhost \
                    /TargetDatabaseName:"$database_name" \
                    /TargetUser:sa \
                    /TargetPassword:"${SA_PASSWORD}" \
                    /TargetTrustServerCertificate:True \
                    /Diagnostics:True \
                    /DiagnosticsFile:"/tmp/sqlpackage_diagnostics_${database_name}.log" \
                    /p:CommandTimeout=300 \
                    /p:LongRunningCommandTimeout=0 \
                    >> "$log_file" 2>&1; then
                    echo "$0: sqlpackage completed for [$database_name]" | tee -a "$log_file"
                    break
                else
                    echo "$0: Retry $attempt failed for [$database_name]" | tee -a "$log_file"
                    sleep 5
                fi
            done
            
            # Stop progress monitoring
            kill $monitor_pid 2>/dev/null || true
            wait $monitor_pid 2>/dev/null || true
            
            sleep 2
            if sqlcmd -S localhost -U sa -Q "SELECT name FROM sys.databases WHERE name = '$database_name'" 2>>"$log_file" | grep -q "$database_name"; then
                echo "$0: ✓ Successfully restored $f - database [$database_name] exists and is accessible" | tee -a "$log_file"
                
                echo "$0: Mapping orphaned users to app_user in [$database_name]..." | tee -a "$log_file"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Mapping orphaned users to app_user in [$database_name]..." >> /tmp/login_creation.log
                
                # Create a SQL script for user mapping
                local user_mapping_sql="/tmp/map_users_${database_name}.sql"
                cat > "$user_mapping_sql" << EOF
USE [$database_name];
GO

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
DEALLOCATE user_cursor;
GO
EOF
                
                # Execute the user mapping script
                sqlcmd -S localhost -U sa -i "$user_mapping_sql" >> "$log_file" 2>&1
                rm -f "$user_mapping_sql"
                
                # Clean up log files after successful restore
                rm -f "$log_file" 2>/dev/null
            else
                echo "$0: ✗ Failed to restore $f - database [$database_name] was not created" | tee -a "$log_file"
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
        cat /tmp/database_list.log 2>/dev/null || echo "Could not retrieve database list"
    fi
    echo
}

# Simplified progress monitoring function
monitor_import_progress() {
    local database_name="$1"
    local start_time=$(date +%s)
    
    while true; do
        sleep 15
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local elapsed_min=$((elapsed / 60))
        local elapsed_sec=$((elapsed % 60))
        
        # Check if database exists
        local db_status=$(sqlcmd -S localhost -U sa -h -1 -Q "SELECT ISNULL((SELECT state_desc FROM sys.databases WHERE name = '$database_name'), 'NOT_FOUND')" 2>/dev/null | tr -d ' \r\n' | tail -1)
        
        echo "$(date '+%H:%M:%S') - [${elapsed_min}m${elapsed_sec}s] Database: $database_name | Status: $db_status"
        
        # Break if database is online
        if [ "$db_status" = "ONLINE" ]; then
            echo "$(date '+%H:%M:%S') - Database $database_name is now ONLINE!"
            break
        fi
        
        # Safety break after 15 minutes
        if [ $elapsed -gt 900 ]; then
            echo "$(date '+%H:%M:%S') - Progress monitor timeout for $database_name"
            break
        fi
    done
}

# Main restore function that handles both .bak and .bacpac files
restore_database_backups() {
    echo "=== Starting Database Restore Process ==="
    echo "Backup directory: /backups"
    echo
    
    restore_bak_files
    restore_bacpac_files
    
    echo "=== Database Restore Process Complete ==="
}

################################################################################
# MAIN SCRIPT EXECUTION
################################################################################

MSSQL_BASE=${MSSQL_BASE:-/var/opt/mssql}

if [ ! -f "${MSSQL_BASE}/.docker-init-complete" ]; then
    mkdir -p "${MSSQL_BASE}"
    touch "${MSSQL_BASE}/.docker-init-complete"

    "$@" &
    pid="$!"

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
    wait "$pid"
else
    exec "$@"
fi