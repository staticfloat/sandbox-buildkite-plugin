using Pkg
using TOML

function registry_paths(; registry_name::String)
    registries_parent_dir = joinpath(Base.DEPOT_PATH[1], "registries")
    registry_dir          = joinpath(registries_parent_dir, registry_name)
    nounpack_tarball      = joinpath(registries_parent_dir, "$(registry_name).tar.gz")
    nounpack_toml         = joinpath(registries_parent_dir, "$(registry_name).toml")
    paths = (; registries_parent_dir, registry_dir, nounpack_tarball, nounpack_toml)
    return paths
end

function delete_registry_paths(; registry_name::String)
    paths = registry_paths(; registry_name)
    registry_dir     = paths.registry_dir
    nounpack_tarball = paths.nounpack_tarball
    nounpack_toml    = paths.nounpack_toml
    rm(registry_dir;     force = true, recursive = true)
    rm(nounpack_tarball; force = true, recursive = true)
    rm(nounpack_toml;    force = true, recursive = true)
    return nothing
end

function registry_exists_locally(registry_name::String = "General")
    paths = registry_paths(; registry_name)
    registries_parent_dir = paths.registries_parent_dir
    registry_dir          = paths.registry_dir
    nounpack_tarball      = paths.nounpack_tarball
    nounpack_toml         = paths.nounpack_toml

    if !isdir(registries_parent_dir)
        @info "No registries found locally"
        return false
    end

    # In this case, the registry is:
    # 1. From the Pkg server
    # 2. Not unpacked
    if isfile(nounpack_tarball) && isfile(nounpack_toml)
        msg = string(
            "The General registry exists locally in the form of a non-unpacked tarball.",
            "Please note: I did not verify the integrity of this tarball.",
        )
        @info msg
        # TODO: verify the integrity of the `$(registry_name).tar.gz" file
        return true
    end

    if !isdir(registry_dir)
        @info "Registry not found locally: $(registry_name)"
        return false
    end

    # In this case, the registry is:
    # 1. From the Pkg server
    # 2. Unpacked
    tree_info_file = joinpath(registry_dir, ".tree_info.toml")
    if isfile(tree_info_file)
        tree_info = TOML.parsefile(tree_info_file)
        expected_hash = Base.SHA1(tree_info["git-tree-sha1"])
        calculated_hash = Base.SHA1(Pkg.GitTools.tree_hash(registry_dir))
        if expected_hash.bytes == calculated_hash.bytes
            @info "Registry found locally: $(registry_name)"
            return true
        else
            @error "Hash mismatch" expected_hash calculated_hash
            return false
        end
    end

    # In this case, the registry is:
    # 1. Cloned from Git
    if isdir(joinpath(registry_dir, ".git"))
        isclean = isempty(strip(read(`git -C $(registry_dir) status --short`, String)))
        if isclean
            @info "Registry found locally: $(registry_name)"
            return true
        else
            msg = string(
                "The working directory is dirty. ",
                "See below for the output from `git status`:",
            )
            @error msg
            run(`bash -c "git -C $(registry_dir) status | head -n 50"`)
            run(`git -C $(registry_dir) log -n 1`)
            return false
        end
    end

    @info "Registry not found locally: $(registry_name)"
    return true
end

function ensure_registry_downloaded(; registry_name::String)
    if should_download_registry(; registry_name)
        delete_registry_paths(; registry_name)
        @info "Downloading registry: $(registry_name)"
        Pkg.Registry.add(registry_name)
    end
    return nothing
end

ensure_registry_downloaded(; registry_name = "General")
