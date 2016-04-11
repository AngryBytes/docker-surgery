#!/bin/bash
set -e

follow_link=""

function usage {
    echo "Usage: $0 [-L] <base image> <directory> <comment>" >& 2
    echo "Creates a new image with an extra commented layer" >& 2
    exit 64
}

while getopts "L" OPT; do
    case $OPT in
        L)
            follow_link="-L"
            ;;
        h|?)
            usage
            ;;
    esac
done
shift $(($OPTIND - 1))

if [ $# -ne 3 ]; then
    usage
fi

container=$(docker create "$1")
trap "docker rm ${container} > /dev/null" exit

# Seems like whatever we do, specifying a directory
# copies the directory, not its contents.
shopt -s nullglob dotglob
for entry in "$2"/*; do
  docker cp ${follow_link} "${entry}" ${container}:/
done

docker commit -m "$3" ${container}
