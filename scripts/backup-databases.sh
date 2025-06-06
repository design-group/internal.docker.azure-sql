#!/bin/bash
# Simple backup script that works reliably

# Configuration
EXPORT_DIR="${BACKUP_EXPORT_DIR:-/backups}"
DATABASES="${EXPORT_DATABASES:-}"
SA_PASSWORD="${SA_PASSWORD:-YourStrong!Passw0rd}"

echo "Starting backup process..."
echo "Export directory: $EXPORT_DIR"
echo "Databases: $DATABASES"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Wait for SQL Server
echo "Waiting for SQL Server..."
for i in {1..60}; do
    if sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -l 1 -Q "SELECT 1" &> /dev/null; then
        echo "SQL Server is ready"
        break
    fi
    sleep 1
    if [ "$i" -eq 60 ]; then
        echo "ERROR: SQL Server not ready after 60 seconds"
        exit 1
    fi
done

# Get databases to backup
if [ -n "$DATABASES" ]; then
    echo "Using specified databases"
    # Convert comma-separated list to array
    IFS=',' read -ra DB_ARRAY <<< "$DATABASES"
else
    echo "Getting all user databases"
    # Get all user databases - use a more reliable method
    DB_ARRAY=()
    
    # Get raw database list
    raw_output=$(sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 ORDER BY name" 2>/dev/null)
    
    # Parse each line
    while IFS= read -r line; do
        # Clean the line and check if it's a valid database name
        clean_line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
        if [ -n "$clean_line" ] && [ "$clean_line" != "name" ] && [[ ! "$clean_line" =~ "affected" ]] && [[ ! "$clean_line" =~ "---" ]]; then
            DB_ARRAY+=("$clean_line")
        fi
    done <<< "$raw_output"
fi

echo "Found ${#DB_ARRAY[@]} database(s) to backup: ${DB_ARRAY[*]}"

if [ ${#DB_ARRAY[@]} -eq 0 ]; then
    echo "No databases to backup"
    exit 0
fi

# Backup each database
success_count=0
failure_count=0

for db_name in "${DB_ARRAY[@]}"; do
    if [ -z "$db_name" ]; then
        continue
    fi
    
    echo
    echo "Backing up database: [$db_name]"
    
    backup_file="$EXPORT_DIR/${db_name}_$(date +%Y%m%d_%H%M%S).bak"
    
    # Create backup SQL
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    sql="BACKUP DATABASE [$db_name] TO DISK = '$backup_file' WITH FORMAT, INIT, NAME = '${db_name} Full Backup $timestamp', SKIP, NOREWIND, NOUNLOAD, COMPRESSION, CHECKSUM, STATS = 10"
    
    echo "  Executing backup..."
    echo "  File: $backup_file"
    
    # Execute backup and capture result
    if sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "$sql" >/dev/null 2>&1; then
        if [ -f "$backup_file" ]; then
            file_size=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  ✓ SUCCESS: $backup_file ($file_size)"
            ((success_count++))
        else
            echo "  ✗ FAILED: $db_name (backup file not created)"
            ((failure_count++))
        fi
    else
        echo "  ✗ FAILED: $db_name (SQL command failed)"
        ((failure_count++))
    fi
    
    # Small delay between backups
    sleep 1
done

echo
echo "=== BACKUP SUMMARY ==="
echo "Success: $success_count"
echo "Failed: $failure_count"
echo
echo "Backup files:"
ls -lh "$EXPORT_DIR"/*.bak 2>/dev/null || echo "No backup files found"

total_size=$(du -sh "$EXPORT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
echo "Total backup size: $total_size"