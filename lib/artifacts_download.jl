include(joinpath(@__DIR__, "utils.jl"))

if Sys.which("buildkite-agent") === nothing
    throw(ErrorException("The `buildkite-agent` was not found in the path."))
end

download_filenames = extract_env_array("BUILDKITE_PLUGIN_SANDBOX_ARTIFACTS_DOWNLOAD")

buildkite_download_dir_host = get_download_dir_host()
buildkite_upload_dir_host   = get_upload_dir_host()
rm(buildkite_download_dir_host; force = true, recursive = true)
rm(buildkite_upload_dir_host;   force = true, recursive = true)
if ispath(buildkite_download_dir_host)
    throw(ErrorException("Could not successfully erase: $(buildkite_download_dir_host)"))
end
if ispath(buildkite_upload_dir_host)
    throw(ErrorException("Could not successfully erase: $(buildkite_upload_dir_host)"))
end
mkpath(buildkite_download_dir_host)
mkpath(buildkite_upload_dir_host)

cd(buildkite_download_dir_host) do
    for name in strip.(download_filenames)
        run(`buildkite-agent artifact download $(name) .`)
    end
end
