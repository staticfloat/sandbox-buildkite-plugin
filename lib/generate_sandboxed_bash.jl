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

# Helper to map in a directory that is defined within an environment variable
# if that variable is set, and it's pointing to a real directory.
function add_env_dir!(dict, env_var; default=nothing)
    path = get(ENV, env_var, default)
    if path !== nothing && isdir(path)
        dict[path] = path
    end
    return dict
end

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
    workspace_mappings[sandbox_path] = abspath(host_path)
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