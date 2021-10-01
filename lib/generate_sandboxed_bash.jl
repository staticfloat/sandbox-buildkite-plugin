#!/usr/bin/env julia
using Pkg, Sandbox

# Helper to extract buildkite environment arrays
function extract_env_array(prefix::String)
    envname(idx::Int) = string(prefix, "_", idx)
    idx = 0
    array = String[]
    while haskey(ENV, envname(idx))
        push!(array, ENV[envname(idx)])
        idx += 1
    end
    return array
end

rootfs_url = ENV["BUILDKITE_PLUGIN_SANDBOX_ROOTFS_URL"]
rootfs_treehash = Base.SHA1(ENV["BUILDKITE_PLUGIN_SANDBOX_ROOTFS_TREEHASH"])
verbose = parse(Bool, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_VERBOSE", "false"))
workspaces = [reverse(split(pair, ":")) for pair in extract_env_array("BUILDKITE_PLUGIN_SANDBOX_WORKSPACES")]
uid = parse(Int, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_UID", string(Sandbox.getuid())))
gid = parse(Int, get(ENV, "BUILDKITE_PLUGIN_SANDBOX_GID", string(Sandbox.getgid())))

# Might as well ensure that the artifact exists now
if !Pkg.Artifacts.artifact_exists(rootfs_treehash)
    println("--- Downloading rootfs");
    Pkg.Artifacts.download_artifact(rootfs_treehash, rootfs_url, nothing; verbose);
end

# Double-check that this actually downloaded properly, as a 404 can silently fail!
if !Pkg.Artifacts.artifact_exists(rootfs_treehash)
    @error("Unable to download rootfs!", treehash=bytes2hex(rootfs_treehash), url=rootfs_url)
    run(`buildkite-agent annotate --style=error --context=$(bytes2hex(rootfs_treehash)) "Unable to download rootfs from '$(rootfs_url)'"`)
    exit(1)
end

# Create an Artifacts.toml file pointing to this rootfs treehash.
# The file itself will be deleted after this pipeline finishes, but
# depending on the `collect_delay` set in the pipeline, it may stay
# around for a while.  This works because `bind_artifact!()` internally
# writes into `artifact_usage.toml` in our depot, which informs `gc()`.
temp_artifact_toml = joinpath(mktempdir(prefix="sandbox-buildkite-plugin-", cleanup=false), "Artifacts.toml")
Pkg.Artifacts.bind_artifact!(temp_artifact_toml, "rootfs", rootfs_treehash)

# Helper to map in a directory that is defined within an environment variable
# if that variable is set, and it's pointing to a real directory.
function add_env_dir!(dict, env_var; default=nothing)
    path = get(ENV, env_var, default)
    if path !== nothing && isdir(path)
        dict[path] = path
    end
    return dict
end

# Super-simple environment expansion
envexpand(s::AbstractString) = replace(s, r"\${[a-zA-Z0-9_]+}" => m -> get(ENV, m[3:end-1], m))


# read-write mount mappings
workspace_mappings = Dict{String,String}()

# Always mount the build directory in, we need that
add_env_dir!(workspace_mappings, "BUILDKITE_BUILD_PATH")

# Add in the plugins path, since we may want to run plugins within the sandbox
add_env_dir!(workspace_mappings, "BUILDKITE_PLUGINS_PATH")

# `/tmp` always gets mounted in, since buildkite writes hook wrappers out there!
add_env_dir!(workspace_mappings, "TMPDIR"; default="/tmp")

# Add user-specified workspaces (note they must all be absolute paths)
for (sandbox_path, host_path) in workspaces
    # Also perform ENV-expansion.  Note that to make parsing easier, we
    # only support `${FOO}` style expansion, not `$FOO` style.
    workspace_mappings[envexpand(sandbox_path)] = abspath(envexpand(host_path))
end



# Read-only mounts that we'll scatter throughout the build image
read_only_mappings = Dict{String,String}(
    # the rootfs we previously downloaded as an artifact
    "/" => Pkg.Artifacts.artifact_path(rootfs_treehash),
)

# The path to `buildkite-agent`, if it exists
# Note that it's kosher to mount a single executable in like this since it's a
# `go` executable that is completely self-contained (statically linked, etc...)
buildkite_agent_path = Sys.which("buildkite-agent")
if buildkite_agent_path !== nothing
    read_only_mappings["/usr/bin/buildkite-agent"] = buildkite_agent_path
end

# If we have a `resolv.conf` to share, do so
if isfile("/etc/resolv.conf")
    read_only_mappings["/etc/resolv.conf"] = "/etc/resolv.conf"
end

# Build config, get executor command (with all our options embedded within it) and
# use that to generate out a `bash` replacement.
config = SandboxConfig(
    read_only_mappings,
    workspace_mappings;
    pwd=pwd(),
    verbose,
    uid,
    gid,
    persist=true,
)

exe = UnprivilegedUserNamespacesExecutor()
c = Sandbox.build_executor_command(exe, config, ``)
# Write out `/bin/bash` wrapper script that just invokes our `sandbox` executable.
open(ARGS[1], write=true) do io
    println(io, """
    #!/bin/truebash

    # Don't sandbox `sandbox-buildkite-plugin` itself
    if [[ "\${BUILDKITE_PLUGIN_NAME}" == "SANDBOX" ]]; then
        exec /bin/truebash "\$@"
    fi

    # Ensure that PATH contains the bare minimum that any sane rootfs might need
    export PATH="\${PATH}:/usr/local/bin:/usr/bin:/bin"

    # Sandbox invocation
    $(join(c.exec, " ")) /bin/bash "\$@"
    """)
end
chmod(ARGS[1], 0o755)
