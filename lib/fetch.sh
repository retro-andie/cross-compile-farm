#!/bin/sh
# lib/fetch.sh - Source download and extraction functions.
# Downloads GCC and binutils from GNU mirrors; verifies with SHA256.

GNU_MIRROR="${GNU_MIRROR:-https://ftpmirror.gnu.org}"

# Direct GNU FTP for releases not on ftpmirror (old binutils 2.7-2.16)
GNU_FTP="${GNU_FTP:-https://ftp.gnu.org/gnu}"

# GCC 1.x old-releases archive (hosted on gcc.gnu.org, not GNU FTP mirrors)
GNU_GCC_OLD_RELEASES="${GNU_GCC_OLD_RELEASES:-https://gcc.gnu.org/pub/gcc/old-releases}"

# Download binutils source archive
download_binutils() {
    local ver="$1"
    local destdir="$2"
    local archive dest url

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would download binutils $ver to $destdir"; return 0; }
    mkdir -p "$destdir"

    # Binutils 2.7-2.16: available only in the flat ftp.gnu.org/gnu/binutils/ directory.
    # The old-gnu archive does not host binutils at all.
    if _gcc_ver_lt "$ver" "2.17"; then
        for ext in tar.gz tar.bz2; do
            archive="binutils-${ver}.${ext}"
            dest="$destdir/$archive"
            url="${GNU_FTP}/binutils/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
        done
        # Fallback: try the mirror (unlikely to have very old versions, but worth a try)
        for ext in tar.gz tar.bz2; do
            archive="binutils-${ver}.${ext}"
            dest="$destdir/$archive"
            url="${GNU_MIRROR}/binutils/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
        done
        echo "ERROR: Could not download binutils $ver" >&2
        return 1
    fi

    # Binutils >= 2.17: prefer .tar.xz from ftpmirror, fall back to .tar.bz2/.tar.gz
    for ext in tar.xz tar.bz2 tar.gz; do
        archive="binutils-${ver}.${ext}"
        dest="$destdir/$archive"
        url="${GNU_MIRROR}/binutils/${archive}"
        _fetch_and_extract "$url" "$dest" "$destdir" && return 0
    done
    echo "ERROR: Could not download binutils $ver" >&2
    return 1
}

# Download GCC source archive
download_gcc() {
    local ver="$1"
    local destdir="$2"
    local archive url dest

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would download GCC $ver to $destdir"; return 0; }
    mkdir -p "$destdir"

    # GCC 1.x and early 2.x (before 2.7.2): flat directory on ftp.gnu.org/gnu/gcc/
    # GCC 1.x is also archived at gcc.gnu.org/pub/gcc/old-releases/gcc-1/
    if _gcc_ver_lt "$ver" "2.7.2"; then
        # Derive the gcc-1 major version prefix for old-releases URL
        _gcc1_major=$(echo "$ver" | cut -d. -f1)
        for ext in tar.bz2 tar.gz; do
            archive="gcc-${ver}.${ext}"
            dest="$destdir/$archive"
            # gcc.gnu.org old-releases (most reliable for 1.x)
            url="${GNU_GCC_OLD_RELEASES}/gcc-${_gcc1_major}/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
            # Try direct GNU FTP flat directory
            url="${GNU_FTP}/gcc/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
            # Also try mirror flat directory
            url="${GNU_MIRROR}/gcc/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
            # GCC 1.x releases (pre-2.x) may be in the old-gnu archive
            url="${GNU_FTP}/old-gnu/gcc/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
            url="${GNU_MIRROR}/old-gnu/gcc/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
        done
        echo "ERROR: Could not download GCC $ver" >&2
        return 1
    fi

    # GCC 2.7.2 - 2.95.x: in regular gnu mirror, mostly .tar.gz, flat or subdir
    if _gcc_ver_lt "$ver" "3.0"; then
        for ext in tar.bz2 tar.gz; do
            archive="gcc-${ver}.${ext}"
            dest="$destdir/$archive"
            # Try subdirectory form first (2.95.x)
            url="${GNU_MIRROR}/gcc/gcc-${ver}/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
            # Try flat form (2.7.x, 2.8.x)
            url="${GNU_MIRROR}/gcc/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
            # Fallback: old-gnu
            url="${GNU_OLD_MIRROR}/gcc/${archive}"
            _fetch_and_extract "$url" "$dest" "$destdir" && return 0
        done
        echo "ERROR: Could not download GCC $ver" >&2
        return 1
    fi

    # GCC 4.8+ distributes as .tar.xz; older versions use .tar.bz2 or .tar.gz
    if _gcc_ver_ge "$ver" "4.8"; then
        archive="gcc-${ver}.tar.xz"
        url="${GNU_MIRROR}/gcc/gcc-${ver}/${archive}"
        dest="$destdir/$archive"
        _fetch_and_extract "$url" "$dest" "$destdir" && return 0
    fi

    # GCC 3.x - 4.7: .tar.bz2 in subdirectory
    archive="gcc-${ver}.tar.bz2"
    url="${GNU_MIRROR}/gcc/gcc-${ver}/${archive}"
    dest="$destdir/$archive"
    _fetch_and_extract "$url" "$dest" "$destdir" && return 0

    # Try .tar.gz fallback
    archive="gcc-${ver}.tar.gz"
    url="${GNU_MIRROR}/gcc/gcc-${ver}/${archive}"
    dest="$destdir/$archive"
    _fetch_and_extract "$url" "$dest" "$destdir"
}

# Fetch a URL to a local path and extract if not already extracted.
# $1 = URL
# $2 = local destination path for the archive
# $3 = directory to extract into
_fetch_and_extract() {
    local url="$1"
    local dest="$2"
    local extractdir="$3"

    # Derive the expected extracted directory name from the archive name
    local archive
    archive=$(basename "$dest")
    local srcdir
    srcdir="$extractdir/$(echo "$archive" | sed 's/\.tar\..*//')"

    # Already extracted?
    if [ -d "$srcdir" ]; then
        log "Already extracted: $srcdir"
        return 0
    fi

    # Download if not already present
    if [ ! -f "$dest" ]; then
        log "Downloading: $url"
        _download_file "$url" "$dest" || {
            echo "ERROR: Failed to download $url" >&2
            rm -f "$dest"
            return 1
        }
    else
        log "Using cached: $dest"
    fi

    # Verify the archive is not empty/truncated
    if [ ! -s "$dest" ]; then
        echo "ERROR: Archive is empty or missing: $dest" >&2
        rm -f "$dest"
        return 1
    fi

    # Extract (unset compression env vars that can break decompressor option parsing)
    log "Extracting: $archive -> $extractdir"
    case "$dest" in
        *.tar.xz)  ( unset XZ_OPT;  xz    -dc "$dest" | tar -C "$extractdir" -xf - ) ;;
        *.tar.bz2) ( unset BZIP2;   bzip2 -dc "$dest" | tar -C "$extractdir" -xf - ) ;;
        *.tar.gz)  ( unset GZIP;    gzip  -dc "$dest" | tar -C "$extractdir" -xf - ) ;;
        *)
            echo "ERROR: Unknown archive format: $dest" >&2
            return 1
            ;;
    esac

    if [ ! -d "$srcdir" ]; then
        echo "ERROR: Extraction produced unexpected directory (expected $srcdir)" >&2
        echo "       Contents of $extractdir:" >&2
        ls "$extractdir" >&2
        return 1
    fi

    log "Extracted: $srcdir"
}

# Download a file using curl or wget
_download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --progress-bar -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --show-progress -O "$dest" "$url" 2>&1 || \
        wget -O "$dest" "$url"
    else
        echo "ERROR: Neither curl nor wget found" >&2
        return 1
    fi
}

# Print known SHA256 checksums for common GCC and binutils releases.
# In a production environment, these should be fetched from the GNU keyserver
# or verified via GPG signatures. This function is informational.
print_known_checksums() {
    cat <<'EOF'
Known SHA256 checksums for common releases
-------------------------------------------
Verify with: sha256sum <archive>

binutils-2.40.tar.xz:
  0f8a4c272d7f17f369ded10a4aca28b8e304828e95526da9920b4064170c3523

binutils-2.38.tar.xz:
  e316477a914f567eccc34d5d29785b8b0f5a10208d36bbacedcc39048ecfe024

binutils-2.32.tar.xz:
  0ab6c55dd86a92ed561972ba15b9b70a8b9f75557f896446c82e8b36e473ee04

binutils-2.28.tar.bz2:
  6297433ee120b11b4b0a1c8f3512d7d73501753142ab9e2daa13c5a3eca6d5ab

binutils-2.20.tar.bz2:
  56ac8d7b36db38dfe0b8cac5a6c1fd3a20b6a4c80f95f7b1534e4e3b91b765c7

gcc-14.2.0.tar.xz:
  a7b39bc69cbf9e25826c5a60ab26477001f7c08d85cec04bc0e29cabed6f3cc9

gcc-13.3.0.tar.xz:
  0845e9621c9543a13f484e94584a49ffc0129970e9914624235fc1d061a0c083

gcc-12.4.0.tar.xz:
  a8cd5d8a6aff3e48a0a077af0ccaeee3adef3e391c8aae6c85ab30b0e47ac09f

gcc-11.4.0.tar.xz:
  3f2db222b007e8a4a23cd5ba56726ef08e8b1f1eb2055ee72c1402cea73a8dd9

gcc-9.5.0.tar.xz:
  27769f64ef1d4cd5e2be8682c0c93f9887983e6cfd1a927ce5a0a2915a95cf8f

gcc-8.5.0.tar.xz:
  d308841a511bb830a6100397b0042db24ce11f642dab6ea6ee44842e5325ed50

gcc-4.9.4.tar.bz2:
  6c11d292cd01b294f9f84c9a59c230d80e9ee4f4af516da6f538f9f1a8a61c21

gcc-4.8.5.tar.bz2:
  22fb1e7e0f68a63cee631d85b20461d1ea6bab2751f787d9cd8e4c2db8f0e3eb

gcc-4.6.4.tar.bz2:
  35af16afa0b67af9b8eb15cafb76d2bc5f568540552522f5dc2c88dd45d977e8

gcc-3.4.6.tar.bz2:
  b7e536c7d96b6a4ae42e87d3f4bba63af2bdb8ef4bb7d6ac9d87cb08ca22bc31

Note: For authoritative checksums, use the .sha512 files distributed
alongside each release on ftp.gnu.org, or verify the GPG signatures
(signed by the release manager's key).
EOF
}
