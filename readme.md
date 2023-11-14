# ghcr.io/design-group/mssql-docker/mssql-docker

## Design Group MSSQL Image

The purpose of this image is to provide a quick way to spin up docker containers that include some necessary creature comforts for automatically spinning up databases, restoring backups, and version controlling sql scripts.

This image is automatically built for the latest `azure-sql-edge` version on both arm and amd, new versions will be updated, but any features are subject to change with later versions. Upon a new pull request, if a valid build file is modified, it will trigger a build test pipeline that verifies the image still operates as expected.

If using a windows device, you will want to [Set up WSL](https://github.com/design-group/ignition-docker/blob/master/docs/setting-up-wsl.md)

___

## Getting the Docker Imgage

1. The user must have a local personal access token to authenticate to the Github Repository. For details on how to authenticate to the Github Repository, see the [Github Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).

1. This docker image is uploaded to the github container registry, and can be pulled with the following:
```sh
docker pull ghcr.io/design-group/mssql-docker/mssql-docker:latest
```

___

## Customizations

This is a derived image of the microsoft `azure-sql-edge` image. Please see the [Azure SQL Edge Docker Hub](https://hub.docker.com/_/microsoft-azure-sql-edge?tab=description) for more information on the base image. This image should be able to take all arguments provided by the base image, but has not been tested.

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
		image: ghcr.io/design-group/mssql-docker/mssql-docker:latest
		ports:
		- "1433:1433"
		environment:
		  INSERT_SIMULATED_DATA: "true"
		volumes:
		- ./simulated-data:/simulated-data
		- ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql
		- ./backups/my-database.bak:/backups/my-database.bak
```

___

### Contributing

This repository uses [pre-commit](https://pre-commit.com/) to enforce code style. To install the pre-commit hooks, run `pre-commit install` from the root of the repository. This will run the hooks on every commit. If you would like to run the hooks manually, run `pre-commit run --all-files` from the root of the repository.

### Requests

If you have any requests for additional features, please feel free to [open an issue](https://github.com/design-group/mssql-docker/issues/new/choose) or submit a pull request.

### Shoutout

A big shoutout to [Kevin Collins](https://github.com/thirdgen88) for the original inspiration and support for building this image.

