#!/usr/bin/env julia
using Pkg, Sandbox

# Helper to extract buildkite environment arrays
function extract_env_array(prefix::String)
    envname(idx::Int) = string("BUILDKITE_PLUGIN_SANDBOX_", prefix, "_", idx)
    idx = 0
    array = String[]
    while haskey(ENV, envname(idx))
        push!(array, ENV[envname(idx)])
        idx += 1
    end
    return array
end

function buildkite_warn(message::String)
    @warn(message)
    if Sys.which("buildkite-agent") !== nothing
        run(`buildkite-agent annotate --style=warning "$(message)"`)
    end
end

# Parse out everything passed to us via the environment
rootfs_url = ENV["BUILDKITE_PLUGIN_SANDBOX_ROOTFS_URL"]
rootfs_treehash = Base.SHA1(ENV["BUILDKITE_PLUGIN_SANDBOX_ROOTFS_TREEHASH"])
command = ENV["BUILDKITE_COMMAND"]
env_file = ENV["BUILDKITE_ENV_FILE"]
verbose = parse(Bool, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_VERBOSE", "false"))
inherit_environment = parse(Bool, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_INHERIT_ENVIRONMENT", "true"))
extra_envs = extract_env_array("EXTRA_ENVIRONMENT")
workspaces = [reverse(split(pair, ":")) for pair in extract_env_array("WORKSPACES")]
uid = parse(Int, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_UID", string(Sandbox.getuid())))
gid = parse(Int, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_GID", string(Sandbox.getgid())))

# First, download the rootfs
if !Pkg.Artifacts.artifact_exists(rootfs_treehash)
    println("--- Downloading rootfs")
    Pkg.Artifacts.download_artifact(rootfs_treehash, rootfs_url, nothing; verbose)
end

# Extract environment values set in our pipeline, unless inherit_environment is not set
env_mappings = Dict{String,String}()
if inherit_environment
    for pair in readlines(env_file)
        key, value = split(pair, "=")
        env_mappings[key] = value
    end
end

# Also add in any extra environment variables requested
for e in extra_envs
    if haskey(ENV, e)
        env_mappings[e] = ENV[e]
    else
        buildkite_warn("Requested propagation of environment variable '$(e)' but it does not exist!")
    end
end

config = SandboxConfig(
    # The only read-only mapping we mount is the rootfs we previously downloaded as an artifact
    Dict("/" => Pkg.Artifacts.artifact_path(rootfs_treehash)),
    # The read-write mappings are provided as the workspaces arguments
    Dict{String,String}(workspaces),
    # Our environment mappings
    env_mappings;
    verbose,
    uid,
    gid,
)
with_executor() do exe
    run(exe, config, `/bin/bash -c "$command"`)
end
