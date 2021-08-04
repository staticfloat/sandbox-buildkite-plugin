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

get_download_dir_guest() = "/buildkite-download/"
get_upload_dir_guest()   = "/buildkite-upload/"

function get_download_dir_host()
    return string(
        "/tmp/buildkite-download/",
        ENV["BUILDKITE_BUILD_NUMBER"], "_",
        ENV["BUILDKITE_STEP_ID"],
    )
end

function get_upload_dir_host()
    return string(
        "/tmp/buildkite-upload/",
        ENV["BUILDKITE_BUILD_NUMBER"], "_",
        ENV["BUILDKITE_STEP_ID"],
    )
end
