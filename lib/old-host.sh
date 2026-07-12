#!/bin/sh
# lib/old-host.sh - Old UNIX host detection, environment setup, and
# Canadian-cross support (building a toolchain that will run on an old host).
#
# Two scenarios handled here:
#
#  A) RUNNING ON AN OLD HOST: The build-cross.sh script is being executed
#     directly on an old UNIX system (SunOS 4, old AIX, HP-UX 10, libc5 Linux).
#     We detect the host and configure the build environment accordingly.
#
#  B) BUILDING FOR AN OLD HOST (Canadian cross): The script runs on a modern
#     Linux host but the resulting cross-compiler must RUN on an old system.
#     Set COMPILER_HOST=<triple> to enable this.  The user must supply a
#     build→compiler-host cross-compiler in PATH (e.g. sparc-sun-sunos4.1.4-gcc).
#
# In both cases this library sets environment variables used by the build
# functions: MAKE, TAR, GZIP, BUILD_TRIPLE, HOST_TRIPLE, etc.

# The triple of the system where the resulting toolchain will run.
# Empty means the toolchain runs on the same system as the build host.
COMPILER_HOST="${COMPILER_HOST:-}"

# ---------------------------------------------------------------------------
# Detect the current build host and its capabilities.
# Sets: BUILD_TRIPLE, HOST_OS_TYPE, MAKE, TAR, GZIP, HOST_SHELL_OK
# ---------------------------------------------------------------------------
detect_host_capabilities() {
    # Determine the build machine triple
    BUILD_TRIPLE=$(${HOST_CC:-gcc} -dumpmachine 2>/dev/null || \
                   uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')

    # Classify the host OS
    local uname_s
    uname_s=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$uname_s" in
        linux*)   HOST_OS_TYPE="linux"  ;;
        sunos*)
            local sunos_rel
            sunos_rel=$(uname -r 2>/dev/null | cut -d. -f1)
            case "$sunos_rel" in
                4) HOST_OS_TYPE="sunos4" ;;
                5) HOST_OS_TYPE="solaris" ;;
                *) HOST_OS_TYPE="sunos" ;;
            esac
            ;;
        aix*)     HOST_OS_TYPE="aix"    ;;
        hp-ux*)   HOST_OS_TYPE="hpux"   ;;
        irix*)    HOST_OS_TYPE="irix"   ;;
        osf1*)    HOST_OS_TYPE="tru64"  ;;
        freebsd*) HOST_OS_TYPE="freebsd" ;;
        netbsd*)  HOST_OS_TYPE="netbsd"  ;;
        openbsd*) HOST_OS_TYPE="openbsd" ;;
        *)        HOST_OS_TYPE="unknown" ;;
    esac

    # Find GNU make (required; old UNIX `make` often won't work)
    # Try gmake/gnumake first so BSD systems with pkg-installed gmake win over
    # the system BSD make; fall back to plain 'make' on Linux where it's GNU.
    MAKE=$(find_gnu_tool gmake gnumake make)
    if [ -z "$MAKE" ]; then
        echo "ERROR: GNU make not found. Install gmake or add GNU make to PATH." >&2
        echo "       On SunOS 4: pkgadd or compile from source" >&2
        echo "       On HP-UX:   /usr/local/bin/gmake" >&2
        echo "       On AIX:     smit or /opt/freeware/bin/gmake" >&2
        return 1
    fi
    export MAKE

    # Find GNU tar (standard tar may not support compression on old UNIX)
    TAR=$(find_gnu_tool tar gtar)
    export TAR

    # Find gzip/bzip2/xz
    GZIP=$(find_gnu_tool gzip)
    BZIP2=$(find_gnu_tool bzip2)
    XZ=$(find_gnu_tool xz)
    export GZIP BZIP2 XZ

    # Test if /bin/sh supports `local` (not in old Bourne sh)
    if (sh -c 'local x=1' 2>/dev/null); then
        HOST_SHELL_OK="yes"
    else
        HOST_SHELL_OK=""
        echo "WARNING: /bin/sh does not support 'local'. Use bash or ksh." >&2
        echo "         Try: SHELL=/bin/ksh ./build-cross.sh ..." >&2
    fi

    log "Build host: $BUILD_TRIPLE ($HOST_OS_TYPE)"
    log "GNU make:   $MAKE"
    log "GNU tar:    ${TAR:-not found}"
}

# ---------------------------------------------------------------------------
# Set up build environment for running on an old UNIX host.
# Called when detect_host_capabilities() identifies a non-Linux/non-NetBSD host.
# ---------------------------------------------------------------------------
setup_old_host_env() {
    case "$HOST_OS_TYPE" in
        sunos4)
            _setup_env_sunos4
            ;;
        solaris)
            _setup_env_solaris_host
            ;;
        hpux)
            _setup_env_hpux_host
            ;;
        aix)
            _setup_env_aix_host
            ;;
        irix)
            _setup_env_irix_host
            ;;
        tru64)
            _setup_env_tru64_host
            ;;
        *)
            # Linux, NetBSD, FreeBSD, etc. — no special setup needed
            ;;
    esac

    # Prefer GNU tools over system tools regardless of host
    _prepend_gnu_tools_to_path
}

_setup_env_sunos4() {
    echo "" >&2
    echo "Building on SunOS 4.x host. Required GNU tools:" >&2
    echo "  GNU make, GNU tar, GNU flex, GNU bison, GCC (existing)" >&2
    echo "  Typical location: /usr/local/bin or /usr/gnu/bin" >&2

    # SunOS 4 /bin/sh is old Bourne sh; use bash or ksh if available
    for sh in /usr/local/bin/bash /usr/local/bin/ksh /bin/ksh; do
        [ -x "$sh" ] && { export SHELL="$sh"; break; }
    done

    # SunOS 4 install(1) has different flags; use GNU install
    INSTALL=$(find_gnu_tool install ginstall)
    export INSTALL

    # SunOS 4 /bin/awk is very old; need gawk or nawk
    AWK=$(find_gnu_tool gawk nawk awk)
    export AWK

    # Use /usr/local/bin tools first
    PATH="/usr/local/bin:/usr/gnu/bin:/usr/ccs/bin:$PATH"
    export PATH
}

_setup_env_solaris_host() {
    # Solaris 2.x: /usr/ucb tools are often needed; prefer GNU
    PATH="/usr/local/bin:/opt/csw/bin:/usr/ccs/bin:/usr/bin:$PATH"
    export PATH
    AWK=$(find_gnu_tool gawk awk /usr/xpg4/bin/awk)
    export AWK
}

_setup_env_hpux_host() {
    echo "Building on HP-UX host." >&2
    echo "  Ensure GNU tools are in PATH (typically /usr/local/bin)." >&2
    PATH="/usr/local/bin:/usr/contrib/bin:/opt/gnu/bin:$PATH"
    export PATH
    # HP-UX /bin/sh is POSIX but old; bash is safer
    for sh in /usr/local/bin/bash /usr/contrib/bin/bash; do
        [ -x "$sh" ] && { export SHELL="$sh"; break; }
    done
}

_setup_env_aix_host() {
    echo "Building on AIX host." >&2
    PATH="/opt/freeware/bin:/usr/local/bin:$PATH"
    export PATH
    # On AIX, OBJECT_MODE controls 32/64 bit linking
    OBJECT_MODE="${OBJECT_MODE:-32}"
    export OBJECT_MODE
    # Force GNU linker flags (IBM ld has different options)
    export LDFLAGS="${LDFLAGS} -Wl,-blibpath:/opt/freeware/lib:/usr/lib:/lib"
}

_setup_env_irix_host() {
    PATH="/usr/local/bin:/usr/bsd:/usr/gnu/bin:$PATH"
    export PATH
}

_setup_env_tru64_host() {
    PATH="/usr/local/bin:/usr/gnu/bin:$PATH"
    export PATH
}

_prepend_gnu_tools_to_path() {
    for dir in /usr/local/bin /opt/local/bin /usr/gnu/bin /opt/csw/bin \
                /opt/freeware/bin /usr/pkg/bin; do
        [ -d "$dir" ] || continue
        case "$PATH" in
            *"$dir"*) ;;
            *) PATH="$dir:$PATH" ;;
        esac
    done
    export PATH
}

# ---------------------------------------------------------------------------
# Canadian-cross support: build a toolchain that RUNS on COMPILER_HOST.
# Sets: COMPILER_HOST_CC, BINUTILS_HOST_FLAG, GCC_HOST_FLAG
#
# A "Canadian cross" requires:
#   BUILD  = current machine (modern Linux)
#   HOST   = COMPILER_HOST (e.g. sparc-sun-sunos4.1.4)
#   TARGET = the target the cross-compiler will generate code for
#
# You must have a BUILD→HOST cross-compiler already installed.
# Example: /opt/cross/bin/sparc-sun-sunos4.1.4-gcc must exist.
# ---------------------------------------------------------------------------
setup_compiler_host() {
    [ -z "$COMPILER_HOST" ] && return 0

    log "Canadian-cross mode: toolchain will run on $COMPILER_HOST"

    if [ -n "$DRY_RUN" ]; then
        echo "[DRY RUN] Would verify $COMPILER_HOST-gcc exists for Canadian cross"
        BINUTILS_HOST_FLAG="--host=$COMPILER_HOST"
        GCC_HOST_FLAG="--host=$COMPILER_HOST"
        COMPILER_HOST_SYSROOT="${COMPILER_HOST_SYSROOT:-$CROSS_SYSROOT_BASE/$COMPILER_HOST}"
        export BINUTILS_HOST_FLAG GCC_HOST_FLAG COMPILER_HOST_SYSROOT
        return 0
    fi

    # Find the build→host cross-compiler
    local host_cc="${COMPILER_HOST}-gcc"
    local host_cc_path
    host_cc_path=$(command -v "$host_cc" 2>/dev/null)

    if [ -z "$host_cc_path" ]; then
        # Try with CROSS_PREFIX
        if [ -x "$CROSS_PREFIX/bin/$host_cc" ]; then
            host_cc_path="$CROSS_PREFIX/bin/$host_cc"
        fi
    fi

    if [ -z "$host_cc_path" ]; then
        echo "ERROR: Canadian-cross requires a build→host cross-compiler:" >&2
        echo "         $host_cc" >&2
        echo "       Build one first:" >&2
        echo "         $(echo "$COMPILER_HOST" | sed 's/-/ /g' | awk '{print $3}' | \
                          sed 's/[0-9.].*//') ... or use build-cross.sh for that host" >&2
        return 1
    fi

    COMPILER_HOST_CC="$host_cc_path"
    log "Host cross-compiler: $COMPILER_HOST_CC"

    # Flags to pass to binutils and GCC configure for canadian cross
    BINUTILS_HOST_FLAG="--host=$COMPILER_HOST"
    GCC_HOST_FLAG="--host=$COMPILER_HOST"

    # Also need a sysroot for the HOST system's libraries (for linking GCC itself)
    COMPILER_HOST_SYSROOT="${COMPILER_HOST_SYSROOT:-$CROSS_SYSROOT_BASE/$COMPILER_HOST}"
    if [ ! -d "$COMPILER_HOST_SYSROOT" ]; then
        echo "WARNING: Compiler host sysroot not found: $COMPILER_HOST_SYSROOT" >&2
        echo "         Set COMPILER_HOST_SYSROOT= to the $COMPILER_HOST system root." >&2
    fi

    export COMPILER_HOST_CC BINUTILS_HOST_FLAG GCC_HOST_FLAG COMPILER_HOST_SYSROOT
}

# ---------------------------------------------------------------------------
# Check prerequisites specific to old UNIX hosts.
# A superset of check_prereqs() with old-host-specific additions.
# ---------------------------------------------------------------------------
check_old_host_prereqs() {
    local gcc_ver="$1"

    # First run the normal check
    check_prereqs "$gcc_ver" || return 1

    # Extra checks for non-Linux hosts
    if [ "$HOST_OS_TYPE" != "linux" ] && [ "$HOST_OS_TYPE" != "netbsd" ] && \
       [ "$HOST_OS_TYPE" != "freebsd" ] && [ "$HOST_OS_TYPE" != "openbsd" ]; then

        # Verify GNU make is found and is actually GNU
        if ! "$MAKE" --version 2>&1 | grep -q GNU; then
            echo "ERROR: $MAKE is not GNU make. Install gmake." >&2
            return 1
        fi

        # SunOS 4 / HP-UX: flex is critical (old lex won't work with GCC)
        if ! command -v flex >/dev/null 2>&1; then
            echo "ERROR: flex not found. GCC build requires GNU flex." >&2
            return 1
        fi

        # Warn about shell
        if [ -z "$HOST_SHELL_OK" ]; then
            echo "WARNING: Incompatible /bin/sh detected. Set SHELL to bash or ksh." >&2
        fi
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Utility: find a GNU tool by trying multiple names in PATH.
# Returns the first found, or empty string.
# ---------------------------------------------------------------------------
find_gnu_tool() {
    local found=""
    local _p=""
    for name in "$@"; do
        # Capture output; /dev/null redirect is intentionally avoided so this
        # works on hosts where /dev/null is missing or not writable.
        _p=$(command -v "$name" 2>&1)
        case "$_p" in
            /*) found="$_p"; break ;;
        esac
    done
    echo "$found"
}

# ---------------------------------------------------------------------------
# Generate a self-contained bootstrap script for old UNIX hosts.
# This script can be copied to an old host and builds the prerequisite tools
# (GNU make, flex, bison, tar) needed before running build-cross.sh there.
# ---------------------------------------------------------------------------
generate_bootstrap_script() {
    local out="${1:-bootstrap-old-host.sh}"
    cat > "$out" << 'BOOTSTRAP'
#!/bin/sh
# Bootstrap GNU tools on an old UNIX host.
# Run this first on the old host before running build-cross.sh.
# Requires: a C compiler (cc or gcc), tar, and network/FTP access.

set -e

PREFIX="${PREFIX:-/usr/local}"
MIRROR="${MIRROR:-https://ftpmirror.gnu.org}"
SRCDIR="${TMPDIR:-/tmp}/bootstrap-src"

mkdir -p "$SRCDIR"

die() { echo "ERROR: $*" >&2; exit 1; }

fetch() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$dest" "$url"
    elif command -v ftp >/dev/null 2>&1; then
        ftp -o "$dest" "$url"
    else
        die "No download tool (curl/wget/ftp) found."
    fi
}

build_pkg() {
    local name="$1" ver="$2" url="$3"
    local archive="$SRCDIR/${name}-${ver}.tar.gz"
    local src="$SRCDIR/${name}-${ver}"

    echo "==> Building $name $ver..."
    [ -f "$archive" ] || fetch "$url" "$archive"
    [ -d "$src" ]     || (cd "$SRCDIR" && gzip -dc "$archive" | tar xf -)

    mkdir -p "$src/build"
    (cd "$src/build" && \
        ../configure --prefix="$PREFIX" --disable-nls && \
        make && make install)
}

echo "Building bootstrap tools for old UNIX host"
echo "Install prefix: $PREFIX"
echo ""

# GNU make 3.82 — last version that works on very old UNIX systems
build_pkg make 3.82 "$MIRROR/make/make-3.82.tar.gz" || \
build_pkg make 4.3  "$MIRROR/make/make-4.3.tar.gz"

# GNU tar 1.34
build_pkg tar  1.34 "$MIRROR/tar/tar-1.34.tar.gz"

# GNU flex 2.6.4
build_pkg flex 2.6.4 "https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz"

# GNU bison 3.8.2
build_pkg bison 3.8.2 "$MIRROR/bison/bison-3.8.2.tar.gz" || \
build_pkg bison 2.7   "$MIRROR/bison/bison-2.7.tar.gz"

echo ""
echo "Bootstrap complete. Add $PREFIX/bin to your PATH:"
echo "  export PATH=$PREFIX/bin:\$PATH"
BOOTSTRAP
    chmod +x "$out"
    log "Bootstrap script written to: $out"
    log "Copy to the old host and run it before build-cross.sh."
}
