#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# This is pretty ugly, but it works on macOS without requiring coreutils for GNU readlink
# Ideally this would be: SCRIPT=$( readlink -f ${BASH_SOURCE[0]} )
SCRIPT=$( cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd )/$( basename "${BASH_SOURCE[0]}" )
SCRIPTPATH=$( dirname "${SCRIPT}" )

# LibBPF headers version to download
LIBBPF_VERSION=${LIBBPF_VERSION:-1.7.0}

# The headers we want
prefix=libbpf-"$LIBBPF_VERSION"
headers=(
    "$prefix"/LICENSE.BSD-2-Clause
    "$prefix"/src/bpf_core_read.h
    "$prefix"/src/bpf_endian.h
    "$prefix"/src/bpf_helper_defs.h
    "$prefix"/src/bpf_helpers.h
    "$prefix"/src/bpf_tracing.h
)

OUTPUTDIR="${OUTPUTDIR:-"$SCRIPTPATH/../bpf/libbpf"}"
mkdir -p "${OUTPUTDIR}"

# dest_for maps a tarball path to its destination relative to OUTPUTDIR: the
# .h headers from src/ go under bpf/ (so sources #include <bpf/...>); anything
# else (the LICENSE) lands flat at the root.
function dest_for() {
    case "$1" in
        "$prefix"/src/*.h) echo "bpf/$( basename "$1" )" ;;
        *) basename "$1" ;;
    esac
}

# Check if we already have the current version and all files exist
function check_ok() {
    if [[ -f "$OUTPUTDIR/version" ]]; then
        version_ok=true
        files_ok=true

        current_version=$( cat "$OUTPUTDIR/version" )
        if [[ "$current_version" != "$LIBBPF_VERSION" ]]; then
            version_ok=false
        fi

        for f in "${headers[@]}"; do
            if [[ ! -f "$OUTPUTDIR/$( dest_for "$f" )" ]]; then
                files_ok=false
                break
            fi
        done

        if [[ "$version_ok" == true && "$files_ok" == true ]]; then
            echo "libbpf headers are up to date v${LIBBPF_VERSION}"
            exit 0
        fi
    fi
}

check_ok

echo "Downloading and updating libbpf headers (libbpf v${LIBBPF_VERSION})"

# Fetch libbpf release and extract the desired headers.
# Extract into a temp dir and copy the files flat, since tar's path-rewriting
# flags differ between GNU (--xform) and BSD (-s) tar.
tmpdir=$( mktemp -d )
trap 'rm -rf "$tmpdir"' EXIT

curl -sL "https://github.com/libbpf/libbpf/archive/refs/tags/v${LIBBPF_VERSION}.tar.gz" | \
    tar -xz -C "${tmpdir}" "${headers[@]}"

for f in "${headers[@]}"; do
    dest="${OUTPUTDIR}/$( dest_for "${f}" )"
    mkdir -p "$( dirname "${dest}" )"
    cp "${tmpdir}/${f}" "${dest}"
done

# The headers are vendored verbatim: with the .h files under bpf/ and
# -I<libbpf_dir> on the compile line, libbpf's own #include <bpf/...> lines
# resolve as-is, so no include rewriting is needed.

# Touch version file
echo "$LIBBPF_VERSION" > "${OUTPUTDIR}/version"
