# docker-bake.hcl

group "build" {
	targets = [
		"mssql-base"
	]
}

variable "BASE_IMAGE_NAME" {
    default = "bwdesigngroup/mssql-docker"
}


// ###########################################################################################
//  Current Imaages
// ###########################################################################################

target "mssql-base" {
	context = "."
	args = {}
	platforms = [
		"linux/amd64", 
		"linux/arm64"
	]
	tags = [
		"${BASE_IMAGE_NAME}"
	]
}