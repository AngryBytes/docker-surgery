#!/usr/bin/env ruby

require 'securerandom'

CREATE_UTIL = File.join(__dir__, 'create-layer.sh')
STRIP_UTIL  = File.join(__dir__, 'strip-layers.rb')

FROM_RE = /^(\s*FROM\s*)([^\s#]+)/i

$verbose = !ARGV.any? { |arg| %w(-q --quiet).include? arg }

def system_verbose(*cmd)
    opts = {}
    opts[:out] = :close unless $verbose
    system(*cmd, opts) or exit 1
end

# Unique ID for our build.
build_id = SecureRandom.hex 8
build_args = ARGV.dup

# Get and remove the context directory from args.
ctx_dir = build_args.pop

# Get and remove `--secrets`.
secrets_opt_idx = build_args.index '--secrets'
if secrets_opt_idx.nil?
    abort "No secrets specified"
end
_, secrets_path = build_args.slice! secrets_opt_idx, 2

# Check `--secrets-follow-link`.
secrets_follow_link_opt = build_args.delete('--secrets-follow-link') and '-L'

# Get and remove the image tag.
tag_opt_idx = build_args.index { |arg| %w(-t --tag).include? arg }
if tag_opt_idx.nil?
    abort "No tag specified"
end
_, tag = build_args.slice! tag_opt_idx, 2

# Find the Dockerfile, remove the file option if used.
file_opt_idx = build_args.index { |arg| %w(-f --file).include? arg }
if file_opt_idx.nil?
    dockerfile_path = File.join(ctx_dir, 'Dockerfile')
else
    dockerfile_path = File.join(ctx_dir, build_args[file_opt_idx + 1])
    build_args.slice! file_opt_idx, 2
end

# Read the Dockerfile.
dockerfile = File.read(dockerfile_path)

# Get the base image from the Dockerfile.
unless FROM_RE =~ dockerfile
    abort "Could not find FROM in #{dockerfile_path}"
end
base_image = $~[2]

# Check if we need to pull.
unless want_pull = build_args.delete('--pull')
    want_pull = %x(docker images -q #{base_image}).empty?
    exit 1 if $? != 0
end
if want_pull
    system_verbose("docker pull #{base_image}")
end

# Create the secrets image.
puts "Creating base image with secrets" if $verbose
secrets_tag = "docker-surgery.invalid/secrets:#{build_id}"
secrets_image = %x(#{CREATE_UTIL} #{secrets_follow_link_opt} -t #{secrets_tag} #{base_image} #{secrets_path} SECRETS)
exit 1 if $? != 0
puts "Created #{secrets_image}" if $verbose
begin

    # Create the temporary Dockerfile.
    temp_dockerfile_name = ".Dockerfile.#{build_id}"
    temp_dockerfile_path = File.join(ctx_dir, temp_dockerfile_name)
    temp_dockerfile = dockerfile.sub(FROM_RE) { "#{$1}#{secrets_tag}" }
    File.write temp_dockerfile_path, temp_dockerfile
    begin

        # Add the temporary Dockerfile and tag to the build args.
        build_tag = "docker-surgery.invalid/build:#{build_id}"
        build_args += ['-f', temp_dockerfile_name, '-t', build_tag, ctx_dir]

        # Invoke the actual build.
        build_cmd = ['docker', 'build'] + build_args
        system_verbose(*build_cmd)
        begin

            # Recreate the image with secrets stripped.
            puts "Stripping image of secrets" if $verbose
            stripped_image = %x(#{STRIP_UTIL} #{build_tag} #{tag} SECRETS)
            exit 1 if $? != 0
            if $verbose
                puts "Created #{stripped_image}"
            else
                puts stripped_image
            end

        ensure
            system("docker rmi #{build_tag}", :out => :close) or exit 1
        end

    # Clean up temporary Dockerfile.
    ensure
        File.unlink temp_dockerfile_path
    end

# Clean up secrets image.
ensure
    system("docker rmi #{secrets_tag}", :out => :close) or exit 1
end
