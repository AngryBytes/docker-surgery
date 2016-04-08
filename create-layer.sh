#!/bin/bash
set -e

if [ $# -ne 3 ]; then
    echo "Usage: $0 <base image> <directory> <comment>" >& 2
    echo "Creates a new image with an extra commented layer"
    exit 64
fi

container=$(docker create "$1")
trap "docker rm ${container} > /dev/null" exit

shopt -s dotglob
docker cp "$2"/* ${container}:/

docker commit -m "$3" ${container}
