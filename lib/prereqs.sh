#!/bin/sh
# lib/prereqs.sh - Host prerequisite checking and GCC prerequisite handling.
# GCC 4.3+ requires GMP, MPFR, and MPC. GCC 4.8+ optionally uses ISL.
# This library checks for host tools and manages those prerequisites.

# Versions of GCC prerequisites to download if not found on the system
GMP_VERSION="${GMP_VERSION:-6.3.0}"
MPFR_VERSION="${MPFR_VERSION:-4.2.1}"
MPC_VERSION="${MPC_VERSION:-1.3.1}"
ISL_VERSION="${ISL_VERSION:-0.26}"

# ---------------------------------------------------------------------------
# GNU make detection
# On BSD systems 'make' is BSD make; GNU make is required for GCC/binutils.
# Honor a caller-set MAKE; otherwise probe gmake, gnumake, then make.
# ---------------------------------------------------------------------------
# _have_cmd: check if a command exists without relying on /dev/null.
# Works when /dev/null is missing or not writable (e.g. on old/damaged hosts).
_have_cmd() { case "$(command -v "$1" 2>&1)" in /*) return 0 ;; *) return 1 ;; esac; }

if [ -z "${MAKE:-}" ]; then
    if _have_cmd gmake && gmake --version 2>&1 | grep -q 'GNU Make'; then
        MAKE=gmake
    elif _have_cmd gnumake && gnumake --version 2>&1 | grep -q 'GNU Make'; then
        MAKE=gnumake
    elif make --version 2>&1 | grep -q 'GNU Make'; then
        MAKE=make
    else
        MAKE=make  # Last resort; build will fail with a clear error
    fi
    export MAKE
fi

# Minimum GMP/MPFR/MPC versions by GCC version range
# GCC 4.3-4.5: GMP>=4.3.2, MPFR>=2.4.2
# GCC 4.5-4.8: GMP>=4.3.2, MPFR>=2.4.2, MPC>=0.8.1
# GCC 4.8+:    GMP>=5.1.3, MPFR>=3.1.0, MPC>=1.0.1, ISL>=0.15 (optional)

check_prereqs() {
    local gcc_ver="$1"
    local errors=0

    log "Checking host prerequisites..."

    # GNU make — required for GCC/binutils source builds
    if ! _have_cmd "${MAKE:-make}"; then
        echo "ERROR: GNU make not found (MAKE=${MAKE:-make})" >&2
        errors=$((errors + 1))
    elif ! "${MAKE:-make}" --version 2>&1 | grep -q 'GNU Make'; then
        echo "ERROR: '${MAKE:-make}' is not GNU make; GCC/binutils require GNU make" >&2
        echo "       Install GNU make (e.g., 'pkgin install gmake' on NetBSD)" >&2
        errors=$((errors + 1))
    fi

    # Required tools always
    for tool in flex bison m4 gawk patch tar; do
        if ! _have_cmd "$tool"; then
            echo "ERROR: Required tool not found: $tool" >&2
            errors=$((errors + 1))
        fi
    done

    # C compiler
    local host_cc="${HOST_CC:-gcc}"
    local host_cxx="${HOST_CXX:-g++}"
    if ! _have_cmd "$host_cc"; then
        echo "ERROR: Host C compiler not found: $host_cc" >&2
        errors=$((errors + 1))
    fi

    # GCC 5+ build system requires C++ compiler
    if _gcc_ver_ge "$gcc_ver" "5.0"; then
        if ! _have_cmd "$host_cxx"; then
            echo "ERROR: Host C++ compiler required for GCC 5+: $host_cxx" >&2
            errors=$((errors + 1))
        fi
    fi

    # Downloader
    if ! _have_cmd curl && ! _have_cmd wget; then
        echo "ERROR: Need curl or wget for downloading sources" >&2
        errors=$((errors + 1))
    fi

    # Decompressors
    if ! _have_cmd xz; then
        echo "WARNING: xz not found; some archives may not decompress" >&2
    fi

    if [ "$errors" -gt 0 ]; then
        echo "ERROR: $errors prerequisite(s) missing. Install them and retry." >&2
        return 1
    fi

    log "Host prerequisites OK"
    return 0
}

# Check and handle GCC library prerequisites (GMP, MPFR, MPC, ISL).
# For GCC 4.3+, these must be available. Strategy:
#   1. If system libs found (via pkg-config or known paths), use them.
#   2. Otherwise, use GCC's own contrib/download_prerequisites inside the
#      GCC source tree (places them as subdirectories so GCC builds them).
handle_gcc_prereqs() {
    local gcc_ver="$1"
    local srcdir="$2"
    local builddir="$3"
    local prefix="$4"

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would handle GCC prerequisites for GCC $gcc_ver"; return 0; }

    # GCC < 4.3 does not need GMP/MPFR/MPC
    if _gcc_ver_lt "$gcc_ver" "4.3"; then
        log "GCC $gcc_ver: no GMP/MPFR/MPC prerequisites needed"
        return 0
    fi

    local gcc_src="$srcdir/gcc-${gcc_ver}"

    if [ ! -d "$gcc_src" ]; then
        echo "ERROR: GCC source not found at $gcc_src" >&2
        echo "       Run download_gcc first." >&2
        return 1
    fi

    log "Checking GCC library prerequisites for GCC $gcc_ver..."

    # Try contrib/download_prerequisites first (most reliable method)
    if [ -f "$gcc_src/contrib/download_prerequisites" ]; then
        if _system_gcc_prereqs_ok "$gcc_ver"; then
            log "System GMP/MPFR/MPC libraries found; skipping download"
            _set_gcc_prereq_opts_system
        else
            log "Downloading GCC prerequisites via contrib/download_prerequisites..."
            (cd "$gcc_src" && sh contrib/download_prerequisites) || {
                echo "WARNING: download_prerequisites failed; trying manual download" >&2
                _download_gcc_prereqs_manual "$gcc_ver" "$gcc_src" "$srcdir" || return 1
            }
            log "GCC prerequisites downloaded into $gcc_src"
            GCC_PREREQ_OPTS=""  # In-tree prereqs need no extra configure flags
        fi
    else
        # Old GCC without download_prerequisites script
        if _system_gcc_prereqs_ok "$gcc_ver"; then
            log "System GMP/MPFR/MPC libraries found"
            _set_gcc_prereq_opts_system
        else
            log "Manually downloading GCC prerequisites..."
            _download_gcc_prereqs_manual "$gcc_ver" "$gcc_src" "$srcdir" || return 1
        fi
    fi

    return 0
}

# Check whether system GMP/MPFR/MPC are available and new enough
_system_gcc_prereqs_ok() {
    local gcc_ver="$1"

    # Check for headers and libraries
    for lib in gmp mpfr mpc; do
        if ! pkg-config --exists "$lib" 2>/dev/null; then
            # Try finding headers directly
            local found=0
            for dir in /usr/include /usr/local/include /usr/pkg/include; do
                case "$lib" in
                    gmp)  [ -f "$dir/gmp.h"  ] && found=1 ;;
                    mpfr) [ -f "$dir/mpfr.h" ] && found=1 ;;
                    mpc)  [ -f "$dir/mpc.h"  ] && found=1 ;;
                esac
            done
            if [ "$found" -eq 0 ]; then
                # MPC not needed before GCC 4.5
                if [ "$lib" = "mpc" ] && _gcc_ver_lt "$gcc_ver" "4.5"; then
                    continue
                fi
                return 1
            fi
        fi
    done
    return 0
}

# Set GCC_PREREQ_OPTS pointing to system libraries
_set_gcc_prereq_opts_system() {
    GCC_PREREQ_OPTS=""
    for prefix_dir in /usr /usr/local /usr/pkg; do
        if [ -f "$prefix_dir/include/gmp.h" ]; then
            GCC_PREREQ_OPTS="--with-gmp=$prefix_dir"
            break
        fi
    done
    if [ -f /usr/local/include/mpfr.h ] && [ -z "$GCC_PREREQ_OPTS" ]; then
        GCC_PREREQ_OPTS="--with-gmp=/usr/local --with-mpfr=/usr/local --with-mpc=/usr/local"
    fi
}

# Manually download and symlink GCC prerequisites into the GCC source tree
_download_gcc_prereqs_manual() {
    local gcc_ver="$1"
    local gcc_src="$2"
    local srcdir="$3"

    local need_mpc=1
    _gcc_ver_lt "$gcc_ver" "4.5" && need_mpc=0

    # Select versions appropriate for the GCC version being built
    local gmp_ver mpfr_ver mpc_ver
    if _gcc_ver_lt "$gcc_ver" "4.6"; then
        gmp_ver="5.1.3"; mpfr_ver="3.1.6"; mpc_ver="1.0.3"
    elif _gcc_ver_lt "$gcc_ver" "6.0"; then
        gmp_ver="6.1.0"; mpfr_ver="3.1.6"; mpc_ver="1.0.3"
    else
        gmp_ver="$GMP_VERSION"; mpfr_ver="$MPFR_VERSION"; mpc_ver="$MPC_VERSION"
    fi

    local mirror="${GNU_MIRROR:-https://ftpmirror.gnu.org}"

    _fetch_and_extract \
        "$mirror/gmp/gmp-${gmp_ver}.tar.xz" \
        "$srcdir/gmp-${gmp_ver}.tar.xz" \
        "$srcdir" || return 1
    ln -sfn "$srcdir/gmp-${gmp_ver}" "$gcc_src/gmp"

    _fetch_and_extract \
        "$mirror/mpfr/mpfr-${mpfr_ver}.tar.xz" \
        "$srcdir/mpfr-${mpfr_ver}.tar.xz" \
        "$srcdir" || return 1
    ln -sfn "$srcdir/mpfr-${mpfr_ver}" "$gcc_src/mpfr"
    # MPFR 3.x moved mpfr.h into src/; GCC 4.5-4.6 Makefile's configure-mpc
    # rule passes --with-mpfr-include=$srcdir/mpfr (the root, not src/).
    # Create a compat symlink so the header is findable at the root level.
    if [ ! -f "$srcdir/mpfr-${mpfr_ver}/mpfr.h" ] && \
       [ -f "$srcdir/mpfr-${mpfr_ver}/src/mpfr.h" ]; then
        ln -sf src/mpfr.h "$srcdir/mpfr-${mpfr_ver}/mpfr.h" 2>/dev/null || true
    fi

    if [ "$need_mpc" -eq 1 ]; then
        _fetch_and_extract \
            "$mirror/mpc/mpc-${mpc_ver}.tar.gz" \
            "$srcdir/mpc-${mpc_ver}.tar.gz" \
            "$srcdir" || return 1
        ln -sfn "$srcdir/mpc-${mpc_ver}" "$gcc_src/mpc"
    fi

    GCC_PREREQ_OPTS=""  # In-tree symlinks; no configure flags needed
    log "GCC prerequisites linked into $gcc_src"
}

# Version comparison helpers
# Returns 0 (true) if $1 >= $2 as version strings
_gcc_ver_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, va, "."); m = split(b, vb, ".")
        lim = (n > m) ? n : m
        for (i = 1; i <= lim; i++) {
            x = va[i] + 0; y = vb[i] + 0
            if (x > y) { exit 0 }
            if (x < y) { exit 1 }
        }
        exit 0
    }'
}

# Returns 0 (true) if $1 < $2
_gcc_ver_lt() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, va, "."); m = split(b, vb, ".")
        lim = (n > m) ? n : m
        for (i = 1; i <= lim; i++) {
            x = va[i] + 0; y = vb[i] + 0
            if (x < y) { exit 0 }
            if (x > y) { exit 1 }
        }
        exit 1
    }'
}
