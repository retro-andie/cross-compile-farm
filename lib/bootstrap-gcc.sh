#!/bin/sh
# lib/bootstrap-gcc.sh - Build GCC 2.7.2.3 as an intermediate native compiler.
#
# PURPOSE:
#   GCC 1.x and early GCC 2.x sources are written in K&R C.  Host GCC 5+
#   may fail to compile them even with compatibility flags.  GCC 2.7.2.3 is
#   the last version that natively handles both K&R C input AND can itself be
#   built on modern Linux with the patches in patches/gcc-2.7.2.3-native-linux.patch
#   and patches/gcc-2.7.2.3-cross-linux.patch.
#
#   This library builds GCC 2.7.2.3 as a 32-bit i686-linux native compiler
#   (using the host's `gcc -m32` toolchain), then uses that compiler as
#   HOST_CC for era1 and era2-early cross-compiler builds.
#
# ARCHITECTURE NOTES:
#   GCC 2.7.2.3 predates x86_64; its only viable build on a 64-bit host is
#   as an i686-linux binary executed under the 32-bit compatibility layer.
#   The resulting cross-compiler binaries (cc1, gcc driver, etc.) will be
#   i686 ELF; they run on x86_64 Linux via ia32 compat and on NetBSD amd64
#   via COMPAT_LINUX32.
#
#   If 32-bit compat is unavailable, the script falls back to building
#   GCC 2.7.2.3 as i686-linux using the full Canadian-cross approach:
#     BUILD=x86_64-linux  HOST=i686-linux  TARGET=<whatever>
#   In that case the bootstrap GCC 2.7.2.3 cannot run as a standalone native
#   compiler, but the object files it generates during the final GCC 1.x build
#   are passed to the real host linker (x86_64), producing a runnable binary.
#
# EXPORTED VARIABLES (after ensure_bootstrap_gcc):
#   BOOTSTRAP_GCC_CC     - path to the i686 gcc binary (e.g. .../bin/gcc)
#   BOOTSTRAP_GCC_PREFIX - installation prefix of the bootstrap GCC
#   BOOTSTRAP_GCC_BUILT  - "yes" once successfully built

BOOTSTRAP_GCC_VER="2.7.2.3"
BOOTSTRAP_GCC_PREFIX="${BOOTSTRAP_GCC_PREFIX:-${CROSS_PREFIX}/lib/bootstrap-gcc}"

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Returns 0 if the bootstrap GCC (2.7.2.3) is needed for this build.
# It is needed whenever HOST_CC cannot reliably compile K&R C.
need_bootstrap_gcc() {
    local gcc_ver="$1"
    local era
    era=$(gcc_build_era "$gcc_ver" 2>/dev/null || echo "modern")
    case "$era" in
        era1|era2-early) return 0 ;;
        *)               return 1 ;;
    esac
}

# Ensure the bootstrap GCC is available.  Builds it if necessary.
# Sets BOOTSTRAP_GCC_CC to the path of the resulting gcc binary.
ensure_bootstrap_gcc() {
    local bootstrap_bin="$BOOTSTRAP_GCC_PREFIX/bin/gcc"

    if [ -x "$bootstrap_bin" ]; then
        BOOTSTRAP_GCC_CC="$bootstrap_bin"
        export BOOTSTRAP_GCC_CC
        log "Using existing bootstrap GCC: $BOOTSTRAP_GCC_CC"
        _ensure_bootstrap_includes "$BOOTSTRAP_GCC_PREFIX"
        return 0
    fi

    log "Bootstrap GCC not found at $bootstrap_bin; building now..."
    build_bootstrap_gcc || return 1

    if [ ! -x "$bootstrap_bin" ]; then
        echo "ERROR: Bootstrap GCC build appeared to succeed but $bootstrap_bin not found" >&2
        return 1
    fi

    BOOTSTRAP_GCC_CC="$bootstrap_bin"
    BOOTSTRAP_GCC_BUILT="yes"
    export BOOTSTRAP_GCC_CC BOOTSTRAP_GCC_BUILT
    log "Bootstrap GCC ready: $BOOTSTRAP_GCC_CC"
}

# Test whether the current HOST_CC can compile a minimal K&R C file.
# Returns 0 (true) if K&R C compiles cleanly; 1 if warnings/errors appear.
_host_cc_handles_knr() {
    local cc="${HOST_CC:-gcc}"
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/knr_test_XXXXXX")

    cat > "$tmpfile" <<'EOF'
/* K&R style function definition */
int
add(a, b)
    int a;
    int b;
{
    return a + b;
}

int
main()
{
    return add(1, 2) == 3 ? 0 : 1;
}
EOF

    local rc=0
    "$cc" -O0 -w -x c "$tmpfile" -o /dev/null 2>/dev/null || rc=1
    rm -f "$tmpfile"
    return $rc
}

# Build GCC 2.7.2.3 as an i686 native compiler on the current host.
build_bootstrap_gcc() {
    local ver="$BOOTSTRAP_GCC_VER"

    [ -n "$DRY_RUN" ] && {
        echo "[DRY RUN] Would build bootstrap GCC $ver to $BOOTSTRAP_GCC_PREFIX"
        BOOTSTRAP_GCC_CC="$BOOTSTRAP_GCC_PREFIX/bin/gcc"
        export BOOTSTRAP_GCC_CC
        return 0
    }

    log "Building bootstrap GCC $ver (i686 native) ..."

    # ------ Download source ------
    download_gcc "$ver" "$CROSS_SRCDIR" || {
        echo "ERROR: Failed to download GCC $ver for bootstrap" >&2
        return 1
    }

    local src="$CROSS_SRCDIR/gcc-${ver}"
    if [ ! -d "$src" ]; then
        echo "ERROR: GCC $ver source not found at $src" >&2
        return 1
    fi

    # ------ Apply patches ------
    _apply_bootstrap_patches "$src" "$ver" || return 1

    # ------ Detect 32-bit support ------
    local use_m32=0
    local host_triple
    host_triple=$("${HOST_CC:-gcc}" -dumpmachine 2>/dev/null || echo "unknown")

    case "$host_triple" in
        x86_64*|amd64*)
            if _check_m32_support; then
                use_m32=1
                log "x86_64 host: will build bootstrap GCC as i686 (using -m32)"
            else
                echo "WARNING: Host is x86_64 but 32-bit support not available." >&2
                echo "         Bootstrap build may fail.  Install gcc-multilib." >&2
            fi
            ;;
    esac

    # ------ Configure ------
    local bld="$CROSS_BUILDDIR/bootstrap-gcc-${ver}"
    rm -rf "$bld"
    mkdir -p "$bld" "$BOOTSTRAP_GCC_PREFIX"

    local cfg_target="i686-pc-linux-gnu"
    local host_cc="${HOST_CC:-gcc}"
    local host_cxx="${HOST_CXX:-g++}"
    local cflags="-O1 -w -fgnu89-inline -fpermissive -fno-strict-aliasing"
    cflags="$cflags -Wno-implicit-function-declaration -Wno-int-conversion"
    cflags="$cflags -Wno-incompatible-pointer-types -Wno-deprecated-declarations"

    if [ "$use_m32" -eq 1 ]; then
        cflags="$cflags -m32"
        host_cc="$host_cc -m32"
    fi

    log "Configuring bootstrap GCC $ver (target: $cfg_target)..."
    (cd "$bld" && \
        CC="$host_cc" \
        CFLAGS="$cflags" \
        "$src/configure" \
            --prefix="$BOOTSTRAP_GCC_PREFIX" \
            --disable-nls \
            --disable-shared \
            --with-local-prefix="$BOOTSTRAP_GCC_PREFIX" \
            "$cfg_target" \
    ) || {
        echo "ERROR: Bootstrap GCC configure failed" >&2
        return 1
    }

    # ------ Build (C only, no C++) ------
    # OLDCC/CCLIBFLAGS: GCC 2.7.2.3 Makefile uses OLDCC (not CC) to compile
    # libgcc1.a because the routines must not be compiled with GCC itself.
    # On x86_64 the default OLDCC=cc would generate 64-bit code, so override
    # it to use the same -m32 compiler as the rest of the bootstrap build.
    log "Building bootstrap GCC $ver (C only, jobs: 1)..."
    (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="$host_cc" \
            CFLAGS="$cflags" \
            OLDCC="$host_cc" \
            CCLIBFLAGS="$cflags" \
            BISON="bison -y" \
            LEX="flex" \
            LANGUAGES="c" \
    ) || {
        # Fallback: try building just the compiler front-end files
        log "Full build failed; trying minimal cc1+cpp+gcc build..."
        (cd "$bld" && \
            "${MAKE:-make}" -j1 \
                CC="$host_cc" \
                CFLAGS="$cflags" \
                OLDCC="$host_cc" \
                CCLIBFLAGS="$cflags" \
                BISON="bison -y" \
                LEX="flex" \
                LANGUAGES="c" \
                cc1 cpp xgcc \
        ) || { echo "ERROR: Bootstrap GCC build failed" >&2; return 1; }
    }

    # ------ Install assembler wrapper (before make install) ------
    # xgcc (in the build dir) resolves 'as' via the configured --prefix's
    # lib/gcc-lib/TARGET/VER/ directory.  Install the --32 wrapper there
    # before running 'make install' so that stamp-crt (which uses xgcc to
    # compile i386 CRT objects) finds it.  Without this the 64-bit-default
    # system 'as' chokes on the 32-bit assembly output.
    if [ "$use_m32" -eq 1 ]; then
        _install_bootstrap_wrappers "$BOOTSTRAP_GCC_PREFIX"
    fi

    # ------ Install ------
    log "Installing bootstrap GCC $ver to $BOOTSTRAP_GCC_PREFIX..."
    (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            LANGUAGES="c" \
            install \
    ) || {
        # Manual install of minimal set (GCC 2.7.2.3 has no install-gcc target)
        log "Install target failed; installing cc1/cpp/gcc manually..."
        _bootstrap_manual_install "$bld" "$BOOTSTRAP_GCC_PREFIX" "$cfg_target"
    }

    # ------ Verify ------
    local boot_gcc="$BOOTSTRAP_GCC_PREFIX/bin/gcc"
    if [ ! -x "$boot_gcc" ]; then
        # Try alternate location from manual install
        boot_gcc="$BOOTSTRAP_GCC_PREFIX/bin/xgcc"
    fi

    if [ ! -x "$boot_gcc" ]; then
        echo "ERROR: Bootstrap GCC not found after build/install" >&2
        echo "       Expected: $BOOTSTRAP_GCC_PREFIX/bin/gcc" >&2
        return 1
    fi

    # Quick K&R smoke test — as wrapper is in execdir so no PATH changes needed
    if _bootstrap_smoke_test "$boot_gcc"; then
        log "Bootstrap GCC $ver smoke test PASSED"
    else
        echo "WARNING: Bootstrap GCC smoke test FAILED; K&R builds may not work" >&2
    fi

    BOOTSTRAP_GCC_CC="$boot_gcc"
    export BOOTSTRAP_GCC_CC

    # Ensure runtime files (crtbegin.o, libgcc.a) are present so the bootstrap
    # GCC can link executables when used as HOST_CC for era1/era2-early builds.
    _ensure_bootstrap_includes "$BOOTSTRAP_GCC_PREFIX"
}

# ---------------------------------------------------------------------------
# Patch application for the bootstrap GCC source tree
# ---------------------------------------------------------------------------
_apply_bootstrap_patches() {
    local src="$1"
    local ver="$2"

    # Already patched?
    [ -f "$src/.bootstrap_patched_${ver}" ] && return 0

    log "Applying bootstrap GCC $ver patches..."
    # Ensure all source files are writable (tarballs often extract read-only)
    chmod -R u+w "$src" 2>/dev/null || true
    # Replace stale config.guess/config.sub so the host is identified correctly
    _update_config_scripts "$src" 2>/dev/null || true

    local patch_dir="$SCRIPT_DIR/patches"

    # Apply native patch
    _apply_patch_file "$src" "$patch_dir/gcc-${ver}-native-linux.patch" \
        "native-linux" || true

    # Apply cross patch (for cross-compiler builds FROM the bootstrap GCC)
    _apply_patch_file "$src" "$patch_dir/gcc-${ver}-cross-linux.patch" \
        "cross-linux" || true

    # Always apply sed-based patches as reliable fallback
    _sed_patch_getline        "$src"
    _sed_patch_alloca         "$src"
    _sed_patch_strsignal      "$src"
    _sed_patch_sys_nerr       "$src"
    _sed_patch_xm_linux       "$src"
    _sed_patch_disable_werror "$src"
    _sed_patch_fix_proto      "$src"
    _sed_patch_collect2       "$src"
    _sed_patch_bcopy_shims    "$src"

    touch "$src/.bootstrap_patched_${ver}"
    log "Bootstrap patches applied."
}

# Apply a patch file if it exists and hasn't been applied yet.
_apply_patch_file() {
    local src="$1"
    local patchfile="$2"
    local tag="$3"

    [ -f "$patchfile" ] || return 0

    local marker="$src/.patch_applied_${tag}"
    [ -f "$marker" ] && return 0

    log "Applying patch: $(basename "$patchfile")..."
    if (cd "$src" && sed -n '/^--- /,$p' "$patchfile" | \
            patch -p1 -t -N -r /dev/null > /dev/null 2>&1); then
        touch "$marker"
        return 0
    else
        log "Patch $(basename "$patchfile") did not apply cleanly (may be already applied)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Sed-based patches (idempotent fallbacks if .patch files fail)
# ---------------------------------------------------------------------------

_sed_patch_getline() {
    local src="$1"
    local f="$src/libiberty/getline.c"
    [ -f "$f" ] || return 0
    grep -q 'libiberty_getline\|#define getline' "$f" 2>/dev/null && return 0
    log "  sed: renaming getline -> libiberty_getline in libiberty/getline.c"
    sed -i.bak \
        -e '1i#define getline libiberty_getline' \
        -e 's/^getline (/libiberty_getline (/' \
        -e 's/^getline(/libiberty_getline(/' \
        "$f"
    # Also fix the declaration in libiberty.h if present
    local h="$src/include/libiberty.h"
    [ -f "$h" ] || h="$src/libiberty/libiberty.h"
    if [ -f "$h" ]; then
        grep -q 'libiberty_getline' "$h" 2>/dev/null || \
            sed -i.bak \
                -e 's/getline\([^_a-zA-Z0-9]\)/libiberty_getline\1/g' \
                -e 's/getline$/libiberty_getline/' \
                "$h"
    fi
}

_sed_patch_alloca() {
    local src="$1"
    # GCC 2.7.2.3 has alloca.c at top level; newer versions have libiberty/alloca.c
    local f=""
    for _candidate in "$src/libiberty/alloca.c" "$src/alloca.c"; do
        [ -f "$_candidate" ] && { f="$_candidate"; break; }
    done
    [ -n "$f" ] || return 0
    grep -q 'alloca\.h' "$f" 2>/dev/null && return 0
    log "  sed: adding alloca.h include to $(basename $(dirname $f))/alloca.c"
    sed -i.bak \
        '1i#ifdef HAVE_ALLOCA_H\n#  include <alloca.h>\n#endif' \
        "$f"
}

_sed_patch_strsignal() {
    local src="$1"
    local f="$src/libiberty/strsignal.c"
    [ -f "$f" ] || return 0
    grep -q 'const char \* const sys_siglist\|_GNU_SOURCE' "$f" 2>/dev/null && return 0
    log "  sed: fixing sys_siglist declaration in libiberty/strsignal.c"
    sed -i.bak \
        -e '1i#define _GNU_SOURCE 1' \
        -e 's/^extern char \*sys_siglist/extern const char * const sys_siglist/g' \
        "$f"
}

_sed_patch_xm_linux() {
    local src="$1"
    # Try both i386 and x86_64 locations
    local xm=""
    for candidate in \
            "$src/gcc/config/i386/xm-linux.h" \
            "$src/config/i386/xm-linux.h" \
            "$src/gcc/config/xm-linux.h"; do
        [ -f "$candidate" ] && { xm="$candidate"; break; }
    done
    [ -n "$xm" ] || return 0
    # Idempotency: new form wraps each symbol with its own #ifndef guard.
    grep -q '#ifndef HAVE_VPRINTF' "$xm" 2>/dev/null && return 0
    # Migration: old form used a single #ifndef HAVE_GETRLIMIT block that put
    # HAVE_VPRINTF inside it without an inner guard, causing a redefinition
    # warning because config/xm-linux.h already defines HAVE_VPRINTF bare.
    # Fix by wrapping the existing define with a per-symbol guard.
    if grep -q 'HAVE_GETRLIMIT' "$xm" 2>/dev/null; then
        log "  sed: fixing HAVE_VPRINTF guard in $(basename $(dirname "$xm"))/$(basename "$xm")"
        sed -i.bak \
            's/^# define HAVE_VPRINTF    1$/#ifndef HAVE_VPRINTF\n# define HAVE_VPRINTF    1\n#endif/' \
            "$xm"
        return 0
    fi
    log "  sed: adding HAVE_* defines to $(basename $(dirname $xm))/$(basename $xm)"
    cat >> "$xm" <<'EOF'

/* Added by bootstrap patch for modern glibc compatibility */
#ifndef HAVE_GETRLIMIT
# define HAVE_GETRLIMIT  1
#endif
#ifndef HAVE_SETRLIMIT
# define HAVE_SETRLIMIT  1
#endif
#ifndef HAVE_WAITPID
# define HAVE_WAITPID    1
#endif
#ifndef HAVE_SYSCONF
# define HAVE_SYSCONF    1
#endif
#ifndef HAVE_VPRINTF
# define HAVE_VPRINTF    1
#endif
#ifndef HAVE_PUTENV
# define HAVE_PUTENV     1
#endif
#ifndef HAVE_STRSIGNAL
# define HAVE_STRSIGNAL  1
#endif
EOF
}

_sed_patch_disable_werror() {
    local src="$1"
    # Remove -Werror from all Makefile.in and configure files
    find "$src" -name 'Makefile.in' | while read mf; do
        grep -q '\-Werror' "$mf" 2>/dev/null || continue
        sed -i.bak 's/ -Werror//g; s/-Werror //g; s/-Werror$//g' "$mf"
    done
    find "$src" -maxdepth 3 -name 'configure' | while read cf; do
        grep -q '\-Werror' "$cf" 2>/dev/null || continue
        sed -i.bak 's/ -Werror//g; s/-Werror //g' "$cf"
    done
}

_sed_patch_fix_proto() {
    local src="$1"
    for fp in "$src/gcc/fix_proto.c" "$src/fix_proto.c"; do
        [ -f "$fp" ] || continue
        grep -q 'const char \*proto_dir' "$fp" 2>/dev/null && continue
        log "  sed: fixing char*/const char* in $(basename $fp)"
        sed -i.bak \
            -e 's/^char \*proto_dir/const char *proto_dir/' \
            -e 's/^char \*protoize_dir/const char *protoize_dir/' \
            "$fp"
    done
}

_sed_patch_collect2() {
    local src="$1"
    for c2 in "$src/gcc/collect2.c" "$src/collect2.c"; do
        [ -f "$c2" ] || continue
        grep -q '#include.*unistd' "$c2" 2>/dev/null && continue
        log "  sed: adding system headers to $(basename $c2)"
        sed -i.bak \
            '1i#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>' \
            "$c2"
    done
}

_sed_patch_bcopy_shims() {
    local src="$1"
    # bcopy/bzero/bcmp exist in glibc but need <strings.h> to be declared.
    # Defining them as macros causes wrong expansion when strings.h declares them,
    # so we include strings.h instead.
    for f in \
            "$src/gcc/cccp.c" "$src/cccp.c" \
            "$src/gcc/protoize.c" "$src/protoize.c" \
            "$src/gcc/gcc.c" "$src/gcc.c"; do
        [ -f "$f" ] || continue
        grep -q '\bbcopy\b\|\bbzero\b' "$f" 2>/dev/null || continue
        grep -q 'strings\.h\|bcopy_strings_included' "$f" 2>/dev/null && continue
        log "  sed: adding strings.h include for bcopy/bzero in $(basename $f)"
        sed -i.bak \
            '1i#include <strings.h>  /* bcopy, bcmp, bzero */\n/* bcopy_strings_included */' \
            "$f"
    done
}

# Replace sys_nerr/sys_errlist with strerror() — removed from glibc 2.32+
_sed_patch_sys_nerr() {
    local src="$1"
    for f in \
            "$src/gcc/gcc.c"     "$src/gcc.c" \
            "$src/gcc/cccp.c"    "$src/cccp.c" \
            "$src/gcc/collect2.c" "$src/collect2.c" \
            "$src/gcc/cpplib.c"  "$src/cpplib.c" \
            "$src/gcc/protoize.c" "$src/protoize.c" \
            "$src/gcc/cp/g++.c"  "$src/cp/g++.c"; do
        [ -f "$f" ] || continue
        grep -q 'sys_errlist\|sys_nerr' "$f" 2>/dev/null || continue
        # Check if already patched (sentinel: sys_nerr replaced by literal 256)
        grep -q 'sys_nerr_patched_\|#define sys_nerr' "$f" 2>/dev/null && continue
        log "  sed: replacing sys_nerr/sys_errlist with strerror in $(basename $f)"
        sed -i.bak \
            -e '/^extern.*sys_nerr/d' \
            -e '/^extern.*sys_errlist/d' \
            -e 's/sys_errlist\[\([^]]*\)\]/strerror(\1)/g' \
            -e 's/sys_nerr\([^a-zA-Z0-9_]\)/256\1/g' \
            -e 's/sys_nerr$/256/' \
            "$f"
        # Ensure <string.h> is included for strerror
        grep -q '#include <string.h>' "$f" 2>/dev/null || \
            awk 'NR==1{print "#include <string.h>  /* sys_nerr compat */"} {print}' \
                "$f" > "$f.sntmp" && mv "$f.sntmp" "$f" || true
        # Leave a sentinel so idempotency check works
        printf '\n/* sys_nerr_patched_ */\n' >> "$f"
    done
}

# ---------------------------------------------------------------------------
# Support utilities
# ---------------------------------------------------------------------------

# Check whether the host GCC supports -m32 and has 32-bit libs.
_check_m32_support() {
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/m32test_XXXXXX")
    printf 'int main(void){return 0;}\n' > "$tmpfile"
    local rc=0
    "${HOST_CC:-gcc}" -m32 -x c -o /dev/null "$tmpfile" 2>/dev/null || rc=1
    rm -f "$tmpfile"
    return $rc
}

# Quick K&R C smoke test against the bootstrap GCC binary.
# Only compiles (-c); linking is not tested because the bootstrap GCC's
# role as HOST_CC is to compile individual .c files, not to link executables.
_bootstrap_smoke_test() {
    local boot_gcc="$1"
    local tmpfile tmpobj
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/knr_smoke_XXXXXX")
    tmpobj=$(mktemp "${TMPDIR:-/tmp}/knr_smoke_XXXXXX")

    cat > "$tmpfile" <<'EOF'
/* K&R C smoke test */
int
add(a, b)
    int a;
    int b;
{
    return a + b;
}
EOF

    local rc=0
    # Use -S (compile to assembly) rather than -c to avoid needing the assembler.
    # On platforms where 'as --32' is absent (e.g. NetBSD amd64), -c fails even
    # though cc1 is fully functional.  The bootstrap GCC's role is to drive cc1;
    # the assembler is the system's responsibility.
    "$boot_gcc" -O0 -w -x c -S "$tmpfile" -o "$tmpobj" 2>/dev/null || rc=1
    rm -f "$tmpfile" "$tmpobj"
    return $rc
}

# Install the as wrapper into bootstrap GCC's execdir so that only invocations
# through the bootstrap GCC driver use the wrapper — system-gcc configure tests
# are unaffected because they use /usr/bin/as directly via PATH.
#
# GCC 2.7.2.3 driver: when it finds <execdir>/as it calls it by full path,
# completely bypassing PATH.  No PATH modification is needed.
#
# The ld wrapper is NOT needed — GCC 2.7.2.3 already appends -m elf_i386
# to its ld invocation automatically for i686-pc-linux-gnu targets.
_install_bootstrap_wrappers() {
    local prefix="$1"
    local ver="$BOOTSTRAP_GCC_VER"
    local target="i686-pc-linux-gnu"
    local execdir="$prefix/lib/gcc-lib/$target/$ver"
    local real_as

    real_as=$(command -v as 2>/dev/null || echo "/usr/bin/as")

    # Verify --32 is actually supported before installing the wrapper.
    # Use a temp output file — some assemblers (e.g. NetBSD gas) reject
    # identical input/output paths, which would falsely fail /dev/null -o /dev/null.
    local _as_test_out
    _as_test_out=$(mktemp "${TMPDIR:-/tmp}/as32testXXXXXX")
    if ! "$real_as" --32 /dev/null -o "$_as_test_out" 2>/dev/null; then
        rm -f "$_as_test_out"
        log "  as --32 not supported; skipping assembler wrapper"
        return 0
    fi
    rm -f "$_as_test_out"

    mkdir -p "$execdir"

    cat > "$execdir/as" <<EOF
#!/bin/sh
exec "$real_as" --32 "\$@"
EOF
    chmod +x "$execdir/as"

    log "  Bootstrap as wrapper installed: $execdir/as (adds --32)"
}

# Minimal manual install when 'make install' fails.
# Copies cc1, cpp, and the gcc driver to the bootstrap prefix.
_bootstrap_manual_install() {
    local bld="$1"
    local prefix="$2"
    local target_triple="$3"

    local libdir="$prefix/lib/gcc-lib/$target_triple/$BOOTSTRAP_GCC_VER"
    mkdir -p "$prefix/bin" "$libdir/include"

    for bin in gcc xgcc; do
        [ -f "$bld/gcc/$bin" ]  && cp "$bld/gcc/$bin"  "$prefix/bin/gcc"  && break
        [ -f "$bld/$bin" ]      && cp "$bld/$bin"       "$prefix/bin/gcc"  && break
    done

    for prog in cc1 cpp; do
        local found=0
        for loc in "$bld/gcc/$prog" "$bld/$prog"; do
            if [ -f "$loc" ]; then
                cp "$loc" "$libdir/$prog"
                found=1; break
            fi
        done
    done

    # Install GCC's machine-independent headers (stdarg.h, stddef.h, etc.)
    for srcdir in "$bld/gcc" "$bld"; do
        if [ -d "$srcdir/ginclude" ]; then
            cp "$srcdir/ginclude"/*.h "$libdir/include/" 2>/dev/null || true
            break
        fi
    done
    # Also look in the source tree
    local ver="$BOOTSTRAP_GCC_VER"
    for srcdir in \
            "$CROSS_SRCDIR/gcc-${ver}/ginclude" \
            "$CROSS_BUILDDIR/bootstrap-gcc-${ver}/ginclude"; do
        [ -d "$srcdir" ] && cp "$srcdir"/*.h "$libdir/include/" 2>/dev/null || true
    done

    chmod +x "$prefix/bin/gcc" 2>/dev/null || true
    log "Bootstrap GCC minimal install complete: $prefix/bin/gcc"
}

# Populate the bootstrap GCC include directory if it's empty or missing stdarg.h.
# This is needed when the bootstrap GCC was installed manually without ginclude.
_ensure_bootstrap_includes() {
    local prefix="$1"
    local ver="$BOOTSTRAP_GCC_VER"
    local target="i686-pc-linux-gnu"
    local libdir="$prefix/lib/gcc-lib/$target/$ver"
    local incdir="$libdir/include"

    mkdir -p "$incdir"

    if [ ! -f "$incdir/stdarg.h" ]; then
        for srcdir in \
                "$CROSS_SRCDIR/gcc-${ver}/ginclude" \
                "$CROSS_BUILDDIR/bootstrap-gcc-${ver}/ginclude"; do
            if [ -d "$srcdir" ]; then
                cp "$srcdir"/*.h "$incdir/" 2>/dev/null || true
                [ -f "$incdir/stdarg.h" ] && {
                    log "  Bootstrap GCC includes populated from $srcdir"
                    break
                }
            fi
        done
        [ -f "$incdir/stdarg.h" ] || \
            log "  Warning: could not populate bootstrap GCC includes (stdarg.h missing)"
    fi

    # Install runtime files (crtbegin.o, crtend.o, libgcc.a) needed when the
    # bootstrap GCC driver links executables.  Try to copy from the system's
    # 32-bit multilib directory; without these the linker reports missing crtbegin.o.
    if [ ! -f "$libdir/libgcc.a" ] || [ ! -f "$libdir/crtbegin.o" ]; then
        local sys32=""
        for candidate in \
                /usr/lib/gcc/x86_64-redhat-linux/*/32 \
                /usr/lib/gcc/x86_64-linux-gnu/*/32 \
                /usr/lib/gcc/*/*/32; do
            [ -f "$candidate/libgcc.a" ] && { sys32="$candidate"; break; }
        done
        if [ -n "$sys32" ]; then
            log "  Copying 32-bit runtime files from $sys32 to bootstrap GCC lib dir"
            for f in libgcc.a crtbegin.o crtend.o crtbeginS.o crtendS.o; do
                [ -f "$sys32/$f" ] && cp "$sys32/$f" "$libdir/" 2>/dev/null || true
            done
        else
            log "  Warning: 32-bit system GCC runtime files not found; linking may fail"
        fi
    fi
}
