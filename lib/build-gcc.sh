#!/bin/sh
# lib/build-gcc.sh - Build GNU GCC cross-compiler.
#
# build_gcc <gcc_ver> <target> <prefix> <sysroot> <srcdir> <builddir> [build_runtime]
#
# By default builds only the GCC front-ends (all-gcc / install-gcc), which
# does not require a complete sysroot with libc. Pass build_runtime="yes"
# to also build libgcc and libstdc++, which requires target libc in sysroot.
#
# Patches are applied for known issues when building old GCC on modern hosts.

build_gcc() {
    local gcc_ver="$1"
    local target="$2"
    local prefix="$3"
    local sysroot="$4"
    local srcdir="$5"
    local builddir="$6"
    local build_runtime="${7:-}"
    local host_flag="${8:-}"   # e.g. --host=sparc-sun-solaris2.6 for Canadian cross

    # Route old GCC versions to era-specific build functions
    local era
    era=$(gcc_build_era "$gcc_ver" 2>/dev/null || echo "modern")
    case "$era" in
        era1)
            build_gcc_era1 "$gcc_ver" "$target" "$prefix" "$sysroot" "$srcdir" "$builddir"
            return $?
            ;;
        era2-early)
            build_gcc_era2_early "$gcc_ver" "$target" "$prefix" "$sysroot" "$srcdir" "$builddir" "$build_runtime"
            return $?
            ;;
        era2-late)
            build_gcc_era2_late "$gcc_ver" "$target" "$prefix" "$sysroot" "$srcdir" "$builddir" "$build_runtime"
            return $?
            ;;
    esac

    local src="$srcdir/gcc-${gcc_ver}"
    local bld="$builddir/gcc-${gcc_ver}-${target}"

    [ -n "$DRY_RUN" ] && { echo "[DRY RUN] Would build GCC $gcc_ver for $target"; return 0; }

    if [ ! -d "$src" ]; then
        echo "ERROR: GCC source not found: $src" >&2
        return 1
    fi

    # Already installed?
    if [ -f "$prefix/bin/${target}-gcc" ]; then
        log "GCC $gcc_ver for $target already installed in $prefix"
        return 0
    fi

    # Apply compatibility patches for old GCC on modern hosts
    _patch_gcc_source "$gcc_ver" "$src"

    log "Configuring GCC $gcc_ver for target $target..."
    mkdir -p "$bld"

    local sysroot_flag=""
    if [ -d "$sysroot" ]; then
        sysroot_flag="--with-sysroot=$sysroot"
    fi

    # Language support: C and C++ by default; Fortran if available
    local languages="c,c++"
    _gcc_ver_ge "$gcc_ver" "4.0" && languages="c,c++,fortran"

    # GCC 4.3+ needs GMP/MPFR/MPC; GCC_PREREQ_OPTS set by handle_gcc_prereqs
    local prereq_opts="${GCC_PREREQ_OPTS:-}"

    # GCC 2.x configure scripts don't recognize x86_64/amd64; normalize to
    # i686 so the machine-validity loop (i[34567]86-*-*) accepts the host.
    # For GCC >= 3.0 on NetBSD amd64, pass --build explicitly so configure
    # doesn't call config.guess (which can fail if /dev/null is a plain file).
    local _x86_norm_flags=""
    if [ -z "$host_flag" ]; then
        case "$(uname -m 2>/dev/null)" in
            x86_64|amd64)
                if _gcc_ver_lt "$gcc_ver" "3.0"; then
                    _x86_norm_flags="--host=i686-pc-linux-gnu --build=i686-pc-linux-gnu"
                else
                    case "$(uname -s 2>/dev/null)" in
                        NetBSD) _x86_norm_flags="--build=x86_64-unknown-netbsd$(uname -r 2>/dev/null)" ;;
                    esac
                fi
                ;;
        esac
    fi

    # Host compiler flags (may need adjustments for old GCC)
    local host_cflags host_cxxflags
    host_cflags=$(_get_host_cflags "$gcc_ver")
    host_cxxflags=$(_get_host_cxxflags "$gcc_ver")

    # For GCC < 4.0 (era2-95, i.e. 2.95.x): embed compat flags into CC rather
    # than CFLAGS.  GCC 2.95.3's Makefile propagates $(CFLAGS) into xgcc via
    # GCC_FLAGS_TO_PASS, so modern-only flags like -Wno-int-conversion end up
    # being passed to the freshly built xgcc, which rejects them.  Putting the
    # flags in CC keeps them host-only.
    local _cc_for_configure="${HOST_CC:-gcc}"
    local _cflags_for_configure="$host_cflags"
    local _cxxflags_for_configure="$host_cxxflags"
    if _gcc_ver_lt "$gcc_ver" "4.0"; then
        _cc_for_configure="${HOST_CC:-gcc} $host_cflags"
        _cflags_for_configure=""
        _cxxflags_for_configure=""
    fi

    # Construct the configure command
    # LDFLAGS="" is explicit so gcc/config.cache records it as "set"; GCC 3.x+
    # Makefiles pass LDFLAGS= to sub-makes via BASE_FLAGS_TO_PASS, and if the
    # sub-configure finds LDFLAGS "set" but the cache says "not set", it errors.
    (cd "$bld" && \
        CFLAGS_FOR_BUILD="${_cflags_for_configure}" \
        CXXFLAGS_FOR_BUILD="${_cxxflags_for_configure}" \
        CFLAGS="${_cflags_for_configure}" \
        CXXFLAGS="${_cxxflags_for_configure}" \
        LDFLAGS="" \
        CC="${_cc_for_configure}" \
        CXX="${HOST_CXX:-g++}" \
        "$src/configure" \
            --target="$target" \
            --prefix="$prefix" \
            ${host_flag:+"$host_flag"} \
            $_x86_norm_flags \
            $sysroot_flag \
            --enable-languages="$languages" \
            --disable-nls \
            --disable-shared \
            --disable-multilib \
            --disable-libssp \
            --disable-libquadmath \
            --with-newlib \
            --enable-obsolete \
            $prereq_opts \
            ${EXTRA_GCC_OPTS:-} \
    ) || {
        echo "ERROR: GCC configure failed" >&2
        return 1
    }

    if [ -n "$build_runtime" ]; then
        log "Building GCC $gcc_ver with runtime libraries (jobs: $MAKE_JOBS)..."
        (cd "$bld" && "${MAKE:-make}" -j"$MAKE_JOBS") || {
            echo "ERROR: GCC build failed" >&2
            return 1
        }
        log "Installing GCC $gcc_ver (with runtime) to $prefix..."
        (cd "$bld" && "${MAKE:-make}" install) || {
            echo "ERROR: GCC install failed" >&2
            return 1
        }
    else
        # GCC 4.5-4.6 uses bundled MPFR 3.x; that version's out-of-tree build
        # places the library at mpfr/src/.libs/ while MPC 0.8.1's configure
        # expects mpfr/.libs/.  Pre-build MPFR and create the compatibility
        # symlink before configure-mpc runs inside make all-gcc.
        if ! _gcc_ver_lt "$gcc_ver" "4.5" && _gcc_ver_lt "$gcc_ver" "4.7"; then
            if [ -L "$src/mpfr" ] || [ -d "$src/mpfr" ]; then
                log "Pre-building bundled MPFR for GCC $gcc_ver (MPFR 3.x layout fix)..."
                (cd "$bld" && "${MAKE:-make}" -j"$MAKE_JOBS" all-mpfr 2>/dev/null) || \
                (cd "$bld" && "${MAKE:-make}" -j1 all-mpfr 2>/dev/null) || true
                if [ -d "$bld/mpfr/src/.libs" ] && [ ! -e "$bld/mpfr/.libs" ]; then
                    ln -s src/.libs "$bld/mpfr/.libs" 2>/dev/null || true
                fi
            fi
        fi

        # For GCC 3.x+, gcc/Makefile is not generated at top-level configure
        # time — it is created lazily by the configure-gcc sub-target during
        # make all-gcc.  Run configure-gcc explicitly now so we can patch the
        # resulting gcc/Makefile before the actual compilation begins.
        # GCC 2.x configure generates gcc/Makefile immediately, so this is a
        # no-op for those versions (configure-gcc is guarded by
        # "test ! -f gcc/Makefile || exit 0" in the top-level Makefile).
        if [ ! -f "$bld/gcc/Makefile" ]; then
            log "Running configure-gcc to initialize gcc/Makefile..."
            (cd "$bld" && LDFLAGS="" "${MAKE:-make}" configure-gcc) || {
                echo "ERROR: configure-gcc failed" >&2
                return 1
            }
        fi

        # Patch gcc/Makefile to clear runtime-library variables before building.
        # We only install the cross-compile front-end (not a runtime), so CRT
        # objects (EXTRA_PARTS), libgcc1 (LIBGCC1), libgcc (LIBGCC), and
        # libgcc1-test (LIBGCC1_TEST) are never needed here.
        # The make command-line "EXTRA_PARTS=" override does NOT propagate to
        # the gcc/ sub-make because it is not in GCC_FLAGS_TO_PASS, and the
        # MAKEFLAGS propagation is unreliable when the Makefile uses += or
        # assigns the variable directly via config.status substitution.
        # Patch directly to guarantee all are suppressed.
        if [ -f "$bld/gcc/Makefile" ]; then
            log "Patching gcc/Makefile: clearing EXTRA_PARTS, LIBGCC1, LIBGCC, LIBGCC1_TEST..."
            sed -i.no_ep_bak \
                -e 's/^EXTRA_PARTS = .*/EXTRA_PARTS = /' \
                -e 's/^LIBGCC1 = .*/LIBGCC1 = /' \
                -e 's/^LIBGCC = .*/LIBGCC = /' \
                -e 's/^INSTALL_LIBGCC = .*/INSTALL_LIBGCC = /' \
                -e 's/^LIBGCC1_TEST = .*/LIBGCC1_TEST = /' \
                "$bld/gcc/Makefile" 2>/dev/null || true
            # Also insert override after include $(xmake_file) and include $(tmake_file)
            # for targets where these fragments use += to append to EXTRA_PARTS
            # (e.g. alpha/t-crtfm appends crtfastmath.o via tmake_file).
            awk '/^include.*(xmake_file|tmake_file)/{print; print "EXTRA_PARTS ="; next} {print}' \
                "$bld/gcc/Makefile" > "$bld/gcc/Makefile.no_ep_bak2" && \
                mv "$bld/gcc/Makefile.no_ep_bak2" "$bld/gcc/Makefile" || true
        fi

        log "Building GCC $gcc_ver front-ends only (jobs: $MAKE_JOBS)..."
        # EXTRA_PARTS="": skip CRT objects built from platform-specific assembly
        # (Solaris/SPARC/Alpha asm syntax rejected by modern GNU as).
        # MAKEINFO=true: skip documentation generation that may fail on old GCC.
        # LDFLAGS="" must be in the make environment (not just configure) so the
        # configure-gcc sub-rule runs with LDFLAGS set, matching what GCC_FLAGS_TO_PASS
        # later passes as "LDFLAGS=" — otherwise config.cache records it as unset and
        # the subsequent sub-make triggers a "LDFLAGS was not set in previous run" error.
        (cd "$bld" && LDFLAGS="" "${MAKE:-make}" -j"$MAKE_JOBS" all-gcc EXTRA_PARTS="" MAKEINFO=true) || {
            echo "ERROR: GCC build (all-gcc) failed" >&2
            return 1
        }
        # Touch stub .info files so install-gcc's install-info doesn't re-run
        # makeinfo (which fails for old GCC texinfo on modern makeinfo versions).
        # The files just need to exist; content doesn't matter for a cross build.
        for _info in cpp gcc g++; do
            touch "$bld/gcc/${_info}.info" 2>/dev/null || true
        done

        log "Installing GCC $gcc_ver to $prefix..."
        # Use -k (keep going) so install-fixincludes or install-info failures
        # on read-only dirs don't abort before the cross binary is placed.
        (cd "$bld" && MAKEINFO=true "${MAKE:-make}" -k install-gcc) || \
            log "install-gcc exited non-zero; checking if binary was installed..."
        # GCC 2.95.x: install-driver is sometimes silently skipped by install-gcc.
        # Also recovers from install-fixincludes failure on restricted hosts.
        if [ ! -f "$prefix/bin/${target}-gcc" ]; then
            log "install-driver skipped or binary missing; running explicitly..."
            (cd "$bld" && "${MAKE:-make}" -j1 install-driver 2>/dev/null) || \
            (cd "$bld/gcc" && "${MAKE:-make}" -j1 install-driver 2>/dev/null) || true
        fi
        if [ ! -f "$prefix/bin/${target}-gcc" ]; then
            echo "ERROR: GCC install-gcc failed (binary not installed)" >&2
            return 1
        fi
        # Also build and install libgcc if possible
        log "Attempting to build cross libgcc..."
        if (cd "$bld" && "${MAKE:-make}" -j"$MAKE_JOBS" all-target-libgcc 2>/dev/null); then
            (cd "$bld" && "${MAKE:-make}" install-target-libgcc) || true
            log "Cross libgcc installed"
        else
            log "Note: libgcc not built (requires complete sysroot; use -r flag)"
        fi
    fi

    log "GCC $gcc_ver for $target installed successfully"
}

# Determine extra CFLAGS needed when building old GCC on modern hosts
_get_host_cflags() {
    local gcc_ver="$1"
    local flags=""

    if _gcc_ver_lt "$gcc_ver" "4.0"; then
        # Old GCC source has many issues with modern C compliance
        flags="-O1 -fno-strict-aliasing"
        flags="$flags -Wno-implicit-function-declaration"
        flags="$flags -Wno-int-conversion"
        flags="$flags -Wno-incompatible-pointer-types"

        # Use gnu89 inline semantics; the old code assumes them
        flags="$flags -fgnu89-inline"

        # Suppress all warnings-as-errors propagation
        flags="$flags -w"
    elif _gcc_ver_lt "$gcc_ver" "4.6"; then
        flags="-O2 -Wno-deprecated -fno-strict-aliasing"
    fi

    echo "$flags"
}

# Determine extra CXXFLAGS needed when building old GCC on modern hosts.
# Separate from _get_host_cflags because -std=gnu++NN is valid only for C++.
_get_host_cxxflags() {
    local gcc_ver="$1"
    local flags
    flags=$(_get_host_cflags "$gcc_ver")

    # GCC 4.6-4.9 C++ source uses bool++ which is forbidden in C++17.
    # Build with C++14 to allow the deprecated construct.
    if ! _gcc_ver_lt "$gcc_ver" "4.6" && _gcc_ver_lt "$gcc_ver" "5.0"; then
        flags="$flags -std=gnu++14"
    fi

    echo "$flags"
}

# Apply source-level patches for known compatibility issues.
# Patches are applied idempotently (checked before applying).
_patch_gcc_source() {
    local gcc_ver="$1"
    local src="$2"

    # GCC < 4.0 has config.sub/config.guess from the 1990s that don't know
    # about x86_64, aarch64, etc.  Replace them with modern automake versions.
    if _gcc_ver_lt "$gcc_ver" "4.0"; then
        chmod -R u+w "$src" 2>/dev/null || true
        _update_config_scripts "$src"
        _patch_libiberty_getline "$src"
        _patch_libiberty_alloca "$src"
        _patch_gcc_2x_fixups "$src" "$gcc_ver"
        # NetBSD errno.h: `const int sys_nerr` conflicts with old `extern int sys_nerr`
        _sed_patch_sys_nerr "$src"
        # NetBSD sys_nsig/sys_siglist have const qualifiers old libiberty doesn't expect
        _sed_patch_strsignal_types "$src"
    fi
    # All GCC versions: fix static/extern linkage conflict for sys_nsig on BSD.
    # BSD system headers declare extern const int sys_nsig; old libiberty uses
    # static [const] int sys_nsig = NSIG in the #else branch of NEED_sys_siglist.
    # Safe on Linux: NEED_sys_siglist is defined there so the #else never compiles.
    _sed_patch_strsignal_netbsd "$src"
    if ! _gcc_ver_lt "$gcc_ver" "4.0" && _gcc_ver_lt "$gcc_ver" "4.4"; then
        # GCC 4.0-4.3 generally builds fine; minimal fixups
        _patch_disable_werror "$src"
    fi

    # GCC 4.5-4.7: cfns.h libc_name_p declaration is missing gnu_inline attribute
    # that matches the definition; modern GCC rejects the mismatch.
    if ! _gcc_ver_lt "$gcc_ver" "4.5" && _gcc_ver_lt "$gcc_ver" "4.8"; then
        _patch_cfns_gnu_inline "$src"
    fi
}

# Patch gcc/cp/cfns.h: add __gnu_inline__ to libc_name_p forward declaration
# so it matches the definition which adds it under __GNUC_STDC_INLINE__.
_patch_cfns_gnu_inline() {
    local src="$1"
    local cfns_h="$src/gcc/cp/cfns.h"
    [ -f "$cfns_h" ] || return 0
    grep -q 'cfns_gnu_inline_patched' "$cfns_h" 2>/dev/null && return 0
    log "Patching gcc/cp/cfns.h: adding gnu_inline to libc_name_p declaration..."
    # State machine: match the exact 4-line block
    #   #ifdef __GNUC__  /  __inline  /  #endif  /  const char * libc_name_p ...;
    # and insert __GNUC_STDC_INLINE__ guard inside it so the declaration matches
    # the definition (which already carries __attribute__ ((__gnu_inline__))).
    awk '
BEGIN { s=0 }
s==0 && /^#ifdef __GNUC__$/ { s=1; l1=$0; next }
s==1 {
    if (/^__inline$/) { s=2; l2=$0; next }
    print l1; s=0
}
s==2 {
    if (/^#endif$/) { s=3; l3=$0; next }
    print l1; print l2; s=0
}
s==3 {
    if (/^const char \* libc_name_p/) {
        print l1; print l2
        print "#ifdef __GNUC_STDC_INLINE__"
        print "__attribute__ ((__gnu_inline__))"
        print "#endif"
        print l3
        print $0 " /* cfns_gnu_inline_patched */"
        s=0; next
    }
    print l1; print l2; print l3; s=0
}
{ print }
' "$cfns_h" > "$cfns_h.tmp" && mv "$cfns_h.tmp" "$cfns_h" || true
}

# Patch libiberty/getline.c: rename getline -> libiberty_getline to avoid
# conflict with POSIX getline() in modern glibc.
_patch_libiberty_getline() {
    local src="$1"
    local f="$src/libiberty/getline.c"

    [ -f "$f" ] || return 0

    # Check if already patched
    grep -q "libiberty_getline" "$f" 2>/dev/null && return 0

    log "Patching libiberty/getline.c (getline rename)..."
    sed -i.orig \
        -e 's/getline\([^_a-zA-Z0-9]\)/libiberty_getline\1/g' \
        -e 's/getline$/libiberty_getline/' \
        "$f"

    # Also patch the header declaration if it exists
    local h="$src/include/libiberty.h"
    if [ -f "$h" ]; then
        grep -q "libiberty_getline" "$h" 2>/dev/null || \
            sed -i.orig \
                -e 's/getline\([^_a-zA-Z0-9]\)/libiberty_getline\1/g' \
                -e 's/getline$/libiberty_getline/' \
                "$h"
    fi
}

# Patch alloca declarations for portability with modern headers
_patch_libiberty_alloca() {
    local src="$1"
    local f="$src/libiberty/alloca.c"

    [ -f "$f" ] || return 0
    grep -q "HAVE_ALLOCA_H" "$f" 2>/dev/null && return 0

    log "Patching libiberty/alloca.c..."
    # Ensure proper include guard for alloca
    sed -i.orig \
        '1i#ifndef HAVE_ALLOCA_H\n#define HAVE_ALLOCA_H 1\n#endif\n#ifdef HAVE_ALLOCA_H\n#include <alloca.h>\n#endif' \
        "$f" 2>/dev/null || true
}

# Patch out -Werror flags in old GCC Makefiles and configure scripts
_patch_disable_werror() {
    local src="$1"

    # Stamp prevents re-patching configure scripts on subsequent builds of the
    # same GCC version for different targets.  Re-patching would update the
    # configure script timestamps, making them newer than the build-dir's
    # config.status, which triggers a reconfigure that fails due to a stale
    # config.cache LDFLAGS mismatch (Makefile passes LDFLAGS= to sub-makes).
    [ -f "$src/.disable_werror_applied" ] && return 0

    log "Removing -Werror from old GCC build files..."

    # Remove -Werror from Makefile.in files
    find "$src" -name 'Makefile.in' | while read mf; do
        grep -q '\-Werror' "$mf" || continue
        sed -i.orig 's/ -Werror//g; s/-Werror //g; s/^-Werror$//g' "$mf"
    done

    # Remove -Werror from configure scripts
    find "$src" -name 'configure' -maxdepth 3 | while read cf; do
        grep -q '\-Werror' "$cf" || continue
        sed -i.orig 's/ -Werror//g; s/-Werror //g' "$cf"
    done

    touch "$src/.disable_werror_applied"
}

# Patch obstack.h cast-as-lvalue ++ that modern GCC rejects as not a valid lvalue.
# Affects MIPS/SPARC/Alpha targets where reorg.c uses obstack_ptr/int_grow macros.
# Applies to both GCC 2.7.2.3 (obstack.h in root) and 2.95.3 (include/obstack.h).
_patch_obstack_lvalue() {
    local src="$1"
    local ob
    for ob in "$src/include/obstack.h" "$src/obstack.h"; do
        [ -f "$ob" ] || continue
        grep -q '_obstack_lvalue_patched_' "$ob" 2>/dev/null && continue
        grep -q 'next_free)++ = ' "$ob" 2>/dev/null || continue
        log "Patching obstack.h: fixing cast-as-lvalue ++ in $ob..."
        # Fix statement-form macros: split assignment + pointer advance
        sed -i.obstack_bak \
            's|\*((void \*\*)__o->next_free)++ = ((void \*)datum);|*(void **)(__o->next_free) = (void *)datum; __o->next_free += sizeof (void *);|g' \
            "$ob"
        sed -i \
            's|\*((int \*)__o->next_free)++ = ((int)datum);|*(int *)(__o->next_free) = (int)datum; __o->next_free += sizeof (int);|g' \
            "$ob"
        # Fix _fast expression macros: use comma-expression instead of ++
        # Four variants: with/without space in cast, #define vs # define
        sed -i \
            's|#define obstack_ptr_grow_fast(h,aptr) (\*((void \*\*) (h)->next_free)++ = (void \*)aptr)|#define obstack_ptr_grow_fast(h,aptr) (*(void **)((h)->next_free) = (void *)aptr, (h)->next_free += sizeof (void *))|g' \
            "$ob"
        sed -i \
            's|# define obstack_ptr_grow_fast(h,aptr) (\*((void \*\*) (h)->next_free)++ = (void \*)aptr)|# define obstack_ptr_grow_fast(h,aptr) (*(void **)((h)->next_free) = (void *)aptr, (h)->next_free += sizeof (void *))|g' \
            "$ob"
        sed -i \
            's|#define obstack_ptr_grow_fast(h,aptr) (\*((void \*\*)(h)->next_free)++ = (void \*)aptr)|#define obstack_ptr_grow_fast(h,aptr) (*(void **)((h)->next_free) = (void *)aptr, (h)->next_free += sizeof (void *))|g' \
            "$ob"
        sed -i \
            's|# define obstack_ptr_grow_fast(h,aptr) (\*((void \*\*)(h)->next_free)++ = (void \*)aptr)|# define obstack_ptr_grow_fast(h,aptr) (*(void **)((h)->next_free) = (void *)aptr, (h)->next_free += sizeof (void *))|g' \
            "$ob"
        sed -i \
            's|#define obstack_int_grow_fast(h,aint) (\*((int \*) (h)->next_free)++ = (int) aint)|#define obstack_int_grow_fast(h,aint) (*(int *)((h)->next_free) = (int)aint, (h)->next_free += sizeof (int))|g' \
            "$ob"
        sed -i \
            's|# define obstack_int_grow_fast(h,aint) (\*((int \*) (h)->next_free)++ = (int) aint)|# define obstack_int_grow_fast(h,aint) (*(int *)((h)->next_free) = (int)aint, (h)->next_free += sizeof (int))|g' \
            "$ob"
        sed -i \
            's|#define obstack_int_grow_fast(h,aint) (\*((int \*)(h)->next_free)++ = (int)aint)|#define obstack_int_grow_fast(h,aint) (*(int *)((h)->next_free) = (int)aint, (h)->next_free += sizeof (int))|g' \
            "$ob"
        sed -i \
            's|# define obstack_int_grow_fast(h,aint) (\*((int \*)(h)->next_free)++ = (int)aint)|# define obstack_int_grow_fast(h,aint) (*(int *)((h)->next_free) = (int)aint, (h)->next_free += sizeof (int))|g' \
            "$ob"
        printf '\n/* _obstack_lvalue_patched_ */\n' >> "$ob"
    done
}

# Additional fixups specific to GCC 2.x on modern Linux
_patch_gcc_2x_fixups() {
    local src="$1"
    local gcc_ver="$2"

    # GCC 2.95.x: fix_proto.c uses char* for string literals in unsafe ways
    local fp="$src/gcc/fix_proto.c"
    if [ -f "$fp" ]; then
        grep -q "char \*proto_dir" "$fp" 2>/dev/null && \
        sed -i.orig 's/char \*proto_dir/const char *proto_dir/g' "$fp" 2>/dev/null || true
    fi

    # GCC 2.95.x: protoize.c similar issues
    local pr="$src/gcc/protoize.c"
    if [ -f "$pr" ]; then
        # This file has many such issues; just suppress warnings
        touch "$src/.applied_2x_fixups"
    fi

    # Handle conflicting types in xm-linux.h or similar
    local xm="$src/gcc/config/i386/xm-linux.h"
    if [ -f "$xm" ]; then
        grep -q "HAVE_GETRLIMIT" "$xm" 2>/dev/null || \
            printf '\n#define HAVE_GETRLIMIT 1\n' >> "$xm"
    fi

    _patch_disable_werror "$src"
    _patch_obstack_lvalue "$src"
}
