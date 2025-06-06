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


# Restore .bacpac files - completely ignore login issues
restore_bacpac_files() {
    local bacpac_count=0
    
    echo "=== Restoring .bacpac files - IGNORING ALL LOGIN ISSUES ==="
    
    # Process .bacpac files sequentially for better error handling
    for f in /backups/*.bacpac; do
        if [ -f "$f" ]; then
            ((bacpac_count++))
            local database_name
            local log_file
            
            database_name="$(basename "$f" .bacpac)"
            log_file="/tmp/restore_${database_name}.log"
            
            echo "$0: Starting restore of $f to database [$database_name]"
            
            # Pre-create common logins that might be needed
            echo "$0: Pre-creating common logins for [$database_name]..."
            sqlcmd -S localhost -U sa -Q "
            DECLARE @logins TABLE (name NVARCHAR(128));
            INSERT INTO @logins VALUES ('Ignition'), ('Sepasoft'), ('Liquibase');
            
            DECLARE @login NVARCHAR(128);
            DECLARE login_cursor CURSOR FOR SELECT name FROM @logins;
            OPEN login_cursor;
            FETCH NEXT FROM login_cursor INTO @login;
            
            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @login)
                BEGIN
                    BEGIN TRY
                        DECLARE @sql NVARCHAR(MAX) = 'CREATE LOGIN [' + @login + '] WITH PASSWORD = ''TempPassword123!'', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF';
                        EXEC sp_executesql @sql;
                        PRINT 'Created login: ' + @login;
                    END TRY
                    BEGIN CATCH
                        PRINT 'Failed to create login ' + @login + ': ' + ERROR_MESSAGE();
                    END CATCH
                END
                ELSE
                BEGIN
                    PRINT 'Login already exists: ' + @login;
                END
                FETCH NEXT FROM login_cursor INTO @login;
            END
            
            CLOSE login_cursor;
            DEALLOCATE login_cursor;" 2>/dev/null || true
            
            # Drop existing database if it exists
            sqlcmd -S localhost -U sa -Q "
            IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$database_name')
            BEGIN
                PRINT 'Dropping existing database [$database_name]';
                ALTER DATABASE [$database_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [$database_name];
            END" 2>/dev/null || true
            
            # Try restore with comprehensive login/security ignoring
            echo "$0: Attempting sqlpackage restore for [$database_name]..."
            
            # Use only valid properties for Import action - try basic restore first
            if sqlpackage /Action:Import \
                /SourceFile:"$f" \
                /TargetServerName:localhost \
                /TargetDatabaseName:"$database_name" \
                /TargetUser:sa \
                /TargetPassword:"${SA_PASSWORD}" \
                /TargetTrustServerCertificate:True \
                /Properties:CommandTimeout=300 \
                > "$log_file" 2>&1; then
                
                echo "$0: sqlpackage completed for [$database_name]"
            else
                echo "$0: sqlpackage had errors for [$database_name], checking if database was created..."
            fi
            
            # Check if database was actually created regardless of sqlpackage exit code
            sleep 2  # Give SQL Server a moment to complete any pending operations
            
            if sqlcmd -S localhost -U sa -Q "SELECT name FROM sys.databases WHERE name = '$database_name'" 2>/dev/null | grep -q "$database_name"; then
                echo "$0: ✓ Successfully restored $f - database [$database_name] exists and is accessible"
                
                # Try to fix any orphaned users by mapping them to existing logins or creating simple ones
                echo "$0: Fixing orphaned users in [$database_name]..."
                sqlcmd -S localhost -U sa -d "$database_name" -Q "
                DECLARE @sql NVARCHAR(MAX) = '';
                DECLARE @username NVARCHAR(128);
                
                -- Create logins for orphaned users
                DECLARE user_cursor CURSOR FOR
                SELECT dp.name
                FROM sys.database_principals dp
                LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
                WHERE dp.type IN ('S', 'U') 
                  AND dp.principal_id > 4 
                  AND sp.sid IS NULL
                  AND dp.name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys');
                
                OPEN user_cursor;
                FETCH NEXT FROM user_cursor INTO @username;
                
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    BEGIN TRY
                        -- Try to create login if it doesn't exist
                        IF NOT EXISTS (SELECT 1 FROM master.sys.server_principals WHERE name = @username)
                        BEGIN
                            SET @sql = 'CREATE LOGIN [' + @username + '] WITH PASSWORD = ''TempPassword123!'', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF';
                            EXEC sp_executesql @sql;
                            PRINT 'Created login for: ' + @username;
                        END
                        
                        -- Try to fix the user mapping
                        SET @sql = 'ALTER USER [' + @username + '] WITH LOGIN = [' + @username + ']';
                        EXEC sp_executesql @sql;
                        PRINT 'Fixed user mapping for: ' + @username;
                    END TRY
                    BEGIN CATCH
                        PRINT 'Could not fix user: ' + @username + ' - ' + ERROR_MESSAGE();
                    END CATCH
                    
                    FETCH NEXT FROM user_cursor INTO @username;
                END
                
                CLOSE user_cursor;
                DEALLOCATE user_cursor;" 2>/dev/null || true
                
                rm -f "$log_file"
            else
                echo "$0: ✗ ERROR - Failed to restore $f - database [$database_name] was not created"
                echo "$0: sqlpackage error details:"
                if [ -f "$log_file" ]; then
                    tail -30 "$log_file"
                    echo "--- Full log saved at: $log_file ---"
                else
                    echo "No log file found"
                fi
            fi
            echo
        fi
    done
    
    if [ $bacpac_count -eq 0 ]; then
        echo "$0: No .bacpac files found in /backups"
    else
        echo "$0: Processed $bacpac_count .bacpac file(s)"
        
        # Show final database list
        echo "$0: Final database list:"
        sqlcmd -S localhost -U sa -Q "SELECT name, create_date, state_desc FROM sys.databases WHERE database_id > 4 ORDER BY name" 2>/dev/null || true
    fi
    echo
}

# Main restore function that handles both .bak and .bacpac files
restore_database_backups() {
    echo "=== Starting Database Restore Process ==="
    echo "Backup directory: /backups"
    echo
    
    # First, restore all .bak files (these work fine)
    restore_bak_files
    
    # Then, restore all .bacpac files (with comprehensive login ignoring)
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

    # Restore database backups (.bak first, then .bacpac in parallel)
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