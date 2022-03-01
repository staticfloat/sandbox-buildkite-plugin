# sandbox-buildkite-plugin
> Launch sandboxed commands within user-specified rootfs images

## Dependencies

Requires `julia` to be installed, see [the `julia` buildkite plugin](https://github.com/JuliaCI/julia-buildkite-plugin) for more on automated installs.
We recommend running all buildkite agents within some kind of isolation sandbox, however if running inside of `Docker`, for this plugin to work, you must [set the container as `privileged`](https://docs.docker.com/engine/reference/run/#runtime-privilege-and-linux-capabilities).
We recommend running the buildkite agent inside of a non-docker sandbox for ease of sandbox nesting; see this repository for more information.

## Usage

The purpose of this package is to allow users to pre-create a rootfs that contains their needed packages, then launch test suites, CI jobs, etc.. within that environment so that they do not have to continually `apt intsall` all of their dependencies within every step of their build pipelines.

First, create a rootfs and host it as a tarball somewhere.  The [`Sandbox.jl` repository](https://github.com/staticfloat/Sandbox.jl) contains a few, we will use a minimal debian rootfs as an example.

```yaml
steps:
  - label: "run code within a sandbox"
    plugins:
      # Install Julia v1.6+ to run sandbox
      - JuliaCI/julia#v1:
          version: 1.6
      - staticfloat/sandbox:
          rootfs_url: "https://github.com/staticfloat/Sandbox.jl/releases/download/debian-minimal-927c9e7f/debian_minimal.tar.gz"
          rootfs_treehash: "5b44fab874ec426cad9b80b7dffd2b3f927c9e7f"
    commands: |
      echo "this is running in a sandbox!"
```

The sandbox automatically gets access to a few host directories, such as the current repository checkout, the buildkite plugins directory, etc...
Most Julia users will want to do something like launch their julia tests within an environment that has, e.g. `pdflatex` available.
To do so, they would first create a rootfs, perhaps by building a `Dockerfile` with the following contents (these snippets adapted from [the `docker_build_example` in `Sandbox.jl`](https://github.com/staticfloat/Sandbox.jl/tree/main/contrib/docker_build_example)):

```Dockerfile
# Our base image will be debian
FROM debian

# Install some useful tools
RUN apt update && apt install -y curl python3 texlive-full
```

They would then build it via `docker build -t texlive_rootfs .`.
Once it is finished building, it can be flattened into an artifact using `Sandbox.export_docker_image()`:

```julia
using Pkg.Artifacts, Sandbox
artifact_hash = create_artifact() do dir
    Sandbox.export_docker_image("texlive_rootfs", dir; verbose=true)
end
@info("docker export complete, artifact hash: $(bytes2hex(artifact_hash))")
```

This artifact can then be packaged into a tarball and uploaded somewhere:
```julia
archive_artifact(artifact_hash, "/tmp/texlive_rootfs.tar.gz")
```

Note that `texlive-full` is quite large, and will generate a large artifact that will take quite a while to export and upload.
Once the archived artifact is uploaded somewhere (such as an S3 bucket, or a github release), it is usable as a rootfs by listing its URL and treehash.

For users that want to test on a variety of Julia versions (even those that are incompatible with `Sandbox.jl` itself; e.g. Julia v1.5 and earlier) pipelines will need to install Julia v1.6 first, and then within the sandbox, install the desired version of Julia.
Note that all plugins after `sandbox` will magically be running inside of the sandbox itself, so Julia installation/testing of Julia packages etc.. can all happen from within the sandbox.
We give here an example, using the `texlive-full` rootfs built in the previous steps, and running a different version of Julia from within the rootfs than is used on the outside to install `sandbox`:

```yaml
steps:
  - label: "run tests within a sandbox"
    plugins:
      # Install Julia v1.6 to run Sandbox.jl
      - JuliaCI/julia#v1:
          version: 1.6
      - staticfloat/sandbox:
          rootfs_url: "https://julialang-buildkite.s3.amazonaws.com/rootfs_images/texlive_rootfs.tar.gz"
          rootfs_treehash: "4748ee25bcb689727fb642eea56fd10c840d5094"
          workspaces:
            # Include `/cache` so that `julia` install can properly cache its Julia downloads
            - "/cache:/cache"
      # Once inside the sandbox, install a different version of Julia to run our tests
      - JuliaCI/julia#v1:
          version: 1.7
          update_registry: false
      - JuliaCI/julia-test#v1: ~
```
