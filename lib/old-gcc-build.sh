#!/bin/sh
# lib/old-gcc-build.sh - Build procedures for GCC 1.x and early GCC 2.x.
#
# GCC version routing (called from build-gcc.sh):
#   GCC 1.x       (1987-1992)  → build_gcc_era1()        K&R C; needs bootstrap GCC
#   GCC 2.0-2.4   (1992-1993)  → build_gcc_era2_early()  early 2.x; needs bootstrap GCC
#   GCC 2.5-2.8   (1994-1998)  → build_gcc_era2_late()   late 2.x; builds with patches only
#   GCC 2.95+                  → main build-gcc.sh build_gcc()
#
# HOST REQUIREMENTS:
#   GCC 1.x:      Requires bootstrap GCC 2.7.2.3 as intermediate compiler.
#                 Built automatically by lib/bootstrap-gcc.sh when needed.
#   GCC 2.0-2.4:  Requires bootstrap GCC 2.7.2.3 on hosts with GCC >= 7.
#                 Automatically used when K&R C test fails.
#   GCC 2.5-2.8:  Builds with modern host GCC + patches.
#
# PATCH FILES (from patches/ directory):
#   gcc-1.40-cross-linux.patch      GCC 1.40 cross-compiler issues
#   gcc-1.42-cross-linux.patch      GCC 1.42 cross-compiler issues
#   gcc-2.3.3-cross-linux.patch     GCC 2.3.3 issues
#   gcc-2.5.8-cross-linux.patch     GCC 2.5.8 issues
#   gcc-2.7.2.3-cross-linux.patch   GCC 2.7.2.3 cross issues
#   binutils-2.5.2-modern-linux.patch
#   binutils-2.7-modern-linux.patch
#   binutils-2.8.1-modern-linux.patch

# ---------------------------------------------------------------------------
# GCC 1.x  (1.27 through 1.42, 1987-1992)
# ---------------------------------------------------------------------------
build_gcc_era1() {
    local gcc_ver="$1"
    local target="$2"
    local prefix="$3"
    local sysroot="$4"
    local srcdir="$5"
    local builddir="$6"

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would build GCC $gcc_ver (era1) for $target"; return 0; }

    local src="$srcdir/gcc-${gcc_ver}"

    if [ ! -d "$src" ]; then
        echo "ERROR: GCC $gcc_ver source not found at $src" >&2
        return 1
    fi

    # On BSD hosts, COMPAT_LINUX32 may not be configured, so the bootstrap GCC
    # (i686-pc-linux-gnu Linux ELF) cannot link host executables.  Use the system
    # GCC directly when it supports K&R C (GCC 5+ handles K&R with -w).
    # On Linux, always use bootstrap GCC 2.7.2.3 to avoid glibc/K&R C issues.
    local era1_cc
    local _era1_use_bootstrap=1
    case "$(uname -s 2>/dev/null)" in
        *BSD|DragonFly)
            if _host_cc_handles_knr; then
                era1_cc="${HOST_CC:-gcc}"
                _era1_use_bootstrap=0
                log "BSD host: using system GCC for GCC $gcc_ver era1 build."
            fi
            ;;
    esac

    if [ "$_era1_use_bootstrap" -eq 1 ]; then
        # GCC 1.x is K&R C throughout; always use the bootstrap GCC 2.7.2.3 as HOST_CC.
        log "GCC $gcc_ver is era1 (K&R C); ensuring bootstrap GCC $BOOTSTRAP_GCC_VER is available..."
        ensure_bootstrap_gcc || {
            echo "ERROR: Bootstrap GCC $BOOTSTRAP_GCC_VER is required to build GCC $gcc_ver." >&2
            echo "       The bootstrap build failed.  See above for details." >&2
            return 1
        }
        era1_cc="$BOOTSTRAP_GCC_CC"
    fi
    log "Using $era1_cc to compile GCC $gcc_ver source."

    # GCC 1.x is built in-source (no VPATH / out-of-tree support)
    local bld="$builddir/gcc-${gcc_ver}-${target}-src"
    if [ -d "$bld" ]; then
        rm -rf "$bld"
    fi
    log "Copying GCC $gcc_ver source for in-source build..."
    cp -rp "$src" "$bld" || { echo "ERROR: Failed to copy GCC source" >&2; return 1; }

    # Apply patches using patch file first, then sed fallbacks
    _patch_gcc_era1 "$gcc_ver" "$bld"

    log "Configuring GCC $gcc_ver for target $target..."

    # GCC 1.x configure is a hand-written shell script (config.gcc).
    # It takes a positional MACHINE name, not --target=. Derive the machine
    # name from the target triple: map i486/i586→i386 and simplify the OS part.
    local machine_arg
    machine_arg=$(echo "$target" | sed \
        -e 's/^i[456]86-/i386-/' \
        -e 's/-pc-linux.*$/-linux/' \
        -e 's/-linux-.*$/-linux/' \
        -e 's/-unknown-linux.*$/-linux/')
    local configure_done=0
    if [ -f "$bld/configure" ] || [ -f "$bld/config.gcc" ]; then
        # GCC 1.42+ ships a 'configure' wrapper; 1.40 and earlier only have
        # 'config.gcc'.  Both accept a positional machine name argument.
        local cfg_script="configure"
        [ -f "$bld/configure" ] || cfg_script="config.gcc"
        log "Invoking GCC 1.x $cfg_script with machine: $machine_arg"
        (cd "$bld" && \
            CFLAGS="$(_era1_cflags)" \
            CC="$era1_cc" \
            sh "$cfg_script" "$machine_arg" \
        ) && configure_done=1 || true
        # Patch the prefix into the Makefile config.gcc produced
        if [ "$configure_done" -eq 1 ] && [ -f "$bld/Makefile" ]; then
            sed -i.bak "s|^prefix = .*|prefix = $prefix|" "$bld/Makefile" || true
        fi
    fi

    if [ "$configure_done" -eq 0 ]; then
        _configure_gcc_1x_manual "$bld" "$target" "$prefix" "$era1_cc"
    fi

    log "Building GCC $gcc_ver for $target..."

    local cross_prefix="${target}-"
    (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="$era1_cc" \
            CFLAGS="$(_era1_cflags)" \
            CROSS_COMPILE="$cross_prefix" \
            LANGUAGES="c" \
            BISON="bison -y" \
            LEX="flex" \
    ) || {
        echo "ERROR: GCC $gcc_ver build failed." >&2
        echo "" >&2
        echo "Troubleshooting:" >&2
        echo "  1. Check $bld/config.log for configure errors" >&2
        echo "  2. The bootstrap compiler was: $era1_cc" >&2
        echo "  3. Apply additional patches from patches/gcc-${gcc_ver}-cross-linux.patch" >&2
        echo "     and re-run: ${0} -g $gcc_ver $(echo $target | sed 's/-.*//')" >&2
        return 1
    }

    log "Installing GCC $gcc_ver to $prefix..."
    # GCC 1.x Makefile has no 'prefix =' variable; libdir/bindir are set to
    # $(prefix)/usr/local/{lib,bin} where prefix defaults to empty = /usr/local.
    # Override them directly so the install lands in our prefix.
    mkdir -p "$prefix/bin" "$prefix/lib" "$prefix/share/man/man1"
    (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="$era1_cc" \
            CROSS_COMPILE="$cross_prefix" \
            LANGUAGES="c" \
            libdir="$prefix/lib" \
            bindir="$prefix/bin" \
            mandir="$prefix/share/man/man1" \
            install \
    ) || {
        # If make install fails (permissions, missing targets), do minimal copy
        log "make install failed; trying manual copy of cc1/cpp/gcc/gnulib..."
        for f in cc1 cpp gcc; do
            [ -f "$bld/$f" ] && install -m 0755 "$bld/$f" "$prefix/bin/gcc-1.${gcc_ver#*.}-$f" || true
        done
        [ -f "$bld/cc1" ] && install -m 0755 "$bld/cc1" "$prefix/lib/gcc-cc1" || true
        [ -f "$bld/gnulib" ] && install -m 0644 "$bld/gnulib" "$prefix/lib/gcc-gnulib" || true
    }

    log "GCC $gcc_ver (era1) for $target installed."
}

# Manual configuration for GCC 1.x versions without --target= support
_configure_gcc_1x_manual() {
    local bld="$1"
    local target="$2"
    local prefix="$3"
    local cc="$4"

    log "GCC 1.x manual configuration for $target..."

    local cpu
    cpu=$(echo "$target" | cut -d- -f1)

    local md_cpu
    case "$cpu" in
        sparc*)          md_cpu="sparc"   ;;
        m68k|m68020)     md_cpu="m68k"    ;;
        i386|i486|i586)  md_cpu="i386"    ;;
        vax)             md_cpu="vax"     ;;
        ns32k)           md_cpu="ns32k"   ;;
        rs6000|powerpc)  md_cpu="rs6000"  ;;
        mips*)           md_cpu="mips"    ;;
        *)               md_cpu="$cpu"    ;;
    esac

    # Create necessary header symlinks that configure normally sets up.
    # GCC 1.42+ uses config/<cpu>.h; GCC 1.40 uses config/tm-<cpu>*.h.
    if [ -f "$bld/config/$md_cpu.h" ]; then
        ln -sfn "config/$md_cpu.h" "$bld/tm.h" 2>/dev/null || true
    elif [ -f "$bld/config/$md_cpu/$md_cpu.h" ]; then
        ln -sfn "config/$md_cpu/$md_cpu.h" "$bld/tm.h" 2>/dev/null || true
    elif [ -f "$bld/config/tm-${md_cpu}gas.h" ]; then
        ln -sfn "config/tm-${md_cpu}gas.h" "$bld/tm.h" 2>/dev/null || true
    elif [ -f "$bld/config/tm-${md_cpu}.h" ]; then
        ln -sfn "config/tm-${md_cpu}.h" "$bld/tm.h" 2>/dev/null || true
    else
        echo "WARNING: No tm.h found for cpu $md_cpu; build may fail" >&2
    fi

    # Host machine description — use the bootstrap GCC's host
    local host_triple
    host_triple=$("$cc" -dumpmachine 2>/dev/null || echo "i686-linux")
    local host_cpu
    host_cpu=$(echo "$host_triple" | cut -d- -f1)
    for xm_candidate in \
            "$bld/config/xm-linux.h" \
            "$bld/config/${host_cpu}/xm-linux.h" \
            "$bld/config/xm-${host_cpu}.h"; do
        if [ -f "$xm_candidate" ]; then
            ln -sfn "$xm_candidate" "$bld/xm.h" 2>/dev/null || true
            break
        fi
    done

    # Minimal config.h for GCC 1.x
    cat > "$bld/config.h" <<EOF
#define HOST_BITS_PER_CHAR  8
#define HOST_BITS_PER_SHORT 16
#define HOST_BITS_PER_INT   32
#define HOST_BITS_PER_LONG  32
#define HAVE_ALLOCA_H   1
#define HAVE_STDLIB_H   1
#define HAVE_STRING_H   1
#define HAVE_UNISTD_H   1
#define HAVE_VPRINTF    1
#define HAVE_PUTENV     1
#define HAVE_STRSIGNAL  1
EOF

    # Patch the Makefile prefix
    if [ -f "$bld/Makefile.in" ]; then
        sed -e "s|^prefix *=.*|prefix = $prefix|" \
            -e "s|^CC *=.*|CC = $cc|" \
            "$bld/Makefile.in" > "$bld/Makefile"
    elif [ -f "$bld/Makefile" ]; then
        sed -i.bak \
            -e "s|^prefix *=.*|prefix = $prefix|" \
            -e "s|^CC *=.*|CC = $cc|" \
            "$bld/Makefile"
    fi
}

# On BSD: GCC 1.x ships its own stddef.h in the build dir. When compiled with
# system GCC and -I., #include <stddef.h> finds the local copy first, which
# redefines size_t/ptrdiff_t/wchar_t that system headers already defined —
# "conflicting types" errors. Replace with a #include_next wrapper so system
# GCC finds the real stddef.h without the redefinition conflict.
_bsd_patch_era1_stddef() {
    local src="$1"
    local f="$src/stddef.h"
    [ -f "$f" ] || return 0
    case "$(uname -s 2>/dev/null)" in
        *BSD|DragonFly) ;;
        *) return 0 ;;
    esac
    grep -q 'bsd_stddef_patched_' "$f" 2>/dev/null && return 0
    printf '/* bsd_stddef_patched_ */\n#pragma GCC system_header\n#include_next <stddef.h>\n' > "$f" 2>/dev/null || true
    log "  era1 stddef.h: replaced with #include_next wrapper (BSD)"
}

# ---------------------------------------------------------------------------
# Patches for GCC 1.x
# ---------------------------------------------------------------------------
_patch_gcc_era1() {
    local gcc_ver="$1"
    local src="$2"

    # Apply before the stamp check so it survives already-patched source trees.
    _sed_patch_strsignal_types "$src"
    _sed_patch_strsignal_netbsd "$src"
    # On BSD with system GCC: local stddef.h conflicts with system headers.
    _bsd_patch_era1_stddef "$src"

    [ -f "$src/.era1_patches_applied" ] && return 0
    log "Applying GCC $gcc_ver era1 compatibility patches..."

    chmod -R u+w "$src" 2>/dev/null || true
    _update_config_scripts "$src"

    # 1. Try the dedicated patch file first
    local patchfile="$SCRIPT_DIR/patches/gcc-${gcc_ver}-cross-linux.patch"
    if [ -f "$patchfile" ]; then
        log "Applying patch file: $patchfile"
        (cd "$src" && sed -n '/^--- /,$p' "$patchfile" | \
            patch -p1 -t -N -r /dev/null > /dev/null 2>&1) || true
    fi

    # 2. Sed-based patches as reliable fallback / supplement
    _sed_patch_getline        "$src"
    _sed_patch_alloca         "$src"
    _sed_patch_sys_nerr       "$src"
    _sed_patch_disable_werror "$src"
    _sed_patch_bcopy_shims    "$src"

    # 3. Add system includes to core source files that lack them
    for f in \
            "$src/gcc.c" "$src/cccp.c" "$src/cpplib.c" \
            "$src/toplev.c" "$src/emit-rtl.c" "$src/expmed.c" \
            "$src/stor-layout.c"; do
        [ -f "$f" ] || continue
        grep -q '#include.*stdio' "$f" 2>/dev/null && continue
        sed -i.bak \
            '1i#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>' \
            "$f" 2>/dev/null || true
    done

    # 3b. errno.h: GCC 1.x source uses errno but doesn't include errno.h on non-VMS
    # platforms (relies on implicit extern int errno which fails on NetBSD where
    # errno is the macro (*__errno())).  Add unconditional include at top.
    # Note: cccp.c has #include <errno.h> inside #ifdef VMS only — not sufficient.
    for f in "$src/gcc.c" "$src/cccp.c"; do
        [ -f "$f" ] || continue
        grep -q '\berrno\b' "$f" 2>/dev/null || continue
        grep -q 'errno_h_era1_patched_' "$f" 2>/dev/null && continue
        awk 'NR==1{print "/* errno_h_era1_patched_ */"; print "#include <errno.h>"} {print}' \
            "$f" > "$f.errtmp" && mv "$f.errtmp" "$f" || true
    done

    # 3d. S_IFMT/S_IFREG: not exposed by sys/stat.h under -ansi -D_POSIX_SOURCE
    # (glibc guards them with __USE_MISC).  Add fallback defines using canonical
    # POSIX/SVID bit values so gcc.c compiles without enabling full __USE_MISC.
    for f in "$src/gcc.c" "$src/gcc/gcc.c"; do
        [ -f "$f" ] || continue
        grep -q '\bS_IFMT\b\|\bS_IFREG\b' "$f" 2>/dev/null || continue
        grep -q 'S_IFMT_era1_patched_' "$f" 2>/dev/null && continue
        sed -i.bak \
            '1i/* S_IFMT_era1_patched_ */\n#ifndef S_IFMT\n# define S_IFMT  0170000\n# define S_IFREG 0100000\n# define S_IFDIR 0040000\n# define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)\n# define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)\n#endif' \
            "$f" 2>/dev/null || true
    done

    # 4. BSD index/rindex → strchr/strrchr shims
    for f in $(find "$src" -name '*.c' -maxdepth 2 2>/dev/null); do
        grep -l '\brindex\b\|\bindex\b' "$f" 2>/dev/null | while read rf; do
            grep -q '#define.*rindex\|strrchr.*rindex' "$rf" 2>/dev/null && continue
            sed -i.bak \
                '1i#ifndef rindex\n#define rindex(s,c) strrchr((s),(c))\n#define index(s,c)  strchr((s),(c))\n#endif' \
                "$rf" 2>/dev/null || true
        done
    done

    # 5. obstack.h multiple-inclusion guard (only if no existing guard)
    local ob="$src/obstack.h"
    if [ -f "$ob" ]; then
        grep -q '_GCC1_OBSTACK_H\|_OBSTACK_H\|__OBSTACKS__' "$ob" 2>/dev/null || {
            printf '#ifndef _GCC1_OBSTACK_H\n#define _GCC1_OBSTACK_H 1\n' | \
                cat - "$ob" > "$ob.tmp" && mv "$ob.tmp" "$ob"
            printf '\n#endif /* _GCC1_OBSTACK_H */\n' >> "$ob"
        }
    fi

    # 6. Add i*86-linux support to config.gcc (GCC 1.x predates Linux).
    #    Use i386-mach config (GAS assembler, no System V specifics) as base.
    local cfg_gcc="$src/config.gcc"
    if [ -f "$cfg_gcc" ] && ! grep -q 'i386-linux\|i486-linux' "$cfg_gcc"; then
        awk '
/^\ti386-mach\)$/ {
    print "\ti[3456]86-linux | i[3456]86-linux-gnu | i[3456]86-pc-linux-gnu)"
    print "\t\tcpu_type=i386"
    print "\t\tconfiguration_file=xm-i386.h"
    print "\t\ttarget_machine=tm-i386gas.h"
    print "\t\t;;"
    print $0; next
}
{ print }
' "$cfg_gcc" > "$cfg_gcc.tmp" && mv "$cfg_gcc.tmp" "$cfg_gcc" && chmod +x "$cfg_gcc" || true
        log "  Patched config.gcc for i*86-linux targets"
    fi

    touch "$src/.era1_patches_applied"
}

# Return extra CFLAGS needed when building old GCC with bootstrap GCC 2.7.x on
# BSD hosts. Modern BSD system headers require built-in types that old compilers
# don't define:
#   __WINT_TYPE__: NetBSD 7+ sys/common_ansi.h errors if not set by compiler.
#   __builtin_va_list: NetBSD sys/ansi.h typedef requires this; use char* proxy.
_bsd_host_wint_define() {
    case "$(uname -s 2>/dev/null)" in
        *BSD|DragonFly) ;;
        *) return 0 ;;
    esac
    local _wt
    _wt=$(echo "int x;" | ${HOST_CC:-gcc} -x c -dM -E - 2>/dev/null | \
          awk '/__WINT_TYPE__/{print $3; exit}')
    [ -n "$_wt" ] && printf ' -D__WINT_TYPE__=%s' "$_wt"
    printf ' -D__builtin_va_list=char*'
    # GCC 2.7.2.3 (bootstrap) does not know the __strftime__ format archetype;
    # NetBSD time.h uses __attribute__((__format__(__strftime__,...))) which
    # causes hard errors even with -w.  Map to printf (close enough, accepted).
    printf ' -D__strftime__=printf'
}

# CFLAGS for building GCC 1.x source (passed to the bootstrap GCC 2.7.2.3).
# IMPORTANT: Only use flags supported by GCC 2.7.2.3 (1997); modern flags like
# -fgnu89-inline, -fpermissive, -Wno-int-conversion are NOT available there.
# -ansi: defines __STRICT_ANSI__ which prevents glibc from enabling __USE_MISC,
# keeping strings.h (with __nonnull attrs unknown to GCC 2.7.2.3) from being
# pulled in transitively by string.h.
_era1_cflags() {
    case "$(uname -s 2>/dev/null)" in
        *BSD|DragonFly)
            # BSD with system GCC: -fcommon allows multiple tentative definitions
            # (GCC 10+ defaults to -fno-common; GCC 1.x source uses common linkage).
            # -fgnu89-inline: GCC 1.x uses __inline without static/extern; C17 mode
            # treats that as "inline definition only" (not emitted), breaking links.
            # -m32: GCC 1.x gen* tools assume 32-bit pointer size; 64-bit hosts segfault.
            # No -ansi/-D_POSIX_SOURCE (Linux/glibc workarounds that break BSD errno).
            # No _bsd_host_wint_define() defines: system GCC already provides these.
            local _bsd_m32=""
            case "$(uname -m 2>/dev/null)" in
                x86_64|amd64) _bsd_m32=" -m32" ;;
            esac
            echo "-O0 -w -fcommon -fgnu89-inline${_bsd_m32}"
            ;;
        *)
            # -ansi: prevents glibc from including strings.h (via __STRICT_ANSI__)
            # -D_POSIX_SOURCE: restores R_OK/W_OK/X_OK and errno from POSIX headers
            echo "-O0 -w -ansi -D_POSIX_SOURCE"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# GCC 2.0-2.4  (era2-early, 1992-1993)
# ---------------------------------------------------------------------------
build_gcc_era2_early() {
    local gcc_ver="$1"
    local target="$2"
    local prefix="$3"
    local sysroot="$4"
    local srcdir="$5"
    local builddir="$6"
    local build_runtime="${7:-}"

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would build GCC $gcc_ver (era2-early) for $target"; return 0; }

    local src="$srcdir/gcc-${gcc_ver}"
    local bld="$builddir/gcc-${gcc_ver}-${target}"

    if [ ! -d "$src" ]; then
        echo "ERROR: GCC $gcc_ver source not found at $src" >&2
        return 1
    fi

    if [ -f "$prefix/bin/${target}-gcc" ]; then
        log "GCC $gcc_ver for $target already installed"
        return 0
    fi

    # Decide whether to use the bootstrap GCC.
    # On BSD: bootstrap GCC (i686-pc-linux-gnu ELF) may not run without COMPAT_LINUX32.
    # Use system GCC directly when it handles K&R C.
    # On Linux: use bootstrap on GCC 7+ hosts (K&R issues amplify with modern glibc).
    local use_cc="${HOST_CC:-gcc}"
    local _era2e_use_bootstrap=1
    case "$(uname -s 2>/dev/null)" in
        *BSD|DragonFly) _era2e_use_bootstrap=0 ;;
    esac

    if [ "$_era2e_use_bootstrap" -eq 1 ]; then
        local host_major
        host_major=$("$use_cc" -dumpversion 2>/dev/null | cut -d. -f1)
        if [ "${host_major:-0}" -ge 7 ] 2>/dev/null || \
           ! _host_cc_handles_knr 2>/dev/null; then
            log "Host GCC $host_major: K&R C may fail; using bootstrap GCC $BOOTSTRAP_GCC_VER..."
            ensure_bootstrap_gcc || {
                echo "WARNING: Bootstrap GCC unavailable; proceeding with host GCC (may fail)" >&2
            }
            [ -n "$BOOTSTRAP_GCC_CC" ] && use_cc="$BOOTSTRAP_GCC_CC"
        fi
    fi

    _patch_gcc_era2_early "$gcc_ver" "$src"

    log "Configuring GCC $gcc_ver (early 2.x) for target $target..."
    mkdir -p "$bld"

    local sysroot_flag=""
    [ -d "$sysroot" ] && sysroot_flag="--with-sysroot=$sysroot"

    # When bootstrap GCC 2.7.2.3 is the compiler, use only flags it supports.
    # Modern flags like -fgnu89-inline / -fpermissive / -Wno-int-conversion
    # were not present in 1997-era GCC and cause "Invalid option" errors.
    #
    # Modern glibc's /usr/include/limits.h:124 does #include_next <limits.h>.
    # Bootstrap GCC 2.7.2.3 has no private limits.h, so #include_next fails.
    # GCC 11's private limits.h also does #include_next, breaking the chain.
    # Fix: install glimits.h from the bootstrap GCC source (self-contained,
    # no #include_next) into a wrapper dir and point -idirafter at that dir.
    local cflags
    if [ -n "$BOOTSTRAP_GCC_CC" ] && [ "$use_cc" = "$BOOTSTRAP_GCC_CC" ]; then
        local _idirafter_dir="$bld/bootstrap-includes"
        mkdir -p "$_idirafter_dir"
        local _glimits="$CROSS_SRCDIR/gcc-${BOOTSTRAP_GCC_VER}/glimits.h"
        if [ -f "$_glimits" ] && [ ! -f "$_idirafter_dir/limits.h" ]; then
            cp "$_glimits" "$_idirafter_dir/limits.h"
        fi
        local _wint_flag
        _wint_flag=$(_bsd_host_wint_define)
        if [ -f "$_idirafter_dir/limits.h" ]; then
            cflags="-O1 -w -idirafter $_idirafter_dir${_wint_flag}"
        else
            cflags="-O1 -w${_wint_flag}"
        fi
    else
        cflags=$(_era2_early_cflags "$gcc_ver")
    fi

    # GCC 2.0-2.2: configure used positional args; GCC 2.3+ added --target=
    if _gcc_ver_lt "$gcc_ver" "2.3"; then
        local host_triple
        host_triple=$("$use_cc" -dumpmachine 2>/dev/null || echo "i686-pc-linux-gnu")
        (cd "$bld" && \
            CFLAGS="$cflags" \
            CC="$use_cc" \
            "$src/configure" \
                "$host_triple" \
                "$target" \
                --prefix="$prefix" \
                $sysroot_flag \
        ) || {
            log "Positional configure failed; retrying with --target=..."
            (cd "$bld" && \
                CFLAGS="$cflags" \
                CC="$use_cc" \
                "$src/configure" \
                    --target="$target" \
                    --prefix="$prefix" \
                    $sysroot_flag \
            ) || { echo "ERROR: GCC $gcc_ver configure failed" >&2; return 1; }
        }
    else
        (cd "$bld" && \
            CFLAGS="$cflags" \
            CC="$use_cc" \
            "$src/configure" \
                --target="$target" \
                --prefix="$prefix" \
                $sysroot_flag \
                ${EXTRA_GCC_OPTS:-} \
        ) || { echo "ERROR: GCC $gcc_ver configure failed" >&2; return 1; }
    fi

    log "Building GCC $gcc_ver for $target (serial, era2-early)..."
    (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="$use_cc" \
            CFLAGS="$cflags" \
            LANGUAGES="c" \
            BISON="bison -y" \
            LEX="flex" \
            all-gcc \
    ) || (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="$use_cc" \
            CFLAGS="$cflags" \
            LANGUAGES="c" \
            BISON="bison -y" \
            LEX="flex" \
            xgcc cc1 cpp \
    ) || { echo "ERROR: GCC $gcc_ver build failed" >&2; return 1; }

    log "Installing GCC $gcc_ver to $prefix..."
    # GCC 2.3-2.4 have no install-gcc target; make install tries to build
    # libgcc2.a (needs target libc) and enquire.o (FP probe) — both fail.
    # Manual install: copy the binaries we actually built.
    local _libsubdir="$prefix/lib/gcc-lib/$target/$gcc_ver"
    mkdir -p "$prefix/bin" "$_libsubdir"
    if [ -f "$bld/xgcc" ]; then
        install -m 0755 "$bld/xgcc" "$prefix/bin/${target}-gcc"
    fi
    for _f in cc1 cpp; do
        [ -f "$bld/$_f" ] && install -m 0755 "$bld/$_f" "$_libsubdir/$_f" || true
    done
    if [ ! -f "$prefix/bin/${target}-gcc" ]; then
        echo "ERROR: GCC $gcc_ver install failed (xgcc not built)" >&2
        return 1
    fi

    log "GCC $gcc_ver (era2-early) for $target installed."
}

_patch_gcc_era2_early() {
    local gcc_ver="$1"
    local src="$2"

    # Apply before the stamp check so it survives already-patched source trees.
    _sed_patch_strsignal_types "$src"
    _sed_patch_strsignal_netbsd "$src"
    _bsd_patch_hz "$src"
    _patch_gvarargs_ellipsis "$src"

    [ -f "$src/.era2_early_patches_applied" ] && return 0
    log "Applying GCC $gcc_ver era2-early compatibility patches..."

    chmod -R u+w "$src" 2>/dev/null || true
    _update_config_scripts "$src"

    # Try dedicated patch file first
    local patchfile="$SCRIPT_DIR/patches/gcc-${gcc_ver}-cross-linux.patch"
    if [ -f "$patchfile" ]; then
        log "Applying patch file: $patchfile"
        (cd "$src" && sed -n '/^--- /,$p' "$patchfile" | \
            patch -p1 -t -N -r /dev/null > /dev/null 2>&1) || true
    fi

    # Sed-based fallback patches
    _sed_patch_getline        "$src"
    _sed_patch_alloca         "$src"
    _sed_patch_strsignal      "$src"
    _sed_patch_sys_nerr       "$src"
    _sed_patch_disable_werror "$src"
    _sed_patch_bcopy_shims    "$src"

    # Add system includes to key files
    for f in "$src/gcc.c" "$src/toplev.c" "$src/cccp.c" "$src/cpplib.c"; do
        [ -f "$f" ] || continue
        grep -q '#include.*stdio' "$f" 2>/dev/null && continue
        awk 'NR==1{
            print "#include <stdio.h>"
            print "#include <string.h>"
            print "#include <stdlib.h>"
            print "#include <unistd.h>"
        } {print}' "$f" > "$f.inctmp" && mv "$f.inctmp" "$f" || true
    done

    # Fix yyerror declarations
    for f in $(find "$src" -name 'c-decl.c' -maxdepth 3 2>/dev/null); do
        grep -q 'void yyerror\|#ifndef yyerror' "$f" 2>/dev/null && continue
        sed -i.bak \
            's/^yyerror (s)$/void yyerror (s)/;
             s/^yyerror(s)$/void yyerror(s)/' \
            "$f" 2>/dev/null || true
    done

    # obstack.h guard
    for ob in "$src/obstack.h" "$src/include/obstack.h"; do
        [ -f "$ob" ] || continue
        grep -q '_OBSTACK_H\|_GCC_OBSTACK_H\|__OBSTACKS__' "$ob" 2>/dev/null && continue
        printf '#ifndef _GCC_OBSTACK_H\n#define _GCC_OBSTACK_H 1\n' | \
            cat - "$ob" > "$ob.tmp" && mv "$ob.tmp" "$ob"
        printf '\n#endif /* _GCC_OBSTACK_H */\n' >> "$ob"
    done

    touch "$src/.era2_early_patches_applied"
}

_era2_early_cflags() {
    printf '%s' "-O1 -w -fcommon -fgnu89-inline -fpermissive -fno-strict-aliasing"
    printf '%s' " -Wno-implicit-function-declaration"
    printf '%s' " -Wno-int-conversion"
    printf '%s' " -Wno-incompatible-pointer-types"
    echo ""
}

# ---------------------------------------------------------------------------
# GCC 2.5-2.8  (era2-late, 1994-1998)
# ---------------------------------------------------------------------------
build_gcc_era2_late() {
    local gcc_ver="$1"
    local target="$2"
    local prefix="$3"
    local sysroot="$4"
    local srcdir="$5"
    local builddir="$6"
    local build_runtime="${7:-}"

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would build GCC $gcc_ver (era2-late) for $target"; return 0; }

    local src="$srcdir/gcc-${gcc_ver}"
    local bld="$builddir/gcc-${gcc_ver}-${target}"

    if [ ! -d "$src" ]; then
        echo "ERROR: GCC $gcc_ver source not found: $src" >&2
        return 1
    fi

    if [ -f "$prefix/bin/${target}-gcc" ]; then
        log "GCC $gcc_ver for $target already installed"
        return 0
    fi

    _patch_gcc_era2_late "$gcc_ver" "$src"

    log "Configuring GCC $gcc_ver (late 2.x) for target $target..."
    mkdir -p "$bld"

    local sysroot_flag=""
    [ -d "$sysroot" ] && sysroot_flag="--with-sysroot=$sysroot"

    local cflags="-O1 -w -fgnu89-inline -fpermissive -fno-strict-aliasing"
    cflags="$cflags -Wno-implicit-function-declaration -Wno-int-conversion"

    # GCC 2.5.x configure only ignores --enable-*/--with-*; --disable-* triggers
    # "Invalid option".  These flags were added in GCC 2.7.
    local disable_flags=""
    if ! _gcc_ver_lt "$gcc_ver" "2.7"; then
        disable_flags="--disable-nls --disable-shared --disable-multilib"
    fi

    local _host_norm_flags=""
    case "$(uname -m 2>/dev/null)" in
        # GCC 2.5.8 configure only recognises i[34]86; 2.7+ recognises i[3456]86.
        # i486-linux is safe for the full era2-late range.
        # NetBSD reports amd64 where Linux reports x86_64 — handle both.
        x86_64|amd64) _host_norm_flags="--host=i486-linux --build=i486-linux" ;;
    esac

    (cd "$bld" && \
        CFLAGS_FOR_BUILD="$cflags" \
        CFLAGS="$cflags" \
        CC="${HOST_CC:-gcc}" \
        "$src/configure" \
            --target="$target" \
            --prefix="$prefix" \
            $_host_norm_flags \
            $sysroot_flag \
            $disable_flags \
            ${EXTRA_GCC_OPTS:-} \
    ) || { echo "ERROR: GCC $gcc_ver configure failed" >&2; return 1; }

    log "Building GCC $gcc_ver for $target (serial)..."
    (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="${HOST_CC:-gcc}" \
            CFLAGS="$cflags" \
            BISON="bison -y" \
            LEX="flex" \
            LANGUAGES="c" \
            all-gcc \
    ) || (cd "$bld" && \
        "${MAKE:-make}" -j1 \
            CC="${HOST_CC:-gcc}" \
            CFLAGS="$cflags" \
            BISON="bison -y" \
            LEX="flex" \
            LANGUAGES="c" \
            xgcc cc1 cpp \
    ) || { echo "ERROR: GCC $gcc_ver build failed" >&2; return 1; }

    log "Installing GCC $gcc_ver to $prefix..."
    if ! (cd "$bld" && "${MAKE:-make}" -j1 install-gcc 2>/dev/null); then
        log "install-gcc failed; doing manual install..."
        local _libsubdir="$prefix/lib/gcc-lib/$target/$gcc_ver"
        mkdir -p "$prefix/bin" "$_libsubdir"
        if [ -f "$bld/xgcc" ]; then
            install -m 0755 "$bld/xgcc" "$prefix/bin/${target}-gcc"
        fi
        for _f in cc1 cpp; do
            [ -f "$bld/$_f" ] && install -m 0755 "$bld/$_f" "$_libsubdir/$_f" || true
        done
    fi
    if [ ! -f "$prefix/bin/${target}-gcc" ]; then
        echo "ERROR: GCC $gcc_ver install failed" >&2
        return 1
    fi

    if [ -n "$build_runtime" ] && [ -d "$sysroot" ]; then
        log "Attempting cross libgcc build..."
        (cd "$bld" && "${MAKE:-make}" -j1 all-target-libgcc 2>/dev/null) && \
            (cd "$bld" && "${MAKE:-make}" -j1 install-target-libgcc) || \
            log "libgcc skipped (incomplete sysroot; use -r with full sysroot only)"
    fi

    log "GCC $gcc_ver (era2-late) for $target installed."
}

_patch_gcc_era2_late() {
    local gcc_ver="$1"
    local src="$2"

    # Apply these before the stamp check — each uses its own internal guard so
    # they can be applied even to source trees patched in earlier runs.
    _patch_obstack_lvalue "$src"
    _sed_patch_strsignal_types "$src"
    _sed_patch_strsignal_netbsd "$src"
    _sed_patch_mips_sigset "$src"
    _bsd_patch_hz "$src"
    _patch_gvarargs_ellipsis "$src"

    [ -f "$src/.era2_late_patches_applied" ] && return 0
    log "Applying GCC $gcc_ver era2-late compatibility patches..."

    chmod -R u+w "$src" 2>/dev/null || true
    _update_config_scripts "$src"

    # Dedicated patch file
    local patchfile="$SCRIPT_DIR/patches/gcc-${gcc_ver}-cross-linux.patch"
    if [ -f "$patchfile" ]; then
        log "Applying patch file: $patchfile"
        (cd "$src" && sed -n '/^--- /,$p' "$patchfile" | \
            patch -p1 -t -N -r /dev/null > /dev/null 2>&1) || true
    fi

    # Sed-based fallback patches
    _sed_patch_getline        "$src"
    _sed_patch_alloca         "$src"
    _sed_patch_strsignal      "$src"
    _sed_patch_sys_nerr       "$src"
    _sed_patch_disable_werror "$src"
    _sed_patch_fix_proto      "$src"
    _sed_patch_collect2       "$src"
    _sed_patch_bcopy_shims    "$src"

    # xm-linux.h HAVE_* defines for modern glibc
    _sed_patch_xm_linux "$src"

    touch "$src/.era2_late_patches_applied"
}

# ---------------------------------------------------------------------------
# Old binutils patches (binutils 2.5.2 - 2.9.1)
# Called from build-binutils.sh before configure.
# ---------------------------------------------------------------------------
patch_old_binutils() {
    local ver="$1"
    local src="$2"

    # These patches must survive already-patched source trees (the main sentinel
    # exits early otherwise) — apply before the sentinel check.
    _patch_libiberty_funcdef_sys_nerr "$src"
    _sed_patch_strsignal_types "$src"
    _sed_patch_strsignal_netbsd "$src"

    [ -f "$src/.old_binutils_patched" ] && return 0
    log "Applying old binutils $ver compatibility patches..."

    # Replace outdated config.guess/config.sub first (old versions don't know x86_64)
    chmod -R u+w "$src" 2>/dev/null || true
    _update_config_scripts "$src"

    # Fix targ_cpu extraction in bfd/config.bfd (and similar files).
    # Modern config.sub emits 4-part triples (e.g. i486-pc-linux-gnu); the old
    # greedy regex `^\(.*\)-\(.*\)-\(.*\)$` captures `i486-pc` as the CPU
    # instead of just `i486`, breaking BFD architecture lookup.
    _patch_bfd_targ_cpu "$src"

    # Fix GAS configure: extend i386-*-linux* patterns to cover i486/i586 too.
    # Modern config.sub returns i486-pc-linux-gnu for i486-linux, but gas only
    # had i386-*-linux* patterns.
    _patch_gas_configure "$src"

    # Fix GAS i386 struct/linkage issues for modern GCC.
    _patch_gas_i386_types "$src"

    # Try dedicated patch file first
    local patchfile="$SCRIPT_DIR/patches/binutils-${ver}-modern-linux.patch"
    if [ -f "$patchfile" ]; then
        log "Applying patch file: $patchfile"
        (cd "$src" && sed -n '/^--- /,$p' "$patchfile" | \
            patch -p1 -t -N -r /dev/null > /dev/null 2>&1) || true
    fi

    # Sed-based patches as reliable supplement
    _sed_patch_getline        "$src"
    _sed_patch_alloca         "$src"
    _sed_patch_strsignal      "$src"
    _sed_patch_sys_nerr       "$src"
    _sed_patch_disable_werror "$src"

    # obstack.h guard
    for ob in "$src/include/obstack.h" "$src/libiberty/obstack.h"; do
        [ -f "$ob" ] || continue
        grep -q '_BINUTILS_OBSTACK_H\|_OBSTACK_H\|__OBSTACKS__' "$ob" 2>/dev/null && continue
        printf '#ifndef _BINUTILS_OBSTACK_H\n#define _BINUTILS_OBSTACK_H 1\n' | \
            cat - "$ob" > "$ob.tmp" && mv "$ob.tmp" "$ob"
        printf '\n#endif /* _BINUTILS_OBSTACK_H */\n' >> "$ob"
    done

    # bfd/elf.c needs sys/stat.h
    local bfd_elf="$src/bfd/elf.c"
    if [ -f "$bfd_elf" ]; then
        grep -q '#include.*sys/stat' "$bfd_elf" 2>/dev/null || \
            awk 'NR==1{print "#include <sys/stat.h>"} {print}' \
                "$bfd_elf" > "$bfd_elf.tmp" && mv "$bfd_elf.tmp" "$bfd_elf" || true
    fi

    # gas/app.c: remove conflicting strsignal extern declaration
    local gas_app="$src/gas/app.c"
    if [ -f "$gas_app" ]; then
        sed -i.bak \
            '/^extern char \*strsignal/d;
             /^extern char \*psignal/d' \
            "$gas_app" 2>/dev/null || true
    fi

    touch "$src/.old_binutils_patched"
}

# Fix greedy targ_cpu sed regex in bfd/config.bfd (and any configure that
# sources it).  Old regex: `^\(.*\)-\(.*\)-\(.*\)$` → greedily captures
# `i486-pc` from `i486-pc-linux-gnu`.  New: `^\([^-]*\)-.*` → just `i486`.
_bfd_litrepl() {
    OLD_STR="$1" NEW_STR="$2" \
    awk 'BEGIN { o = ENVIRON["OLD_STR"]; n = ENVIRON["NEW_STR"]; ol = length(o) }
         { out = ""; s = $0
           while ((i = index(s, o)) > 0) { out = out substr(s, 1, i-1) n; s = substr(s, i+ol) }
           print out s }' "$3"
}

_patch_bfd_targ_cpu() {
    local src="$1"
    for f in "$src/bfd/config.bfd" "$src/opcodes/configure" "$src/configure" "$src/gas/configure"; do
        [ -f "$f" ] || continue
        grep -q 'bfd_targ_cpu_patched' "$f" 2>/dev/null && continue
        grep -q "sed 's/\^\\\\(.*\\\\)-\\\\(.*\\\\)-\\\\(.*\\\\)" "$f" 2>/dev/null || continue
        _tmp=$(mktemp "${TMPDIR:-/tmp}/targ_cpu_XXXXXX") || true
        cp "$f" "$_tmp"
        # Fix greedy \1 form: host_cpu/target_cpu/build_cpu extractions
        if grep -qF "sed 's/^\(.*\)-\(.*\)-\(.*\)$/\1/'" "$_tmp" 2>/dev/null; then
            _bfd_litrepl "sed 's/^\(.*\)-\(.*\)-\(.*\)$/\1/'" \
                         "sed 's/^\([^-]*\)-.*/\1/'" "$_tmp" > "${_tmp}.n" \
                && mv "${_tmp}.n" "$_tmp"
            log "  bfd_targ_cpu_patched (\\1 form): $f"
        fi
        # Fix greedy cpu= form: eval `... sed 's/.../cpu=\1 vendor=\2 os=\3/'`
        if grep -qF "sed 's/^\(.*\)-\(.*\)-\(.*\)$/cpu=\1 vendor=\2 os=\3/'" "$_tmp" 2>/dev/null; then
            _bfd_litrepl "sed 's/^\(.*\)-\(.*\)-\(.*\)$/cpu=\1 vendor=\2 os=\3/'" \
                         "sed 's/^\([^-]*\)-\([^-]*\)-\(.*\)$/cpu=\1 vendor=\2 os=\3/'" "$_tmp" > "${_tmp}.n" \
                && mv "${_tmp}.n" "$_tmp"
            log "  bfd_targ_cpu_patched (cpu= form): $f"
        fi
        cp "$_tmp" "$f"
        rm -f "$_tmp" "${_tmp}.n"
        echo '# bfd_targ_cpu_patched' >> "$f"
    done
}

# Fix GAS i386 type/linkage issues for modern GCC:
#   1. struct relax_type in tc-i386.h is incomplete when included via targ-env.h
#      before tc.h defines it — inline the full definition into as.h early.
#   2. flag_16bit_code is `static` in tc-i386.c but `extern` in tc-i386.h.
_patch_gas_i386_types() {
    local src="$1"
    local as_h="$src/gas/as.h"
    local tc_h="$src/gas/tc.h"
    local tc_i386_c="$src/gas/config/tc-i386.c"
    local _tmp

    # Inline struct relax_type into as.h and set GAS_RELAX_TYPE_DEF guard so tc.h
    # (patched below) skips its own definition.  Two cases:
    #   A) as.h has only a forward decl `struct relax_type;` (older binutils):
    #      replace the forward decl with a full guarded definition.
    #   B) as.h already has the full definition followed by a late forward decl
    #      (binutils 2.17): add `#define GAS_RELAX_TYPE_DEF` after the first
    #      typedef and remove the redundant forward decl.
    if [ -f "$as_h" ] && ! grep -q 'GAS_RELAX_TYPE_DEF' "$as_h" 2>/dev/null; then
        _tmp=$(mktemp "${TMPDIR:-/tmp}/gash_XXXXXX")
        awk '
BEGIN { found_typedef = 0 }
!found_typedef && /^typedef struct relax_type relax_typeS;$/ {
    print
    print "#define GAS_RELAX_TYPE_DEF"
    found_typedef = 1
    next
}
found_typedef && /^struct relax_type;$/ {
    next
}
!found_typedef && /^struct relax_type;$/ {
    print "#ifndef GAS_RELAX_TYPE_DEF"
    print "#define GAS_RELAX_TYPE_DEF"
    print "struct relax_type { long rlx_forward; long rlx_backward; unsigned char rlx_length; relax_substateT rlx_more; };"
    print "typedef struct relax_type relax_typeS;"
    print "#endif"
    next
}
{ print }
' "$as_h" > "$_tmp" && mv "$_tmp" "$as_h" || { rm -f "$_tmp"; true; }
        log "  gas as.h: struct relax_type guard set"
    fi

    # Guard the struct definition in tc.h to avoid redefinition.
    if [ -f "$tc_h" ] && ! grep -q 'GAS_RELAX_TYPE_DEF' "$tc_h" 2>/dev/null; then
        _tmp=$(mktemp "${TMPDIR:-/tmp}/gatch_XXXXXX")
        awk '
/^struct relax_type$/ && !done {
    print "#ifndef GAS_RELAX_TYPE_DEF"
    print "#define GAS_RELAX_TYPE_DEF"
    in_struct=1
}
in_struct && /^typedef struct relax_type relax_typeS;$/ {
    print
    print "#endif"
    in_struct=0; done=1; next
}
{ print }
' "$tc_h" > "$_tmp" && mv "$_tmp" "$tc_h" || { rm -f "$_tmp"; true; }
        log "  gas tc.h: struct relax_type guarded"
    fi

    # Remove 'static' from flag_16bit_code in tc-i386.c (header declares it extern).
    [ -f "$tc_i386_c" ] && \
        sed -i.bak \
            's/^static int flag_16bit_code;/int flag_16bit_code;/' \
            "$tc_i386_c" 2>/dev/null || true
}

# Extend GAS configure i386-*-linux* patterns to also match i486/i586.
# Old gas configure was written when i386 was the only canonical x86 name.
_patch_gas_configure() {
    local src="$1"
    for f in "$src/gas/configure" "$src/gas/configure.in"; do
        [ -f "$f" ] || continue
        grep -q 'gas_i486_patched' "$f" 2>/dev/null && continue
        grep -q 'i386-\*-linux' "$f" 2>/dev/null || continue
        sed -i.bak \
            -e 's/i386-\*-linux\*aout\* | i386-\*-linuxoldld)/i[3456]86-*-linux*aout* | i[3456]86-*-linuxoldld)/g' \
            -e 's/i386-\*-linux\*coff\*)/i[3456]86-*-linux*coff*)/g' \
            -e 's/i386-\*-linux\*)/i[3456]86-*-linux*)/g' \
            "$f" 2>/dev/null || true
        echo '# gas_i486_patched' >> "$f"
        log "  Patched gas configure for i486/i586 Linux targets"
    done
}

# On BSD systems, HZ is not exposed as a user-space constant in <sys/param.h>
# (NetBSD removed it from the public API).  GCC 2.3-2.8 use HZ in toplev.c to
# convert tms_utime ticks to microseconds.  Patch toplev.c to add a fallback.
_bsd_patch_hz() {
    local src="$1"
    case "$(uname -s 2>/dev/null)" in
        *BSD|DragonFly) ;;
        *) return 0 ;;
    esac
    for f in "$src/toplev.c" "$src/gcc/toplev.c"; do
        [ -f "$f" ] || continue
        grep -q '\bHZ\b' "$f" 2>/dev/null || continue
        grep -q 'bsd_hz_patched_' "$f" 2>/dev/null && continue
        awk '/^#include.*sys\/param\.h/{
            print
            print "/* bsd_hz_patched_ */"
            print "#ifndef HZ"
            print "#  define HZ 100"
            print "#endif"
            next
        } {print}' "$f" > "$f.hztmp" && mv "$f.hztmp" "$f" || true
        log "  toplev.c: added HZ=100 fallback for BSD"
    done
}

# GCC 2.x gvarargs.h defines __va_ellipsis as '...' when compiled by GCC 2+,
# intending to set current_function_varargs in cc1.  Modern GCC (4+) rejects
# '...' in K&R parameter declaration positions (va_dcl expands to
# "int __builtin_va_alist; ...").  Restrict to __GNUC__ < 4 so modern hosts
# compile K&R varargs functions without error.
_patch_gvarargs_ellipsis() {
    local src="$1"
    for f in "$src/gvarargs.h" "$src/gcc/gvarargs.h"; do
        [ -f "$f" ] || continue
        grep -q 'gvarargs_ellipsis_patched_' "$f" 2>/dev/null && continue
        grep -q '__va_ellipsis' "$f" 2>/dev/null || continue
        sed -i.bak \
            's/^#if __GNUC__ > 1$/#if __GNUC__ > 1 \&\& __GNUC__ < 4/' \
            "$f" || true
        printf '\n/* gvarargs_ellipsis_patched_ */\n' >> "$f"
        log "  gvarargs.h: restricted __va_ellipsis to GCC 2-3"
    done
}

# Replace outdated config.guess/config.sub with modern versions.
# Old packages from the 1990s don't know x86_64, aarch64, etc.
_update_config_scripts() {
    local src="$1"
    local modern_guess modern_sub

    # Find modern config scripts from automake or libtool
    for d in /usr/share/automake-*/  /usr/share/libtool/build-aux/ /usr/share/autoconf/; do
        [ -f "${d}config.guess" ] && modern_guess="${d}config.guess" && break
    done
    for d in /usr/share/automake-*/ /usr/share/libtool/build-aux/ /usr/share/autoconf/; do
        [ -f "${d}config.sub" ]   && modern_sub="${d}config.sub"   && break
    done

    [ -n "$modern_guess" ] || return 0
    [ -n "$modern_sub"   ] || return 0

    # Replace every config.guess/config.sub found in the source tree
    find "$src" -name 'config.guess' | while read f; do
        cp "$modern_guess" "$f" && chmod +x "$f"
    done
    find "$src" -name 'config.sub' | while read f; do
        cp "$modern_sub" "$f" && chmod +x "$f"
    done
    log "  Updated config.guess/config.sub to modern versions"
}

# ---------------------------------------------------------------------------
# Shared sed-based patch helpers
# (Also used by bootstrap-gcc.sh — keep signatures stable)
# ---------------------------------------------------------------------------

_sed_patch_getline() {
    local src="$1"
    local f="$src/libiberty/getline.c"
    [ -f "$f" ] || return 0
    grep -q 'libiberty_getline\|#define getline' "$f" 2>/dev/null && return 0
    sed -i.bak \
        -e '1i#define getline libiberty_getline' \
        -e 's/^getline (/libiberty_getline (/' \
        -e 's/^getline(/libiberty_getline(/' \
        "$f"
    # Update declaration in libiberty.h if present
    for h in "$src/include/libiberty.h" "$src/libiberty/libiberty.h"; do
        [ -f "$h" ] || continue
        grep -q 'libiberty_getline' "$h" 2>/dev/null || \
            sed -i.bak \
                -e 's/getline\([^_a-zA-Z0-9]\)/libiberty_getline\1/g' \
                -e 's/getline$/libiberty_getline/' \
                "$h"
    done
}

_sed_patch_alloca() {
    local src="$1"
    local f="$src/libiberty/alloca.c"
    [ -f "$f" ] || return 0
    grep -q 'alloca\.h\|HAVE_ALLOCA_H' "$f" 2>/dev/null && return 0
    sed -i.bak \
        '1i#ifdef HAVE_ALLOCA_H\n#  include <alloca.h>\n#endif' \
        "$f"
}

_sed_patch_strsignal() {
    local src="$1"
    local f="$src/libiberty/strsignal.c"
    [ -f "$f" ] || return 0
    grep -q 'const char \* const sys_siglist\|_GNU_SOURCE' "$f" 2>/dev/null && return 0
    sed -i.bak \
        -e '1i#define _GNU_SOURCE 1' \
        -e 's/^extern char \*sys_siglist/extern const char * const sys_siglist/g' \
        "$f"
}

# Fix strsignal.c type conflicts with NetBSD's const-qualified sys_nsig/sys_siglist.
# NetBSD declares: extern const int sys_nsig; extern const char * const *sys_siglist;
# Old libiberty uses non-const int sys_nsig and array sys_siglist[], which conflict.
# Fix the #else branch of the NEED_sys_siglist guard in strsignal.c.
# NetBSD/modern BSDs declare sys_nsig as 'const int' and sys_siglist as
# 'const char * const *' (pointer).  Old libiberty's #else branch has:
#   static int sys_nsig = NSIG;              -- missing const
#   extern const char * const sys_siglist[]; -- array, not pointer
# Only these two initialised/extern lines are patched; the #ifdef NEED_sys_siglist
# block (uninitialised static int sys_nsig; and the malloc path) must remain
# non-const so that init_signal_tables() can assign to them on Linux.
_sed_patch_strsignal_types() {
    local src="$1"
    local f="$src/libiberty/strsignal.c"
    [ -f "$f" ] || return 0
    grep -q 'strsignal_types_patched_' "$f" 2>/dev/null && return 0
    sed -i.bak \
        -e 's/^static int sys_nsig = NSIG;$/static const int sys_nsig = NSIG;/' \
        -e 's/^static int sys_nsig = _NSIG;$/static const int sys_nsig = _NSIG;/' \
        -e 's/^extern const char \* const sys_siglist\[\]/extern const char * const *sys_siglist/' \
        "$f" || true
    printf '\n/* strsignal_types_patched_ */\n' >> "$f"
}

# Fix strsignal.c linkage conflict on BSD: system headers declare sys_nsig as
# extern const int, but old libiberty declares it as static [const] in the
# #else branch of NEED_sys_siglist.  Fix by matching the system header.
# Safe on Linux: NEED_sys_siglist is defined there so the #else branch is never
# compiled.  The NSIG and _NSIG variants are in nested #ifdef blocks; replacing
# both with identical extern declarations is harmless (only one compiles).
_sed_patch_strsignal_netbsd() {
    local src="$1"
    local f="$src/libiberty/strsignal.c"
    [ -f "$f" ] || return 0
    grep -q 'strsignal_netbsd_patched_' "$f" 2>/dev/null && return 0
    sed -i.bak \
        -e 's/^static const int sys_nsig = NSIG;$/extern const int sys_nsig;/' \
        -e 's/^static const int sys_nsig = _NSIG;$/extern const int sys_nsig;/' \
        -e 's/^static int sys_nsig = NSIG;$/extern const int sys_nsig;/' \
        -e 's/^static int sys_nsig = _NSIG;$/extern const int sys_nsig;/' \
        "$f" || true
    printf '\n/* strsignal_netbsd_patched_ */\n' >> "$f"
}

# Fix action.sa_mask = 0 in config/mips/mips.c: sigset_t is a struct on modern
# systems, not an integer type. Replace with sigemptyset() call.
_sed_patch_mips_sigset() {
    local src="$1"
    local f="$src/config/mips/mips.c"
    [ -f "$f" ] || return 0
    grep -q 'sigset_mips_patched_' "$f" 2>/dev/null && return 0
    sed -i.bak \
        -e 's/action\.sa_mask = 0;/sigemptyset(\&action.sa_mask); \/* sigset_mips_patched_ *\//' \
        "$f" || true
}

_sed_patch_disable_werror() {
    local src="$1"
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
        sed -i.bak \
            '1i#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>' \
            "$c2"
    done
}

_sed_patch_xm_linux() {
    local src="$1"
    local xm=""
    for candidate in \
            "$src/gcc/config/i386/xm-linux.h" \
            "$src/config/i386/xm-linux.h" \
            "$src/gcc/config/xm-linux.h"; do
        [ -f "$candidate" ] && { xm="$candidate"; break; }
    done
    [ -n "$xm" ] || return 0
    grep -q 'HAVE_GETRLIMIT' "$xm" 2>/dev/null && return 0
    cat >> "$xm" <<'EOF'

/* Added for modern glibc compatibility */
#ifndef HAVE_GETRLIMIT
# define HAVE_GETRLIMIT  1
# define HAVE_SETRLIMIT  1
# define HAVE_WAITPID    1
# define HAVE_SYSCONF    1
# define HAVE_VPRINTF    1
# define HAVE_PUTENV     1
# define HAVE_STRSIGNAL  1
#endif
EOF
}

_sed_patch_bcopy_shims() {
    local src="$1"
    # bcopy/bzero/bcmp are BSD functions not declared in standard C headers.
    # Use inline macros (via string.h memmove/memset/memcmp) — avoids pulling in
    # strings.h which uses __attribute__ extensions unknown to GCC 2.7.2.3.
    for f in \
            "$src/gcc/cccp.c" "$src/cccp.c" \
            "$src/gcc/protoize.c" "$src/protoize.c" \
            "$src/gcc/gcc.c" "$src/gcc.c"; do
        [ -f "$f" ] || continue
        grep -q '\bbcopy\b\|\bbzero\b' "$f" 2>/dev/null || continue
        grep -q 'bcopy_strings_included\|#define bcopy' "$f" 2>/dev/null && continue
        # Add time.h unconditionally: cccp.c uses struct tm via localtime() but
        # only includes time.h inside '#ifdef VMS'.  Don't define rindex/index
        # as macros — cccp.c uses rindex without args causing "macro used
        # without args" in strict preprocessors; glibc has them at link time.
        sed -i.bak \
            '1i#include <string.h>\n#include <time.h>\n#ifndef bcopy\n#  define bcopy(s,d,n) memmove((d),(s),(n))\n#  define bzero(d,n)   memset((d),0,(n))\n#  define bcmp(a,b,n)  memcmp((a),(b),(n))\n#endif\n/* bcopy_strings_included */' \
            "$f"
    done
}

_sed_patch_sys_nerr() {
    local src="$1"
    for f in \
            "$src/gcc/gcc.c"      "$src/gcc.c" \
            "$src/gcc/cccp.c"     "$src/cccp.c" \
            "$src/gcc/collect2.c" "$src/collect2.c" \
            "$src/gcc/cpplib.c"   "$src/cpplib.c" \
            "$src/gcc/protoize.c" "$src/protoize.c"; do
        # strerror.c manages its own sys_nerr/sys_errlist compat via rename macros;
        [ -f "$f" ] || continue
        grep -q 'sys_errlist\|sys_nerr' "$f" 2>/dev/null || continue
        # Part 1: Replace sys_nerr/sys_errlist references (guarded by its own sentinel).
        # Guard: use only sys_nerr_patched_ — not '#define sys_nerr' which is a false
        # positive in libiberty/strerror.c which uses #define sys_nerr sys_nerr__ to
        # rename the symbol before including errno.h.
        if ! grep -q 'sys_nerr_patched_' "$f" 2>/dev/null; then
            sed -i.bak \
                -e '/[[:space:]]*extern[[:space:]].*sys_nerr/d' \
                -e '/[[:space:]]*extern[[:space:]].*sys_errlist/d' \
                -e 's/sys_errlist\[\([^]]*\)\]/strerror(\1)/g' \
                -e 's/sys_nerr\([^a-zA-Z0-9_]\)/256\1/g' \
                -e 's/sys_nerr$/256/' \
                "$f"
            # Forward-declare strerror without including string.h: full string.h
            # pulls in bcopy/bcmp prototype declarations that conflict with K&R
            # function definitions in era1 sources (cccp.c defines bcopy/bcmp
            # in K&R style; string.h's const void* prototypes cause mismatch).
            grep -q 'extern.*strerror\|#include <string\.h>' "$f" 2>/dev/null || \
                awk 'NR==1{print "extern char *strerror(int);  /* sys_nerr compat */"} {print}' \
                    "$f" > "$f.sntmp" && mv "$f.sntmp" "$f" || true
            printf '\n/* sys_nerr_patched_ */\n' >> "$f"
        fi
        # Part 2: errno.h injection — separate guard so it runs even on files where
        # Part 1 was already applied (handles BSD sed '1i' failure in prior runs).
        # We delete 'extern int errno, sys_nerr;' above so errno needs a proper
        # declaration.  cccp.c has '#include <errno.h>' inside '#ifdef VMS' only,
        # so a plain grep for errno.h gives a false positive — use a unique sentinel.
        # Skip strerror.c: it already manages its errno.h include order carefully to
        # hide sys_nerr/sys_errlist declarations from errno.h using rename macros.
        case "$f" in
            */strerror.c) ;;
            *)
                if ! grep -q 'era1_errno_patched_' "$f" 2>/dev/null; then
                    awk 'NR==1{
                        print "/* era1_errno_patched_ */"
                        print "#include <errno.h>"
                        print "#ifndef R_OK"
                        print "#  define R_OK 4"
                        print "#  define W_OK 2"
                        print "#  define X_OK 1"
                        print "#  define F_OK 0"
                        print "#endif"
                    } {print}' "$f" > "$f.eptmp" && mv "$f.eptmp" "$f" || true
                fi
                ;;
        esac
    done
}

# NetBSD errno.h declares `const int sys_nerr` but libiberty/functions.def has
# `DEFVAR(sys_nerr, int sys_nerr, sys_nerr = 0)` which expands to:
#   extern int sys_nerr;          (global scope — conflicts with const)
#   { sys_nerr = 0; }             (inside dummy main — assignment to const fails)
# Called from patch_old_binutils BEFORE the .old_binutils_patched sentinel.
_patch_libiberty_funcdef_sys_nerr() {
    local src="$1"
    local fdef="$src/libiberty/functions.def"
    [ -f "$fdef" ] || return 0
    grep -q 'sys_nerr_funcdef_patched_' "$fdef" 2>/dev/null && return 0
    sed -i.bak \
        -e '/^DEFVAR(sys_nerr,/d' \
        -e '/^DEFVAR(sys_errlist,/d' \
        "$fdef"
    printf '\n/* sys_nerr_funcdef_patched_ */\n' >> "$fdef"
}

# ---------------------------------------------------------------------------
# Determine which GCC build era a version belongs to
# ---------------------------------------------------------------------------
gcc_build_era() {
    local ver="$1"
    local major
    major=$(echo "$ver" | cut -d. -f1)

    if [ "$major" -eq 1 ] 2>/dev/null; then
        echo "era1"
    elif [ "$major" -eq 2 ] 2>/dev/null; then
        if _gcc_ver_lt "$ver" "2.5"; then
            echo "era2-early"
        elif _gcc_ver_lt "$ver" "2.95"; then
            echo "era2-late"
        else
            echo "era2-95"
        fi
    else
        echo "modern"
    fi
}
