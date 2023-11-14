variable "BASE_IMAGE_NAME" {
    default = "mssql-docker"
}

target "default" {
    name="${BASE_IMAGE_NAME}"
    context = "."
	matrix = {
		version = ["latest"]
	}
    dockerfile = "Dockerfile"
    platforms = [
		"linux/amd64", 
		"linux/arm64", 
		"linux/arm/v7",
 	]
	tags = [
		"ghcr.io/design-group/mssql-docker/${BASE_IMAGE_NAME}:${version}"
	]
}