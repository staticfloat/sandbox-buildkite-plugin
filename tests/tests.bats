#!/usr/bin/env bats

load "$BATS_PATH/load.bash"

# We always want verbose mode
export BUILDKITE_PLUGIN_SANDBOX_VERBOSE=true

@test "argument parsing" {
    # We need a rootfs URL
    run /plugin/hooks/pre-command
    assert_output --partial "Sandbox requires a rootfs tarball URL"
    assert_failure

    # We need a rootfs treehash
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_URL="https://github.com/staticfloat/Sandbox.jl/releases/download/julia-python3-77eae3ba/julia-python3.tar.gz"
    run /plugin/hooks/pre-command
    assert_output --partial "Sandbox requires a rootfs treehash"
    assert_failure

    # We need an actual treehash-like thing
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_TREEHASH="foo"
    run /plugin/hooks/pre-command
    assert_output --partial "Sandbox rootfs treehash not 40 hexadecimal characters"
    assert_failure
}

@test "bash wrapper" {
    dir="$(mktemp -d)"
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_URL="https://github.com/staticfloat/Sandbox.jl/releases/download/julia-python3-77eae3ba/julia-python3.tar.gz"
    export BUILDKITE_PLUGIN_SANDBOX_ROOTFS_TREEHASH="c0f2c53b857189e1c8378bd37c3b620ea4843e07"
    export BUILDKITE_PLUGIN_SANDBOX_SHELL="${dir}/bash"
    export BUILDKITE_BUILD_PATH="${dir}"

    # First, test out just plain printing
    run /plugin/hooks/pre-command
    assert_output --partial "--- Instantiating sandbox environment"
    assert_success

    [[ -f "${dir}/bash" ]]
    run "${dir}/bash" -c "echo hello world; echo foo > ${dir}/foo"
    assert_output --partial "hello world"
    assert_success
    [[ -f "${dir}/foo" ]]
    [[ "$(cat ${dir}/foo)" == "foo" ]]
}
