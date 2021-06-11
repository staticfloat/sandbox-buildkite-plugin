# sandbox-buildkite-plugin
> Launch sandboxed commands within user-specified rootfs images

## Dependencies

Requires `julia` to be installed, see [the `julia` buildkite plugin](https://github.com/JuliaCI/julia-buildkite-plugin) for more on automated installs.
We recommend running all buildkite agents within some kind of isolation sandbox, however if running inside of `Docker`, for this plugin to work, you must [set the container as `privileged`](https://docs.docker.com/engine/reference/run/#runtime-privilege-and-linux-capabilities).
We recommend running the buildkite agent inside of a non-docker sandbox for ease of sandbox nesting; see this repository for more information.

## Basic Usage

First, create a rootfs and host it as a tarball somewhere.  The [`Sandbox.jl` repository](https://github.com/staticfloat/Sandbox.jl) contains a few, we will use the Debian-based `julia` and `python3` rootfs as an example.

