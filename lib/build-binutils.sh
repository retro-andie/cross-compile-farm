#!/bin/sh
# lib/build-binutils.sh - Build GNU binutils for a cross-compilation target.
#
# build_binutils <version> <target> <prefix> <sysroot> <srcdir> <builddir>
#
# The resulting assembler, linker, and archive tools will be installed as
# <prefix>/bin/<target>-{as,ld,ar,nm,objdump,...}

build_binutils() {
    local ver="$1"
    local target="$2"
    local prefix="$3"
    local sysroot="$4"
    local srcdir="$5"
    local builddir="$6"
    local host_flag="${7:-}"   # e.g. --host=sparc-sun-solaris2.6 for Canadian cross

    local src="$srcdir/binutils-${ver}"
    local bld="$builddir/binutils-${ver}-${target}"

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would build binutils $ver for $target"; return 0; }

    if [ ! -d "$src" ]; then
        echo "ERROR: binutils source not found: $src" >&2
        return 1
    fi

    # Apply compatibility patches for old binutils (<= 2.17) on modern hosts.
    # 2.17 (2006) has the same libiberty/strsignal.c type conflicts as older versions.
    if _gcc_ver_lt "$ver" "2.18"; then
        patch_old_binutils "$ver" "$src"
    fi

    # All versions: BSD sys_nsig linkage fix (sentinel-guarded, safe to repeat).
    _sed_patch_strsignal_netbsd "$src"
    # All versions: allow gas+ld for alpha-dec-osf cross builds.
    _patch_binutils_configure_alpha_osf "$src"
    # All versions: fix sh64elf.em missing EOF heredoc terminator (NetBSD sh).
    _patch_binutils_sh64elf "$src"

    # Already installed?
    # SOM targets (hppa-hpux): GNU ld has no SOM emulation; only -as is built.
    local _need_ld=1
    [ "${TARGET_ABI:-}" = "som" ] && _need_ld=0
    if [ -f "$prefix/bin/${target}-as" ] && { [ "$_need_ld" -eq 0 ] || [ -f "$prefix/bin/${target}-ld" ]; }; then
        log "binutils $ver for $target already installed in $prefix"
        return 0
    fi

    log "Configuring binutils $ver for target $target..."

    mkdir -p "$bld"

    local sysroot_flag=""
    if [ -d "$sysroot" ]; then
        sysroot_flag="--with-sysroot=$sysroot"
    fi

    # Determine if the target needs --enable-targets=all for SOM/XCOFF support
    local extra_targets=""
    case "$TARGET_ABI" in
        som)  extra_targets="--enable-targets=all" ;;
        xcoff) extra_targets="--enable-targets=all" ;;
    esac

    # binutils < 2.20 for sparc targets: elfxx-sparc.c references 64-bit BFD
    # functions (bfd_elf64_swap_*) from elf64-sparc.c even for 32-bit-only builds.
    # sparc64-unknown-linux-gnu pulls in elf64-sparc without building unrelated
    # targets (m32c, sh64) that have linker or shell compatibility issues on BSD.
    if _gcc_ver_lt "$ver" "2.20"; then
        case "$target" in
            sparc*) extra_targets="--enable-targets=sparc64-unknown-linux-gnu" ;;
        esac
    fi

    # Old binutils (< 2.17) config.sub doesn't recognise modern host triples
    # like x86_64-unknown-linux-gnu or amd64-unknown-netbsd*.  Substitute a
    # known-good triple when no explicit host_flag was given (i.e. not a
    # Canadian cross).  Use i686-linux (not i486-linux) so that when the
    # target is also i486-linux the host != target, keeping a cross build.
    local _cfg_host_flags="${host_flag:-}"
    if [ -z "$_cfg_host_flags" ] && _gcc_ver_lt "$ver" "2.17"; then
        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64) _cfg_host_flags="--host=i686-linux --build=i686-linux" ;;
        esac
    fi

    (cd "$bld" && "$src/configure" \
        --target="$target" \
        --prefix="$prefix" \
        ${_cfg_host_flags} \
        $sysroot_flag \
        --disable-nls \
        --disable-werror \
        --disable-gdb \
        --disable-gdbserver \
        --disable-sim \
        --disable-readline \
        --with-system-zlib \
        $extra_targets \
        ${EXTRA_BINUTILS_OPTS:-} \
    ) || {
        echo "ERROR: binutils configure failed" >&2
        return 1
    }

    log "Building binutils $ver for $target (jobs: $MAKE_JOBS)..."
    # MAKEINFO=true: skip documentation build (makeinfo may not be installed).
    # CFLAGS=-fcommon: binutils < 2.20 define variables in headers without
    # 'static', causing multiple-definition link errors with GCC 10+ which
    # defaults to -fno-common.
    local _make_cflags=""
    _gcc_ver_lt "$ver" "2.20" && _make_cflags="CFLAGS=-fcommon"
    (cd "$bld" && "${MAKE:-make}" -j"$MAKE_JOBS" MAKEINFO=true ${_make_cflags}) || {
        echo "ERROR: binutils build failed" >&2
        return 1
    }

    log "Installing binutils $ver to $prefix..."
    # Use -k (keep going) so a read-only share/info failure doesn't abort before
    # the cross assembler and linker are placed in $prefix/bin.
    (cd "$bld" && "${MAKE:-make}" -k install MAKEINFO=true) || \
        log "binutils install exited non-zero; checking if tools were installed..."
    if [ ! -f "$prefix/bin/${target}-as" ]; then
        echo "ERROR: binutils install failed (as not installed)" >&2
        return 1
    fi
    # SOM targets (hppa-hpux) have no GNU ld support; skip ld check.
    if [ "$_need_ld" -eq 1 ] && [ ! -f "$prefix/bin/${target}-ld" ]; then
        echo "ERROR: binutils install failed (ld not installed)" >&2
        return 1
    fi

    log "binutils $ver for $target installed successfully"
}

# Patch binutils configure so alpha*-dec-osf* cross builds include gas and ld.
# Native alpha-osf builds legitimately exclude them (ld lacks shared-lib support,
# gas lacks exception info), but cross builds need both assembler and linker.
_patch_binutils_configure_alpha_osf() {
    local src="$1"
    local f="$src/configure"
    [ -f "$f" ] || return 0
    grep -q 'alpha_osf_cross_patched_' "$f" 2>/dev/null && return 0
    # The line `    noconfigdirs="$noconfigdirs gas ld"` inside alpha*-dec-osf*
    # must be wrapped in is_cross_compiler check for cross builds to get gas+ld.
    grep -q '^    noconfigdirs="\$noconfigdirs gas ld"$' "$f" 2>/dev/null || return 0
    local _tmp
    _tmp=$(mktemp "${TMPDIR:-/tmp}/bnutilsconfXXXXXX")
    awk '
/^    noconfigdirs="\$noconfigdirs gas ld"$/ && !done {
    print "    # For native alpha-dec-osf builds: ld lacks shared lib support,"
    print "    # gas lacks exception info. For cross builds (is_cross_compiler=yes),"
    print "    # both are needed and functional. # alpha_osf_cross_patched_"
    print "    if test x\"$is_cross_compiler\" != xyes; then"
    print "      " substr($0, 5)
    print "    fi"
    done=1; next
}
{ print }
' "$f" > "$_tmp" && mv "$_tmp" "$f" && chmod a+x "$f" || true
    log "  binutils configure: alpha-dec-osf cross build patched"
}

# Fix sh64elf.em: the heredoc (cat >>... <<EOF) at line 28 lacks a closing EOF
# marker, causing POSIX-strict /bin/sh (e.g. NetBSD's sh) to abort with
# "Syntax error: EOF reading here (<<) document". Append the marker.
_patch_binutils_sh64elf() {
    local src="$1"
    local f="$src/ld/emultempl/sh64elf.em"
    [ -f "$f" ] || return 0
    grep -q 'sh64elf_eof_patched_' "$f" 2>/dev/null && return 0
    grep -q '^EOF$' "$f" 2>/dev/null && return 0
    printf '\nEOF\n# sh64elf_eof_patched_\n' >> "$f" 2>/dev/null || true
    log "  binutils sh64elf.em: closing EOF marker appended"
}
