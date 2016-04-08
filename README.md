# docker-surgery

These are tools to perform some low-level hacky operations on docker images.

## build-with-secrets.rb

Wraps `docker build` and takes the same parameters, but adds a filesystem
overlay only available during the build.

The parameters are the same as Docker build, with the following differences:

 - The context directory can only be specified as a path. URLs and STDIN are
   not supported.

 - Supplying a tag (`-t` or `--tag`) is required.

 - An extra option `--secrets` specifies the filesystem overlay directory to
   add to the build environment.

## create-layer.sh

Usage: `create-layer.sh <base image> <directory> <comment>`

Creates a new image from the given base image, with an additional layer added.

The layer contents will be that of the given directory, which should contain a
filesystem overlay. The layer will have the given comment.

Outputs the new image ID.

## strip-layers.sh

Usage: `strip-layers.rb <base image> <new tag> <comment>`

Creates a new image from the given base image with certain layers stripped.

The new image with have the given tag. Layers that are stripped are selected by
the given comment.

Outputs the new image ID.
