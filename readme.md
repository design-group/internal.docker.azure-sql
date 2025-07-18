# ghcr.io/design-group/azure-sql

## Design Group MSSQL Image

The purpose of this image is to provide a quick way to spin up docker containers that include some necessary creature comforts for automatically spinning up databases, restoring backups, and version controlling sql scripts.

This image is automatically built for the latest `azure-sql-edge` version on both arm and amd, new versions will be updated, but any features are subject to change with later versions. Upon a new pull request, if a valid build file is modified, it will trigger a build test pipeline that verifies the image still operates as expected.

If using a windows device, you will want to [Set up WSL](https://github.com/design-group/ignition-docker/blob/master/docs/setting-up-wsl.md)

### What This Container Does

This container automatically handles:
- **Database Restoration**: Automatically restores `.bak` and `.bacpac` files on startup
- **Backup Creation**: Provides scripts to backup databases to `.bak` files
- **Development Setup**: Includes optional simulated data insertion for testing
___

## Getting the Docker Image

1. The user must have a local personal access token to authenticate to the Github Repository. For details on how to authenticate to the Github Repository, see the [Github Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).

1. This docker image is uploaded to the github container registry, and can be pulled with the following:

```sh
docker pull ghcr.io/design-group/azure-sql:latest
```

___

## Customizations

This is a derived image of the microsoft `azure-sql-edge` image. Please see the [Azure SQL Edge Docker Hub](https://hub.docker.com/_/microsoft-azure-sql-edge?tab=description) for more information on the base image. This image should be able to take all arguments provided by the base image, but has not been tested.



### Quick Start

```bash
# Pull the image
docker pull ghcr.io/design-group/azure-sql:latest

# Run with basic setup
docker run -d \
  -p 1433:1433 \
  -e SA_PASSWORD="YourStrong!Passw0rd" \
  ghcr.io/design-group/azure-sql:latest
```

### Using Docker Compose

```yaml
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    ports:
      - "1433:1433"
    environment:
      SA_PASSWORD: "YourStrong!Passw0rd"
    volumes:
      - ./backups:/backups  # Auto-restore any .bak/.bacpac files here
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SA_PASSWORD` | `P@ssword1!` | SQL Server SA account password |
| `ACCEPT_EULA` | `Y` | Accept SQL Server EULA |
| `MSSQL_PID` | `Developer` | SQL Server edition |
| `INSERT_SIMULATED_DATA` | `false` | Enable automatic test data insertion |
| `MSSQL_STARTUP_DELAY` | `60` | Seconds to wait for SQL Server startup |

### Available Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `/scripts/backup-databases.sh` | Backup databases to `.bak` files | `docker exec container-name bash /scripts/backup-databases.sh` |

### Automatic Database Restoration

The container automatically restores any backup files found in the `/backups` directory during startup.

#### Restoring .bak Files (SQL Server Native Backups)

**Automatic restore during startup:**

Any `.bak` files placed in the `/backups` directory will be automatically restored. The database will be created with the same name as the backup file (without the `.bak` extension).

```yaml
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    volumes:
      - ./my-backups/MyDatabase.bak:/backups/MyDatabase.bak
      - ./my-backups/CustomerDB.bak:/backups/CustomerDB.bak
    environment:
      SA_PASSWORD: "YourStrong!Passw0rd"
```

**Example:** A file named `MyDatabase.bak` will be restored as database `MyDatabase`.

#### Restoring .bacpac Files (Cross-Platform Exports)

**Automatic restore during startup:**

Any `.bacpac` files in `/backups` will be automatically imported. The database name matches the filename (without `.bacpac` extension).

```yaml
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    volumes:
      - ./exports/Northwind.bacpac:/backups/Northwind.bacpac
      - ./exports/AdventureWorks.bacpac:/backups/AdventureWorks.bacpac
```

**Example:** A file named `Northwind.bacpac` will be imported as database `Northwind`.

**Note about .bacpac user handling:** The container automatically creates an `app_user` login and maps orphaned database users to this login, ensuring the restored database is accessible.

### Initialization Hooks

The container supports automatic execution of custom scripts during startup:

#### SQL Initialization Scripts

Place `.sql` files in `/docker-entrypoint-initdb.d/` for automatic execution:

```yaml
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    volumes:
      - ./init-scripts/01-create-tables.sql:/docker-entrypoint-initdb.d/01-create-tables.sql
      - ./init-scripts/02-seed-data.sql:/docker-entrypoint-initdb.d/02-seed-data.sql
```

Scripts are executed in alphabetical order after database restoration.

#### Simulated Data for Testing

Enable automatic test data insertion for development:

```yaml
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    environment:
      INSERT_SIMULATED_DATA: "true"
    volumes:
      - ./test-data:/simulated-data
```

Place `.sql` files in the `/simulated-data` directory. These execute after initialization scripts and are intended for test data insertion.

### Creating Backups

```bash
# Backup all databases
docker exec your-container bash /scripts/backup-databases.sh

# Backup specific databases
docker exec -e EXPORT_DATABASES=Database1,Database2 your-container bash /scripts/backup-databases.sh
```

---

## Developer Documentation

### Authentication Setup

You'll need a GitHub personal access token to pull this image. See the [GitHub Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic) for setup instructions.

### Advanced Configuration

#### Execution Order

The container executes scripts in this order during startup:

1. **Database Restoration**: `.bak` and `.bacpac` files from `/backups`
2. **Initialization Scripts**: `.sql` and `.sh` files from `/docker-entrypoint-initdb.d` (alphabetical order)
3. **Simulated Data**: `.sql` files from `/simulated-data` (only if `INSERT_SIMULATED_DATA=true`)

#### Advanced Initialization Example

```yaml
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    environment:
      SA_PASSWORD: "YourStrong!Passw0rd"
      INSERT_SIMULATED_DATA: "true"
    volumes:
      # 1. Restore these databases first
      - ./backups/ProductionDB.bak:/backups/ProductionDB.bak
      - ./backups/UserDB.bacpac:/backups/UserDB.bacpac
      
      # 2. Then run initialization scripts
      - ./scripts/01-create-views.sql:/docker-entrypoint-initdb.d/01-create-views.sql
      - ./scripts/02-create-procedures.sql:/docker-entrypoint-initdb.d/02-create-procedures.sql
      - ./scripts/setup-permissions.sh:/docker-entrypoint-initdb.d/setup-permissions.sh
      
      # 3. Finally insert test data
      - ./test-data/sample-customers.sql:/simulated-data/sample-customers.sql
      - ./test-data/sample-orders.sql:/simulated-data/sample-orders.sql
```

### Detailed Backup & Restore

#### Backup Script Environment Variables

The backup script (`/scripts/backup-databases.sh`) supports these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_EXPORT_DIR` | `/backups` | Directory to save backup files |
| `EXPORT_DATABASES` | *(all user databases)* | Comma-separated list of databases to backup |
| `SA_PASSWORD` | `P@ssword1!` | SA password for database connection |

#### Backup Examples

```bash
# Backup to custom directory
docker exec -e BACKUP_EXPORT_DIR=/custom/path container bash /scripts/backup-databases.sh

# Backup only specific databases
docker exec -e EXPORT_DATABASES=SAP,CustomerDB container bash /scripts/backup-databases.sh

# Backup with custom password
docker exec -e SA_PASSWORD=CustomPassword container bash /scripts/backup-databases.sh
```

#### Restore Process Details

**`.bak` files (Recommended for development):**
- Faster and more reliable restoration
- Preserve all permissions, users, and database settings
- Support for differential and transaction log backups
- Better compression and smaller file sizes
- Database name matches filename (without `.bak` extension)
- Automatic logical file remapping to container paths

**Manual `.bak` restore example:**
```bash
docker exec container sqlcmd -S localhost -U sa -Q "
RESTORE DATABASE [NewDatabaseName] 
FROM DISK = '/backups/my-database.bak' 
WITH MOVE 'LogicalDataName' TO '/var/opt/mssql/data/NewDatabaseName.mdf',
     MOVE 'LogicalLogName' TO '/var/opt/mssql/data/NewDatabaseName.ldf',
     REPLACE"
```

**`.bacpac` files (Cross-platform compatibility):**
- Cross-platform database migrations
- Compatible with Azure SQL Database
- Schema and data export/import (no permissions/users)
- Database name matches filename (without `.bacpac` extension)
- Automatic orphaned user resolution via `app_user` mapping
- Uses `sqlpackage` for import process

**Manual `.bacpac` import example:**
```bash
docker exec container sqlpackage /Action:Import \
  /SourceFile:"/backups/database.bacpac" \
  /TargetServerName:localhost \
  /TargetDatabaseName:RestoredDatabase \
  /TargetUser:sa \
  /TargetPassword:"${SA_PASSWORD}" \
  /TargetTrustServerCertificate:True
```

#### User Management for .bacpac Files

When importing `.bacpac` files, the container automatically:

1. **Extracts user information** from the `.bacpac` model.xml
2. **Creates server logins** for database users (using SA_PASSWORD)
3. **Maps orphaned users** to `app_user` login if mapping fails
4. **Handles login conflicts** gracefully with error logging

This ensures imported databases are immediately accessible without manual user configuration.

### Complete Development Workflow

```bash
# 1. Prepare your backup files and scripts
mkdir -p backups init-scripts test-data

# Copy your .bak/.bacpac files
cp MyDatabase.bak backups/
cp Northwind.bacpac backups/

# Create initialization scripts
echo "CREATE VIEW ActiveCustomers AS SELECT * FROM Customers WHERE Active = 1" > init-scripts/01-views.sql

# Create test data scripts (optional)
echo "INSERT INTO Customers (Name) VALUES ('Test Customer')" > test-data/sample-data.sql

# 2. Start container with mounted volumes
docker-compose up -d

# 3. Container automatically:
#    - Restores MyDatabase.bak as "MyDatabase"
#    - Imports Northwind.bacpac as "Northwind"  
#    - Runs init-scripts/01-views.sql
#    - Runs test-data/sample-data.sql (if INSERT_SIMULATED_DATA=true)

# 4. Work with your databases...
docker exec container sqlcmd -S localhost -U sa -Q "SELECT name FROM sys.databases"

# 5. Create backups of current state
docker exec container bash /scripts/backup-databases.sh

# 6. Backup files are timestamped in ./backups/
ls -la ./backups/
# MyDatabase_20250606_123456.bak
# Northwind_20250606_123456.bak

# 7. For reproducible environments, rename to remove timestamp
mv MyDatabase_20250606_123456.bak MyDatabase.bak
mv Northwind_20250606_123456.bak Northwind.bak

# 8. Next container startup will restore the exact same state
```

### Real-World Examples

#### Production Database Migration

```yaml
# Migrate production .bak files to development
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    environment:
      SA_PASSWORD: "DevPassword123!"
    volumes:
      - ./production-backups/CustomerDB.bak:/backups/CustomerDB.bak
      - ./production-backups/OrderDB.bak:/backups/OrderDB.bak
      - ./dev-scripts/mask-sensitive-data.sql:/docker-entrypoint-initdb.d/mask-data.sql
```

#### Azure SQL Database Import

```yaml
# Import .bacpac files from Azure
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    environment:
      SA_PASSWORD: "LocalDev123!"
    volumes:
      - ./azure-exports/WebApp.bacpac:/backups/WebApp.bacpac
      - ./azure-exports/Analytics.bacpac:/backups/Analytics.bacpac
```

#### Testing Environment with Sample Data

```yaml
# Development with automatic test data
services:
  mssql:
    image: ghcr.io/design-group/azure-sql:latest
    environment:
      SA_PASSWORD: "TestPassword123!"
      INSERT_SIMULATED_DATA: "true"
    volumes:
      - ./schemas/EmptyDB.bak:/backups/EmptyDB.bak
      - ./test-data/customers.sql:/simulated-data/01-customers.sql
      - ./test-data/orders.sql:/simulated-data/02-orders.sql
      - ./test-data/products.sql:/simulated-data/03-products.sql
```

### Included Tools

The container includes these pre-installed tools:
- `sqlcmd` - SQL Server command-line utility
- `sqlpackage` - Database deployment and export utility
- Standard shell utilities for scripting

### Network Configuration

For use with reverse proxies (like Traefik), the container includes labels for automatic service discovery:

```yaml
labels:
  traefik.enable: true
  traefik.hostname: azure-sql-db
  traefik.tcp.routers.azure-sql-db.entrypoints: "azure-sql"
  traefik.tcp.routers.azure-sql-db.rule: "HostSNI(`*`)"
  traefik.tcp.services.azure-sql-db-svc.loadbalancer.server.port: 1433
```

### Health Checks

The container includes a built-in health check that verifies SQL Server connectivity:

```bash
# Check container health
docker ps  # Shows health status

# Manual health check
docker exec container /healthcheck.sh
```

### Troubleshooting

**Common Issues:**

1. **Container fails to start**: Check that `SA_PASSWORD` meets complexity requirements
2. **Backup files not restored**: Ensure files are in `/backups` and have correct extensions
3. **Permission errors**: Verify file ownership and container user permissions
4. **Slow startup**: Increase `MSSQL_STARTUP_DELAY` for large backup files

**Debug logs:**
```bash
# View container logs
docker logs container-name

# View backup process logs
docker exec container cat /tmp/login_creation.log

# View restore process logs
docker exec container ls -la /tmp/restore_*.log
```

### Contributing

This repository uses [pre-commit](https://pre-commit.com/) for code quality enforcement:

```bash
# Install pre-commit hooks
pre-commit install

# Run hooks manually
pre-commit run --all-files
```

### Support

- [Open an issue](https://github.com/design-group/azure-sql/issues/new/choose) for bugs or feature requests
- Submit pull requests for contributions

### License

MIT License - see [LICENSE](LICENSE) file for details.

### Acknowledgments

Special thanks to [Kevin Collins](https://github.com/thirdgen88) for the original inspiration and support for building this image.