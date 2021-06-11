FROM julia:1.6-alpine as julia_container

FROM buildkite/plugin-tester
COPY --from=julia_container /usr/local/julia /usr/local/julia
RUN ln -s /usr/local/julia/bin/julia /usr/local/bin/julia
