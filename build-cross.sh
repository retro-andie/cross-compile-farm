#!/bin/sh
# build-cross.sh - Build GNU cross-compilers for various UNIX platforms.
#
# Supports: Solaris, AIX, HP-UX, Tru64/OSF, IRIX, NetBSD, FreeBSD, OpenBSD,
#           Linux, SCO OpenServer, UnixWare, and others.
#
# See PROCEDURE.txt for full documentation.
#
# Usage: build-cross.sh [options] <platform> <version>
#        build-cross.sh -h

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/lib"

# Defaults (may be overridden by environment or flags)
TMPDIR="${TMPDIR:-/tmpcross}"; export TMPDIR
CROSS_PREFIX="${CROSS_PREFIX:-/opt/cross}"
CROSS_SYSROOT_BASE="${CROSS_SYSROOT:-/opt/sysroots}"
CROSS_SRCDIR="${CROSS_SRCDIR:-/opt/cross-src}"
CROSS_BUILDDIR="${CROSS_BUILDDIR:-${TMPDIR}/cross-build-$$}"
MAKE_JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

BUILD_RUNTIME=""
KEEP_BUILD=""
DRY_RUN=""
VERBOSE=""
USER_GCC_VER=""
USER_BINUTILS_VER=""
USER_ARCH=""
CUSTOM_SYSROOT=""
COMPILER_HOST=""

# Load library files
for _lib in platforms prereqs fetch bootstrap-gcc old-gcc-build build-binutils build-gcc old-host libc5-sysroot; do
    _libfile="$LIB_DIR/${_lib}.sh"
    if [ ! -f "$_libfile" ]; then
        echo "ERROR: Missing library file: $_libfile" >&2
        echo "       Ensure the lib/ directory is alongside build-cross.sh" >&2
        exit 1
    fi
    . "$_libfile"
done

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log() {
    echo "==> $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARNING: $*" >&2
}

run() {
    if [ -n "$DRY_RUN" ]; then
        echo "[DRY RUN] $*"
    else
        [ -n "$VERBOSE" ] && echo "+ $*"
        "$@"
    fi
}

usage() {
    cat <<'EOF'
Usage: build-cross.sh [options] <platform> <version>

Platforms (modern targets):
  solaris    <version>  2.3 2.4 2.5 2.6 7 8 9 10 11
  aix        <version>  3.2 4.1 4.2 4.3 5.1 5.2 5.3 6.1 7.1 7.2 7.3
  hpux       <version>  9 10.20 11.0 11.11 11.23 11.31
  tru64      <version>  3.2 4.0 5.0 5.1
  osf1       <version>  (alias for tru64)
  irix       <version>  5.2 5.3 6.2 6.4 6.5
  netbsd     <version>  1.5 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0
  freebsd    <version>  2.2 3.5 4.11 5.5 6.4 7.4 8.4 9.3 10.4 11.4 12.4 13.2
  openbsd    <version>  2.9 3.9 4.9 5.9 6.9 7.3 7.4
  linux      <version>  2.4 2.6 3.x 4.x 5.x 6.x
  sco        <version>  3.2 5.0
  unixware   <version>  2.1 7.1

Platforms (historical / early-1990s targets):
  sunos4     <version>  3.5 4.0 4.1 4.1.1 4.1.2 4.1.3 4.1.4
  ultrix     <version>  2.0 3.1 4.0 4.2 4.3 4.4
  nextstep   <version>  1.0 2.0 3.0 3.1 3.2 3.3
  openstep   <version>  4.0 4.1 4.2     (alias: next)
  dynix      <version>  3.0 3.1 3.2
  linux1     <version>  1.0 1.1 1.2     (libc4 / a.out, aliases: linux-libc4, linux-aout)
  linux2     <version>  2.0 2.1 2.2     (libc5 / ELF,  aliases: linux-libc5, linuxelf)

Options:
  -a <arch>   Architecture: sparc, x86, x86_64, ppc, ppc64, mips, mipsel,
              mips64, alpha, ia64, parisc, arm, aarch64, s390x, riscv64,
              m68k, vax
  -g <ver>    GCC version to build (default: last version for the target)
  -b <ver>    Binutils version to build (default: recommended for the target)
  -p <dir>    Install prefix (default: /opt/cross)
  -s <dir>    Sysroot base directory (default: /opt/sysroots)
  -S <dir>    Exact sysroot path (overrides -s auto-detection)
  -H <triple> Compiler host triple for Canadian cross builds.
              The resulting compiler will RUN on <triple> and generate code
              for <platform>.  Requires a cross-compiler for <triple> to
              already be installed (or on PATH as <triple>-gcc).
              Example: -H sparc-sun-solaris2.6  (build a compiler that runs
              on Solaris 2.6 and targets some other platform)
  -j <n>      Parallel build jobs (default: auto-detect)
  -d <dir>    Build work directory (default: /tmp/cross-build-PID)
  -D <dir>    Source download directory (default: /opt/cross-src)
  -r          Build target runtime libraries (libgcc, libstdc++)
              Requires a complete sysroot with target libc headers and libs.
              Without -r, only the compiler front-ends are built (sufficient
              for compilation; linking requires target's native libgcc).
  -k          Keep build directory after success (default: remove)
  -n          Dry run: print what would be done without doing it
  -v          Verbose output (echo commands as they run)
  -h          Show this help

Environment variables:
  CROSS_PREFIX      Installation prefix (same as -p)
  CROSS_SYSROOT     Sysroot base (same as -s)
  CROSS_SRCDIR      Source directory (same as -D)
  COMPILER_HOST     Canadian cross host triple (same as -H)
  MAKE_JOBS         Parallel jobs (same as -j)
  HOST_CC           Host C compiler (default: gcc)
  HOST_CXX          Host C++ compiler (default: g++)
  GNU_MIRROR        GNU FTP mirror URL (default: https://ftpmirror.gnu.org)
  GMP_VERSION       Override GMP prerequisite version
  MPFR_VERSION      Override MPFR prerequisite version
  MPC_VERSION       Override MPC prerequisite version

Examples:
  ./build-cross.sh solaris 10
  ./build-cross.sh -a x86 solaris 10
  ./build-cross.sh -a ia64 hpux 11.31
  ./build-cross.sh tru64 5.1
  ./build-cross.sh irix 6.5
  ./build-cross.sh -a ppc64 aix 7.1
  ./build-cross.sh -a x86_64 freebsd 13.2
  ./build-cross.sh -g 4.6.4 -b 2.38 tru64 5.1
  ./build-cross.sh -r -S /mnt/solaris10 solaris 10
  ./build-cross.sh sunos4 4.1.4
  ./build-cross.sh -a mips ultrix 4.4
  ./build-cross.sh linux1 1.0
  ./build-cross.sh linux2 2.0
  ./build-cross.sh -n linux2 2.2

Canadian cross (build compiler that runs on an old UNIX host):
  # Build a cross-compiler that runs on Solaris 2.6 and targets Tru64 5.1
  ./build-cross.sh -H sparc-sun-solaris2.6 tru64 5.1

See PROCEDURE.txt for sysroot setup, version support matrix, old-GCC notes,
libc4/libc5 sysroot setup, Canadian cross procedure, and troubleshooting.
EOF
}

# ---------------------------------------------------------------------------
# Parse command-line options
# ---------------------------------------------------------------------------
while getopts "a:g:b:p:s:S:H:j:d:D:rknvh" _opt; do
    case "$_opt" in
        a) USER_ARCH="$OPTARG"          ;;
        g) USER_GCC_VER="$OPTARG"       ;;
        b) USER_BINUTILS_VER="$OPTARG"  ;;
        p) CROSS_PREFIX="$OPTARG"       ;;
        s) CROSS_SYSROOT_BASE="$OPTARG" ;;
        S) CUSTOM_SYSROOT="$OPTARG"     ;;
        H) COMPILER_HOST="$OPTARG"      ;;
        j) MAKE_JOBS="$OPTARG"          ;;
        d) CROSS_BUILDDIR="$OPTARG"     ;;
        D) CROSS_SRCDIR="$OPTARG"       ;;
        r) BUILD_RUNTIME="yes"          ;;
        k) KEEP_BUILD="yes"             ;;
        n) DRY_RUN="yes"                ;;
        v) VERBOSE="yes"                ;;
        h) usage; exit 0                ;;
        *) usage >&2; exit 1            ;;
    esac
done
shift $((OPTIND - 1))

PLATFORM="$1"
PLATFORM_VER="$2"

if [ -z "$PLATFORM" ] || [ -z "$PLATFORM_VER" ]; then
    echo "ERROR: Platform and version are required" >&2
    usage >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Detect host environment capabilities
# ---------------------------------------------------------------------------
detect_host_capabilities || die "Failed to detect host capabilities"
setup_old_host_env

# ---------------------------------------------------------------------------
# Resolve platform information
# ---------------------------------------------------------------------------
get_platform_info "$PLATFORM" "$PLATFORM_VER" "$USER_ARCH" || exit 1

# Apply user version overrides
GCC_VER="${USER_GCC_VER:-$DEFAULT_GCC_VER}"
BINUTILS_VER="${USER_BINUTILS_VER:-$DEFAULT_BINUTILS_VER}"

# Resolve sysroot path
if [ -n "$CUSTOM_SYSROOT" ]; then
    SYSROOT="$CUSTOM_SYSROOT"
else
    SYSROOT="$CROSS_SYSROOT_BASE/$TARGET"
fi

# Canadian cross: set up --host= flags for binutils and GCC configure
COMPILER_HOST="${COMPILER_HOST:-}"
if [ -n "$COMPILER_HOST" ]; then
    setup_compiler_host || die "Failed to configure compiler host: $COMPILER_HOST"
fi

# Export for library use
export TARGET GCC_VER BINUTILS_VER SYSROOT MAKE_JOBS
export CROSS_PREFIX CROSS_SRCDIR CROSS_BUILDDIR
export TARGET_ABI EXTRA_GCC_OPTS EXTRA_BINUTILS_OPTS
HOST_CC="$(command -v "${HOST_CC:-gcc}" 2>/dev/null || echo "${HOST_CC:-gcc}")"
HOST_CXX="$(command -v "${HOST_CXX:-g++}" 2>/dev/null || echo "${HOST_CXX:-g++}")"
export HOST_CC HOST_CXX
export GNU_MIRROR="${GNU_MIRROR:-https://ftpmirror.gnu.org}"
export COMPILER_HOST BINUTILS_HOST_FLAG GCC_HOST_FLAG
export BOOTSTRAP_GCC_PREFIX="${BOOTSTRAP_GCC_PREFIX:-$CROSS_PREFIX/lib/bootstrap-gcc}"

# ---------------------------------------------------------------------------
# Print build summary
# ---------------------------------------------------------------------------
echo ""
echo "Cross-compiler build summary"
echo "============================"
echo "  Platform  : $PLATFORM $PLATFORM_VER"
echo "  Target    : $TARGET"
echo "  ABI/format: $TARGET_ABI"
echo "  GCC       : $GCC_VER  (last supported for this target: $LAST_GCC_VER)"
echo "  Binutils  : $BINUTILS_VER"
echo "  Prefix    : $CROSS_PREFIX"
echo "  Sysroot   : $SYSROOT"
echo "  Srcdir    : $CROSS_SRCDIR"
echo "  Builddir  : $CROSS_BUILDDIR"
echo "  Jobs      : $MAKE_JOBS"
echo "  Runtime   : ${BUILD_RUNTIME:-no (front-ends only)}"
if [ -n "$COMPILER_HOST" ]; then
    echo "  Comp.host : $COMPILER_HOST  (Canadian cross)"
fi
if [ -n "${LIBC_TYPE:-}" ]; then
    echo "  LibC type : $LIBC_TYPE"
fi
if [ -n "${GCC_PREREQ_OPTS:-}" ]; then
    echo "  GCC prereq: $GCC_PREREQ_OPTS"
fi
echo ""

if [ -n "$DRY_RUN" ]; then
    echo "(Dry run mode - no files will be created or modified)"
fi

# Warn if using a non-default GCC version
if [ -n "$USER_GCC_VER" ] && [ "$USER_GCC_VER" != "$LAST_GCC_VER" ]; then
    warn "Using GCC $USER_GCC_VER (last supported for $PLATFORM $PLATFORM_VER is $LAST_GCC_VER)"
fi

# Sysroot advisory
if [ ! -d "$SYSROOT" ] && [ -z "$DRY_RUN" ]; then
    echo "NOTICE: Sysroot not found at: $SYSROOT"
    echo "        The compiler will be built, but will not find target headers or"
    echo "        libraries until the sysroot is populated."
    echo "        See PROCEDURE.txt Section 4 for sysroot setup instructions."
    echo ""
fi

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
check_prereqs "$GCC_VER" || die "Prerequisite check failed. See above."

# ---------------------------------------------------------------------------
# Create directories
# ---------------------------------------------------------------------------
if [ -z "$DRY_RUN" ]; then
    mkdir -p "$CROSS_SRCDIR" || die "Cannot create source directory: $CROSS_SRCDIR"
    mkdir -p "$CROSS_PREFIX" || die "Cannot create prefix directory: $CROSS_PREFIX (run as root?)"
    mkdir -p "$CROSS_BUILDDIR" || die "Cannot create build directory: $CROSS_BUILDDIR"
fi

# Clean up build directory on failure unless -k
_cleanup() {
    local rc="$?"
    if [ "$rc" -ne 0 ] && [ -z "$KEEP_BUILD" ]; then
        echo ""
        echo "Build FAILED (exit code $rc)"
        echo "Build artifacts left at: $CROSS_BUILDDIR"
        echo "Logs may be in $CROSS_BUILDDIR/*/config.log"
    fi
}
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Bootstrap GCC (needed for era1/era2-early cross-compiler builds)
# ---------------------------------------------------------------------------
if need_bootstrap_gcc "$GCC_VER"; then
    log "GCC $GCC_VER requires bootstrap GCC $BOOTSTRAP_GCC_VER as intermediate compiler."
    if [ -n "$DRY_RUN" ]; then
        echo "[DRY RUN] Would build/verify bootstrap GCC $BOOTSTRAP_GCC_VER"
    else
        ensure_bootstrap_gcc || die "Bootstrap GCC $BOOTSTRAP_GCC_VER required but could not be built."
    fi
fi

# ---------------------------------------------------------------------------
# Download sources
# ---------------------------------------------------------------------------
log "Downloading binutils $BINUTILS_VER..."
download_binutils "$BINUTILS_VER" "$CROSS_SRCDIR" || die "Failed to download binutils $BINUTILS_VER"

log "Downloading GCC $GCC_VER..."
download_gcc "$GCC_VER" "$CROSS_SRCDIR" || die "Failed to download GCC $GCC_VER"

# ---------------------------------------------------------------------------
# Handle GCC prerequisites (GMP, MPFR, MPC for GCC 4.3+)
# ---------------------------------------------------------------------------
handle_gcc_prereqs "$GCC_VER" "$CROSS_SRCDIR" "$CROSS_BUILDDIR" "$CROSS_PREFIX" \
    || die "Failed to set up GCC prerequisites"

# ---------------------------------------------------------------------------
# Build binutils
# ---------------------------------------------------------------------------
log "Building binutils $BINUTILS_VER for $TARGET..."
build_binutils "$BINUTILS_VER" "$TARGET" "$CROSS_PREFIX" "$SYSROOT" \
    "$CROSS_SRCDIR" "$CROSS_BUILDDIR" "${BINUTILS_HOST_FLAG:-}" \
    || die "binutils build failed. Check $CROSS_BUILDDIR/binutils-${BINUTILS_VER}-${TARGET}/config.log"

# Add cross-binutils to PATH so GCC can find the cross-assembler/linker
PATH="$CROSS_PREFIX/bin:$PATH"
export PATH

# ---------------------------------------------------------------------------
# Build GCC
# ---------------------------------------------------------------------------
log "Building GCC $GCC_VER for $TARGET..."
build_gcc "$GCC_VER" "$TARGET" "$CROSS_PREFIX" "$SYSROOT" \
    "$CROSS_SRCDIR" "$CROSS_BUILDDIR" "$BUILD_RUNTIME" "${GCC_HOST_FLAG:-}" \
    || die "GCC build failed. Check $CROSS_BUILDDIR/gcc-${GCC_VER}-${TARGET}/config.log"

# ---------------------------------------------------------------------------
# Cleanup build directory
# ---------------------------------------------------------------------------
if [ -z "$KEEP_BUILD" ] && [ -z "$DRY_RUN" ]; then
    log "Removing build directory: $CROSS_BUILDDIR"
    rm -rf "$CROSS_BUILDDIR"
fi

# ---------------------------------------------------------------------------
# Success message
# ---------------------------------------------------------------------------
trap - EXIT
echo ""
echo "======================================================================"
echo "Cross-compiler installed successfully!"
echo "  Target  : $TARGET"
echo "  GCC     : $GCC_VER"
echo "  Prefix  : $CROSS_PREFIX"
echo ""
echo "To use:"
echo "  export PATH=\"$CROSS_PREFIX/bin:\$PATH\""
echo "  ${TARGET}-gcc --version"
echo "  ${TARGET}-gcc -o hello hello.c"
echo ""
if [ ! -d "$SYSROOT" ]; then
    echo "REMINDER: Populate the sysroot at $SYSROOT before compiling."
    echo "          See PROCEDURE.txt Section 4 for instructions."
    echo ""
fi
echo "======================================================================"
