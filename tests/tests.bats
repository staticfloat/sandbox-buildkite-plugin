#!/usr/bin/env bats

load "$BATS_PATH/load.bash"

# We always want verbose mode
export BUILDKITE_PLUGIN_SANDBOX_VERBOSE=true

@test "argument parsing" {
    # We need a user command
    run /plugin/hooks/command
    assert_output --partial "Sandbox requires a user command"
    assert_failure

    # We need a rootfs URL
    export BUILDKITE_COMMAND="echo Hello World"
    run /plugin/hooks/command
    assert_output --partial "Sandbox requires a rootfs tarball URL"
    assert_failure

    # We need a rootfs treehash
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_URL="https://github.com/staticfloat/Sandbox.jl/releases/download/julia-python3-77eae3ba/julia-python3.tar.gz"
    run /plugin/hooks/command
    assert_output --partial "Sandbox requires a rootfs treehash"
    assert_failure

    # We need an actual treehash-like thing
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_TREEHASH="foo"
    run /plugin/hooks/command
    assert_output --partial "Sandbox rootfs treehash not 40 hexadecimal characters"
    assert_failure
}

@test "launch.jl" {
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_URL="https://github.com/staticfloat/Sandbox.jl/releases/download/julia-python3-77eae3ba/julia-python3.tar.gz"
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_TREEHASH="c0f2c53b857189e1c8378bd37c3b620ea4843e07"
    export BUILDKITE_COMMAND="echo Hello World"
    export BUILDKITE_ENV_FILE="/dev/null"

    # First, test out just plain printing
    run /plugin/hooks/command
    assert_output --partial "--- Instantiating sandbox environment"
    assert_output --partial "+++ Running user command (within provided rootfs)"
    assert_output --partial "Hello World"
    assert_success

    # Next, workspace some stuff in, add some environment variables, etc...
    dir="$(mktemp -d)"
    pushd "${dir}"
    mkdir -p "${dir}/mount1" "${dir}/mount2"
    echo "the contents of bar.txt" > "${dir}/mount2/bar.txt"
    echo "MSG=bar"   >> "${dir}/env"
    echo "BAZ=spoon" >> "${dir}/env"

    export BUILDKITE_COMMAND='echo ${MSG} ${BAZ} ${QUX} > /tmp/mount1/foo.txt; cat /tmp/mount2/bar.txt'
    export BUILDKITE_ENV_FILE="${dir}/env"
    export BUILDKITE_PLUGIN_SANDBOX_WORKSPACES_0="${dir}/mount1:/tmp/mount1"
    export BUILDKITE_PLUGIN_SANDBOX_WORKSPACES_1="./mount2:/tmp/mount2"
    export BUILDKITE_PLUGIN_SANDBOX_EXTRA_ENVIRONMENT_0="QUX"
    export QUX=yolo

    run /plugin/hooks/command
    assert_output --partial "--- Instantiating sandbox environment"
    refute_output --partial "--- Downloading rootfs"
    assert_output --partial "+++ Running user command (within provided rootfs)"
    assert_output --partial "the contents of bar.txt"
    assert_success

    [[ -f "${dir}/mount1/foo.txt" ]]
    [[ "$(cat "${dir}/mount1/foo.txt")" == "bar spoon yolo" ]]
    popd
    rm -rf "${dir}"
}
