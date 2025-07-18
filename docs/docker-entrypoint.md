# Docker Entrypoint Script Documentation

## Overview

This script serves as the entrypoint for a Microsoft SQL Server Docker container that provides automated database backup and restore functionality. It's designed to handle the complex initialization sequence required when SQL Server starts in a containerized environment while providing robust database restoration capabilities.

## Architecture & Design Philosophy

### Why This Design?

**Container Initialization Challenge**: SQL Server containers have a unique startup sequence where the database engine must be fully operational before any database operations can be performed. This script solves the "chicken and egg" problem of needing SQL Server running to restore databases, but needing databases restored as part of container initialization.

**One-Time Initialization Pattern**: The script uses a marker file (`.docker-init-complete`) to ensure initialization only happens once, preventing duplicate restore attempts on container restarts.

**Background Process Management**: SQL Server runs as a background process while initialization occurs, allowing the script to perform database operations during startup without blocking the main SQL Server process.

## Function Documentation

### Core Initialization Functions

#### `execute_startup_scripts()`
**Purpose**: Executes custom SQL and shell scripts from the initialization directory.

```bash
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
```

**Why This Design**:
- Follows Docker convention of using `/docker-entrypoint-initdb.d/` for initialization scripts
- Uses file extension to determine execution method (source for .sh, sqlcmd for .sql)
- Provides feedback for each script execution to aid in debugging
- Executes in alphabetical order, allowing developers to control sequence with naming

#### `copy_simulation_scripts()`
**Purpose**: Conditionally executes test data insertion scripts based on environment variable.

```bash
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
```

**Why This Design**:
- Environment-driven behavior prevents accidental test data insertion in production
- Separate directory (`/simulated-data/`) keeps test scripts isolated from production initialization
- Same execution pattern as startup scripts for consistency

### Database Restoration Functions

#### `restore_bak_files()`
**Purpose**: Automatically restores SQL Server native backup files (.bak) found in the `/backups` directory.

**Key Design Decisions**:

1. **Dynamic SQL Generation**: Creates the restore script at runtime because backup files contain different logical file names that must be discovered.

```sql
-- Get file list from backup
CREATE TABLE #FileList (
    LogicalName NVARCHAR(128),
    PhysicalName NVARCHAR(260),
    Type CHAR(1),
    -- ... other columns
);

INSERT INTO #FileList
EXEC('RESTORE FILELISTONLY FROM DISK = ''' + @BackupFile + '''');
```

**Why**: Each .bak file contains different logical file names. The script must query the backup file itself to determine how to properly restore it.

2. **File Path Mapping**: Automatically maps logical file names to standardized container paths.

```sql
SET @RestoreCmd = 'RESTORE DATABASE [' + @DatabaseName + '] FROM DISK = ''' + @BackupFile + ''' WITH FILE = 1, ' +
    'MOVE ''' + @DataFile + ''' TO ''/var/opt/mssql/data/' + @DatabaseName + '.mdf'', ' +
    'MOVE ''' + @LogFile + ''' TO ''/var/opt/mssql/data/' + @DatabaseName + '_log.ldf'', ' +
    'NOUNLOAD, REPLACE, STATS = 10';
```

**Why**: Backup files contain references to original server paths that don't exist in the container. The MOVE clause relocates files to the container's data directory.

3. **Database Naming**: Uses filename (minus extension) as database name.

**Why**: Provides predictable database naming that developers can rely on for scripting and connections.

#### `extract_and_create_logins()`
**Purpose**: Extracts user information from .bacpac files and creates corresponding SQL Server logins.

**The .bacpac Challenge**:
.bacpac files contain database users but not the server logins they depend on. When imported, these users become "orphaned" because their corresponding logins don't exist on the target server.

**Solution Strategy**:

1. **XML Extraction**: Unzips .bacpac files (which are actually ZIP archives) and parses the model.xml file to find user definitions.

```bash
grep -oP '<Element Type="SqlUser".*?Name="\K[^"]+' "$temp_dir/model.xml" | grep -v '[\\]' | sort -u >> "$login_file"
```

**Why**: The model.xml contains the database schema definition including user accounts. The regex extracts usernames while filtering out Windows domain accounts (containing backslashes).

2. **Login Creation**: Creates SQL Server logins for each discovered user with a default password.

```sql
CREATE LOGIN [username] WITH PASSWORD = N'${SA_PASSWORD}', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
```

**Why**: Uses the same password as SA for simplicity in development environments. Disables policy and expiration checks to avoid authentication issues in containerized development.

3. **Error Handling**: Wraps login creation in TRY/CATCH blocks and logs all operations.

**Why**: Login creation can fail for various reasons (duplicate names, invalid characters, etc.). Comprehensive logging helps developers troubleshoot issues.

#### `restore_bacpac_files()`
**Purpose**: Imports .bacpac files using sqlpackage and handles user mapping.

**Complex Process Breakdown**:

1. **Login Pre-creation**: Calls `extract_and_create_logins()` before any imports.

**Why**: Logins must exist before users can be mapped to them. Creating all logins upfront prevents import failures due to missing logins.

2. **Generic User Creation**: Creates a fallback `app_user` login.

```sql
CREATE LOGIN [app_user] WITH PASSWORD = N'${SA_PASSWORD}', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
```

**Why**: Provides a guaranteed login that orphaned users can be mapped to if their original login cannot be created.

3. **Progress Monitoring**: Runs background monitoring during long-running imports.

```bash
monitor_import_progress "$database_name" &
local monitor_pid=$!
```

**Why**: .bacpac imports can take a very long time (especially for large databases). Progress monitoring provides feedback that the process is still working and helps identify hung imports.

4. **Retry Logic**: Attempts each import up to 3 times.

```bash
for attempt in {1..3}; do
    if sqlpackage /Action:Import \
        # ... parameters
    then
        break
    else
        sleep 5
    fi
done
```

**Why**: .bacpac imports can fail due to transient issues (memory pressure, lock timeouts, etc.). Retry logic improves reliability without manual intervention.

5. **User Mapping**: After successful import, maps orphaned users to existing logins.

```sql
DECLARE user_cursor CURSOR FOR
SELECT name FROM sys.database_principals
WHERE type IN ('S', 'U')
  AND principal_id > 4
  AND name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys')
  AND sid NOT IN (SELECT sid FROM master.sys.server_principals);
```

**Why**: Identifies database users whose SIDs don't match any server login SIDs (orphaned users). These users cannot authenticate until mapped to valid logins.

#### `monitor_import_progress()`
**Purpose**: Provides progress feedback during long-running .bacpac imports.

**Design Rationale**:

1. **Non-blocking Monitoring**: Runs as background process that doesn't interfere with import.

2. **Database State Checking**: Periodically queries `sys.databases` to check import progress.

```sql
SELECT ISNULL((SELECT state_desc FROM sys.databases WHERE name = '$database_name'), 'NOT_FOUND')
```

**Why**: The database appears in `sys.databases` as soon as sqlpackage begins creating it, and the state changes to 'ONLINE' when import completes.

3. **Timeout Protection**: Automatically stops monitoring after 15 minutes.

**Why**: Prevents infinite monitoring loops if imports fail silently or hang indefinitely.

### Main Execution Logic

#### Initialization Check Pattern

```bash
MSSQL_BASE=${MSSQL_BASE:-/var/opt/mssql}

if [ ! -f "${MSSQL_BASE}/.docker-init-complete" ]; then
    # Perform initialization
    touch "${MSSQL_BASE}/.docker-init-complete"
    # ... initialization code
else
    exec "$@"
fi
```

**Why This Pattern**:
- **Idempotency**: Ensures initialization only happens once, even if container restarts
- **Performance**: Container restarts skip expensive restoration process
- **Reliability**: Prevents duplicate database creation attempts
- **Persistence**: Marker file persists across container stops/starts when volumes are used

#### Background Process Management

```bash
"$@" &
pid="$!"

# Wait for SQL Server to be ready
for ((i=${MSSQL_STARTUP_DELAY:=60};i>0;i--)); do
    if sqlcmd -S localhost -U sa -l 1 -V 16 -Q "SELECT 1" &> /dev/null; then
        echo "Database healthy, proceeding with provisioning..."
        break
    fi
    sleep 1
done

# Perform initialization work
restore_database_backups
execute_startup_scripts
copy_simulation_scripts

# Wait for SQL Server process to complete
wait "$pid"
```

**Why This Approach**:

1. **Background Execution**: `"$@" &` starts SQL Server as background process, allowing initialization to proceed
2. **Health Checking**: Loops until SQL Server responds to connections before attempting database operations
3. **Timeout Protection**: Fails fast if SQL Server doesn't start within timeout period
4. **Process Management**: `wait "$pid"` ensures the script doesn't exit until SQL Server process completes

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `MSSQL_STARTUP_DELAY` | `60` | Seconds to wait for SQL Server startup |
| `SA_PASSWORD` | `P@ssword1!` | SA account password |
| `INSERT_SIMULATED_DATA` | `false` | Whether to execute test data scripts |

## Error Handling Strategy

The script uses multiple layers of error handling:

1. **Immediate Failures**: Critical errors (SQL Server startup failure) cause immediate script exit
2. **Graceful Degradation**: Individual restore failures are logged but don't stop other operations
3. **Comprehensive Logging**: All operations write to log files for post-mortem analysis
4. **Retry Logic**: Transient failures are automatically retried with backoff

## File System Layout

```
/var/opt/mssql/           # SQL Server data directory
├── .docker-init-complete # Initialization marker
└── data/                 # Database files

/backups/                 # Backup files directory
├── *.bak                 # SQL Server native backups
└── *.bacpac              # Data-tier application packages

/docker-entrypoint-initdb.d/  # Custom initialization scripts
├── *.sql                 # SQL scripts
└── *.sh                  # Shell scripts

/simulated-data/          # Test data scripts (conditional)
├── *.sql
└── *.sh

/scripts/                 # Built-in utility scripts
└── restore-database.sql  # Generated restore script

/tmp/                     # Temporary files and logs
├── login_creation.log    # Login creation audit trail
├── restore_*.log         # Individual restore logs
└── sqlpackage_diagnostics_*.log  # sqlpackage debug output
```

## Common Use Cases

### Development Environment Setup
1. Mount .bak files to `/backups/`
2. Container automatically restores all databases on first startup
3. Developers connect to predictably-named databases

### CI/CD Pipeline
1. Include .bacpac files in build artifacts
2. Container provides clean database state for each test run
3. Test data injection controlled by environment variable

### Database Migration
1. Export production data as .bacpac
2. Container imports and handles user mapping automatically
3. Developers work with production-like data in isolated environment

## Troubleshooting

### Common Issues

**Script appears to hang during startup**:
- Check SQL Server logs: `docker logs <container>`
- Verify SA_PASSWORD meets complexity requirements
- Increase MSSQL_STARTUP_DELAY for slower systems

**Database restore fails**:
- Check individual restore logs in `/tmp/restore_*.log`
- Verify backup file integrity
- Ensure sufficient disk space

**.bacpac import fails**:
- Check sqlpackage diagnostics in `/tmp/sqlpackage_diagnostics_*.log`
- Verify .bacpac file compatibility with SQL Server version
- Check for special characters in database/user names

**Orphaned users after .bacpac import**:
- Review login creation log: `/tmp/login_creation.log`
- Manually create missing logins
- Use `app_user` login as fallback for development

This script represents a sophisticated solution to the challenges of automated database provisioning in containerized environments, balancing reliability, performance, and developer experience.