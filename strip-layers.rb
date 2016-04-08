#!/usr/bin/env ruby

require 'json'
require 'tmpdir'

if ARGV.length != 3
    STDERR.puts "Usage: #{$0} <base image> <new tag> <comment>"
    STDERR.puts "Create a new image with layers commented layers stripped"
    exit 64
end
image_id, tag, comment = ARGV

# Make sure the tag is complete.
tag += ':latest' unless tag.include? ':'

# Create a temporary directory to save the image in.
Dir.mktmpdir 'docker-surgery' do |image_dir|
    # Move to the directory image directory.
    Dir.chdir(image_dir) do
        # Save and unpack the image.
        system("docker save #{image_id} | tar -x") or exit 1

        # Drop legacy files.
        File.unlink(*(
            Dir['*/json'] + Dir['*/VERSION'] + Dir['repositories']
        ))

        # Read the manifest.
        manifests = File.open('manifest.json') { |f| JSON.load(f) }
        if manifests.length != 1
            abort "Expected one entry in image manifest"
        end
        manifest = manifests[0]

        # Read the config.
        config = File.open(manifest['Config']) { |f| JSON.load(f) }

        # Remove the layers we're not using.
        layers = []
        diff_ids = []
        history = config['history'].select do |h|
            keep = h['comment'] != comment

            unless h['empty_layer']
                layer_file = manifest['Layers'].shift
                diff_id = config['rootfs']['diff_ids'].shift
                if layer_file.nil? or diff_id.nil?
                    abort "Corrupt image"
                end

                if keep
                    layers.push layer_file
                    diff_ids.push diff_id
                else
                    # Also remove the layer file and directory.
                    File.unlink layer_file
                    if /^([0-9a-f]{64})\/layer\.tar$/ =~ layer_file
                        Dir.unlink $~[1]
                    end
                end
            end

            keep
        end

        # Verify we did things right.
        if manifest['Layers'].length > 0 || config['rootfs']['diff_ids'].length > 0
            abort "Corrupt image"
        end

        # Rewrite the files.
        manifest['RepoTags'] = [tag]
        manifest['Layers'] = layers
        config['rootfs']['diff_ids'] = diff_ids
        config['history'] = history

        File.open('manifest.json', 'w') { |f| JSON.dump(manifests, f) }
        File.open(manifest['Config'], 'w') { |f| JSON.dump(config, f) }

        # Pack and load the image.
        system("tar -c . | docker load") or exit 1
    end
end

# Output the image ID.
system("docker images -q #{tag}") or exit 1
