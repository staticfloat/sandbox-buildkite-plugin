include(joinpath(@__DIR__, "utils.jl"))

if Sys.which("buildkite-agent") === nothing
    throw(ErrorException("The `buildkite-agent` was not found in the path."))
end

upload_filenames = extract_env_array("BUILDKITE_PLUGIN_SANDBOX_ARTIFACTS_UPLOAD")

buildkite_download_dir_host = get_buildkite_upload_dir_host()
buildkite_upload_dir_host = get_buildkite_upload_dir_host()
mkpath(buildkite_download_dir_host)
mkpath(buildkite_upload_dir_host)

cd(buildkite_upload_dir_host) do
    root = pwd()
    for name in strip.(upload_filenames)
        full_path = joinpath(root, name)
        if isfile(full_path)
            run(`buildkite-agent artifact upload $(name)`)
        else
            @warn("File $(name) does not exist, so it will not be uploaded.")
        end
    end
end

rm(buildkite_download_dir_host; force = true, recursive = true)
rm(buildkite_upload_dir_host;   force = true, recursive = true)
if ispath(buildkite_download_dir_host)
    throw(ErrorException("Could not successfully erase: $(buildkite_download_dir_host)"))
end
if ispath(buildkite_upload_dir_host)
    throw(ErrorException("Could not successfully erase: $(buildkite_upload_dir_host)"))
end
