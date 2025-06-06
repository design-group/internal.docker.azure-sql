# ghcr.io/design-group/mssql-docker

## Design Group MSSQL Image

The purpose of this image is to provide a quick way to spin up docker containers that include some necessary creature comforts for automatically spinning up databases, restoring backups, and version controlling sql scripts.

This image is automatically built for the latest `azure-sql-edge` version on both arm and amd, new versions will be updated, but any features are subject to change with later versions. Upon a new pull request, if a valid build file is modified, it will trigger a build test pipeline that verifies the image still operates as expected.

If using a windows device, you will want to [Set up WSL](https://github.com/design-group/ignition-docker/blob/master/docs/setting-up-wsl.md)

___

## Getting the Docker Image

1. The user must have a local personal access token to authenticate to the Github Repository. For details on how to authenticate to the Github Repository, see the [Github Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).

1. This docker image is uploaded to the github container registry, and can be pulled with the following:

```sh
docker pull ghcr.io/design-group/mssql-docker:latest
```

___

## Customizations

This is a derived image of the microsoft `azure-sql-edge` image. Please see the [Azure SQL Edge Docker Hub](https://hub.docker.com/_/microsoft-azure-sql-edge?tab=description) for more information on the base image. This image should be able to take all arguments provided by the base image, but has not been tested.

### Backup and Restore Functionality

This image includes built-in backup and restore capabilities for both `.bak` and `.bacpac` files:

#### Creating Backups

Use the backup script to create database backups:

```bash
# Backup all databases to .bak files
docker exec your-container-name bash /scripts/backup-databases.sh

# Backup specific databases
docker exec -e EXPORT_DATABASES=SAP,My_Site_Data,MyData your-container-name bash /scripts/backup-databases.sh

# Save backups to host directory
docker exec -e BACKUP_EXPORT_DIR=/backups -v ./backups:/backups your-container-name bash /scripts/backup-databases.sh
```

#### Restoring .bak Files

**Automatic restore during startup:**

Any `.bak` files placed in the `/backups` directory of the container will be automatically restored during container startup. The database will be created with the same name as the backup file (without the `.bak` extension).

```yaml
services:
  mssql:
    image: ghcr.io/design-group/mssql-docker:latest
    volumes:
      - ./backups/my-database.bak:/backups/my-database.bak
      - ./backups/SAP.bak:/backups/SAP.bak
    environment:
      - RESTORE_DATABASES=my-database,SAP  # Optional: specify which to restore
```

**Example:** A file named `MyData.bak` will be restored as database `MyData`.

**Manual restore:**

```bash
# Restore a .bak file
docker exec your-container-name sqlcmd -S localhost -U sa -Q "
RESTORE DATABASE [NewDatabaseName] 
FROM DISK = '/backups/my-database.bak' 
WITH MOVE 'LogicalDataName' TO '/var/opt/mssql/data/NewDatabaseName.mdf',
     MOVE 'LogicalLogName' TO '/var/opt/mssql/data/NewDatabaseName.ldf',
     REPLACE"
```

#### Restoring .bacpac Files

**Automatic restore during startup:**

Any `.bacpac` files placed in the `/backups` directory will be automatically imported during container startup. The database will be created with the same name as the backup file (without the `.bacpac` extension).

**Example:** A file named `CustomerDB.bacpac` will be imported as database `CustomerDB`.

**Manual import using installed sqlpackage:**

```bash
# Import a .bacpac file
docker exec your-container-name sqlpackage /Action:Import \
  /SourceFile:"/backups/database.bacpac" \
  /TargetServerName:localhost \
  /TargetDatabaseName:RestoredDatabase \
  /TargetUser:sa \
  /TargetPassword:"${SA_PASSWORD}"
```

**Note:** 

`.bak` files are recommended for local development as they:

- Restore faster and more reliably
- Preserve all permissions, users, and database settings
- Support incremental backups (differential, transaction log)
- Have better compression and smaller file sizes

`.bacpac` files are useful for:

- Cross-platform database migrations
- Importing to Azure SQL Database
- Sharing database schema and data without SQL Server dependencies

### Backup Script

The image includes a backup script at `/scripts/backup-databases.sh` with the following environment variables:

| Environment Variable | Default | Description |
| --- | --- | --- |
| `BACKUP_EXPORT_DIR` | `/backups` | Directory to save backup files |
| `EXPORT_DATABASES` | *(all user databases)* | Comma-separated list of databases to backup |
| `SA_PASSWORD` | `P@ssword1!` | SA password for database connection |

### Simulated Data Insertion

This image will automatically insert simulated data into the database if the `INSERT_SIMULATED_DATA` environment variable is set to `true`. This is useful for testing purposes, but should not be used in production. To make these files available to the image, you can mount a volume to `/simulated-data`. The files should be in the `.sql` format and contain any necessary `INSERT` statements. The files will be executed in alphabetical order.

### Environment Variables

This image also preloads the following environment variables by default:

| Environment Variable | Value |
| --- | --- |
| `ACCEPT_EULA` | `Y` |
| `SA_PASSWORD` | `P@ssword1!` |
| `MSSQL_PID` | `Developer` |
| `INSERT_SIMULATED_DATA` | `false` |

___

### Example docker-compose file

```yaml
services:
  mssql:
    image: ghcr.io/design-group/mssql-docker:latest
    ports:
    - "1433:1433"
    environment:
      INSERT_SIMULATED_DATA: "true"
      SA_PASSWORD: "YourStrong!Passw0rd"
    volumes:
    - ./simulated-data:/simulated-data
    - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql
    - ./backups:/backups  # Mount directory for backup files
```

### Complete Backup and Restore Workflow

```bash
# 1. Start your container
docker-compose up -d

# 2. Create backups of all databases
docker exec your-mssql-container bash /scripts/backup-databases.sh

# 3. Backup files will be available in ./backups/
ls -la ./backups/
# Enterprise_20250606_123456.bak
# SAP_20250606_123456.bak
# My_Site_Data_20250606_123456.bak
# MyData_20250606_123456.bak

# 4. To restore in a new container, rename files if needed and mount them
# Files are automatically restored with the filename as the database name
mv Enterprise_20250606_123456.bak Enterprise.bak
mv SAP_20250606_123456.bak SAP.bak

# 5. Mount backup files - they'll be automatically restored on startup
# Database names will match the filenames (without extension)
```

### Advanced Backup Options

The backup script supports additional customization:

```bash
# Backup with custom export directory
docker exec -e BACKUP_EXPORT_DIR=/custom/path your-container bash /scripts/backup-databases.sh

# Backup only specific databases
docker exec -e EXPORT_DATABASES=Database1,Database2 your-container bash /scripts/backup-databases.sh

# Use custom SA password
docker exec -e SA_PASSWORD=CustomPassword your-container bash /scripts/backup-databases.sh
```

___

### Contributing

This repository uses [pre-commit](https://pre-commit.com/) to enforce code style. To install the pre-commit hooks, run `pre-commit install` from the root of the repository. This will run the hooks on every commit. If you would like to run the hooks manually, run `pre-commit run --all-files` from the root of the repository.

### Requests

If you have any requests for additional features, please feel free to [open an issue](https://github.com/design-group/mssql-docker/issues/new/choose) or submit a pull request.

### Shoutout

A big shoutout to [Kevin Collins](https://github.com/thirdgen88) for the original inspiration and support for building this image.
