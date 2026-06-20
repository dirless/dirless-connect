# dirless-connect — build, test, and install recipes
#
# Prerequisites: just, crystal >= 1.20.0
# See `just --list` for available recipes.

ncpus := `nproc`

release_flags := "--release --no-debug"

bin_dir := "bin"

# List available recipes
default:
    @just --list

# Build debug binary
build:
    @mkdir -p {{bin_dir}}
    crystal build src/dirless_connect.cr -o {{bin_dir}}/dirless-connect

# Build release binary
build-release:
    @mkdir -p {{bin_dir}}
    crystal build src/dirless_connect.cr -o {{bin_dir}}/dirless-connect {{release_flags}} --threads {{ncpus}}
    strip {{bin_dir}}/dirless-connect

# Build portable static binary via Docker (Alpine/musl)
build-static:
    @mkdir -p {{bin_dir}}
    docker build --platform linux/amd64 -t dirless-builder ../../dirless-infra/scripts/
    docker run --rm --platform linux/amd64 \
        -v "$PWD":/src \
        -w /src \
        dirless-builder \
        sh -c "shards install && crystal build src/dirless_connect.cr -o {{bin_dir}}/dirless-connect --release --no-debug --static --threads $(nproc)"
    strip {{bin_dir}}/dirless-connect

# Run specs
spec:
    crystal spec --order random --threads {{ncpus}}

# Type-check without producing a binary
check:
    crystal build --no-codegen src/dirless_connect.cr

# Run linter
lint:
    crystal tool format --check src/ spec/
    @command -v ameba >/dev/null 2>&1 && ameba src/ || echo "ameba not installed — skipping"

# Format source files
fmt:
    crystal tool format src/ spec/

# Install binary to /usr/local/bin (requires sudo)
install: build-release
    sudo install -m 755 {{bin_dir}}/dirless-connect /usr/local/bin/dirless-connect

# Remove built binary
clean:
    @rm -f {{bin_dir}}/dirless-connect
