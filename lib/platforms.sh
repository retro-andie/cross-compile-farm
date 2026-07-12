#!/bin/sh
# lib/platforms.sh - Platform definitions: target triples, GCC/binutils versions,
# and extra configure flags for each supported UNIX variant.
#
# After calling get_platform_info(), these variables are set:
#   TARGET              - GNU target triple (e.g., sparc-sun-solaris2.10)
#   DEFAULT_GCC_VER     - Recommended GCC version (last supporting the target)
#   DEFAULT_BINUTILS_VER- Recommended binutils version
#   LAST_GCC_VER        - Last known GCC version supporting the target
#   TARGET_ABI          - Object format: elf, xcoff, som, aout, ecoff
#   EXTRA_GCC_OPTS      - Additional GCC configure flags
#   EXTRA_BINUTILS_OPTS - Additional binutils configure flags
#   GCC_MIN_HOST_VER    - Minimum host GCC version needed to build GCC_VER

get_platform_info() {
    PLATFORM="$1"
    PLATFORM_VER="$2"
    USER_ARCH="${3:-}"

    TARGET=""
    DEFAULT_GCC_VER=""
    DEFAULT_BINUTILS_VER="2.40"
    LAST_GCC_VER=""
    LAST_BINUTILS_VER="current"
    TARGET_ABI="elf"
    EXTRA_GCC_OPTS=""
    EXTRA_BINUTILS_OPTS="--disable-werror"
    GCC_MIN_HOST_VER="3.4"

    case "$PLATFORM" in
        solaris|sunos)
            _platform_solaris "$PLATFORM_VER" "$USER_ARCH"
            ;;
        aix)
            _platform_aix "$PLATFORM_VER" "$USER_ARCH"
            ;;
        hpux|hp-ux|hpux11|hpux10|hpux9)
            _platform_hpux "$PLATFORM_VER" "$USER_ARCH"
            ;;
        tru64|osf1|osf|digital-unix|decunix)
            _platform_tru64 "$PLATFORM_VER" "$USER_ARCH"
            ;;
        irix)
            _platform_irix "$PLATFORM_VER" "$USER_ARCH"
            ;;
        netbsd)
            _platform_netbsd "$PLATFORM_VER" "$USER_ARCH"
            ;;
        freebsd)
            _platform_freebsd "$PLATFORM_VER" "$USER_ARCH"
            ;;
        openbsd)
            _platform_openbsd "$PLATFORM_VER" "$USER_ARCH"
            ;;
        linux)
            _platform_linux "$PLATFORM_VER" "$USER_ARCH"
            ;;
        sco|openserver|sco-unix)
            _platform_sco "$PLATFORM_VER" "$USER_ARCH"
            ;;
        unixware|sco-uw)
            _platform_unixware "$PLATFORM_VER" "$USER_ARCH"
            ;;
        interix|sfu)
            _platform_interix "$PLATFORM_VER" "$USER_ARCH"
            ;;
        # --------------- early/historical platforms -------------------------
        sunos4|sunos3|sun3|sun4)
            _platform_sunos4 "$PLATFORM_VER" "$USER_ARCH"
            ;;
        ultrix)
            _platform_ultrix "$PLATFORM_VER" "$USER_ARCH"
            ;;
        nextstep|openstep|next)
            _platform_nextstep "$PLATFORM_VER" "$USER_ARCH"
            ;;
        dynix|ptx)
            _platform_dynix "$PLATFORM_VER" "$USER_ARCH"
            ;;
        osf1-alpha|osf-alpha)   # alias when user means early DEC OSF
            _platform_tru64 "$PLATFORM_VER" "$USER_ARCH"
            ;;
        # --------------- Linux libc variants --------------------------------
        linux1|linux-libc4|linux-aout)
            _platform_linux1 "$PLATFORM_VER" "$USER_ARCH"
            ;;
        linux2|linux-libc5|linuxelf|linux-elf)
            _platform_linux2 "$PLATFORM_VER" "$USER_ARCH"
            ;;
        *)
            echo "ERROR: Unknown platform '$PLATFORM'" >&2
            echo "Supported: solaris, aix, hpux, tru64, irix, netbsd, freebsd," >&2
            echo "           openbsd, linux, linux1 (libc4/a.out), linux2 (libc5/ELF)," >&2
            echo "           sco, unixware, sunos4, ultrix, nextstep, dynix" >&2
            return 1
            ;;
    esac

    if [ -z "$TARGET" ]; then
        echo "ERROR: Could not determine target triple for $PLATFORM $PLATFORM_VER" >&2
        return 1
    fi

    if [ -z "$DEFAULT_GCC_VER" ]; then
        DEFAULT_GCC_VER="$LAST_GCC_VER"
    fi
}

# ---------------------------------------------------------------------------
# Solaris / SunOS
# ---------------------------------------------------------------------------
_platform_solaris() {
    local ver="$1"
    local arch="${2:-sparc}"
    local solaris_ver

    case "$ver" in
        2.3|5.3)    solaris_ver="2.3"  ;;
        2.4|5.4)    solaris_ver="2.4"  ;;
        2.5|2.5.1|5.5|5.5.1) solaris_ver="2.5" ;;
        2.6|5.6)    solaris_ver="2.6"  ;;
        7|2.7|5.7)  solaris_ver="2.7"  ;;
        8|2.8|5.8)  solaris_ver="2.8"  ;;
        9|2.9|5.9)  solaris_ver="2.9"  ;;
        10|2.10|5.10) solaris_ver="2.10" ;;
        11|2.11|5.11) solaris_ver="2.11" ;;
        *)
            echo "ERROR: Unknown Solaris version '$ver'" >&2
            echo "       Valid: 2.3 2.4 2.5 2.6 7 8 9 10 11" >&2
            return 1
            ;;
    esac

    case "$arch" in
        sparc|sparcv8|sparcv9|"") arch="sparc" ;;
        x86|i386|i486|i586|i686)  arch="i386"  ;;
        x86_64|amd64)
            if [ "$solaris_ver" != "2.10" ] && [ "$solaris_ver" != "2.11" ]; then
                echo "ERROR: x86_64 Solaris only available for Solaris 10 and 11" >&2
                return 1
            fi
            arch="x86_64"
            ;;
        *)
            echo "ERROR: Unknown arch '$arch' for Solaris. Use: sparc, x86, x86_64" >&2
            return 1
            ;;
    esac

    case "$arch" in
        sparc)   TARGET="sparc-sun-solaris${solaris_ver}"  ;;
        i386)    TARGET="i386-pc-solaris${solaris_ver}"    ;;
        x86_64)  TARGET="x86_64-pc-solaris${solaris_ver}" ;;
    esac

    TARGET_ABI="elf"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"

    case "$solaris_ver" in
        2.3|2.4)
            LAST_GCC_VER="4.8.5"
            DEFAULT_BINUTILS_VER="2.36"
            GCC_MIN_HOST_VER="3.4"
            ;;
        2.5|2.6)
            LAST_GCC_VER="8.5.0"
            DEFAULT_BINUTILS_VER="2.36"
            ;;
        2.7|2.8)
            LAST_GCC_VER="9.5.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        2.9)
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        2.10)
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        2.11)
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# AIX
# ---------------------------------------------------------------------------
_platform_aix() {
    local ver="$1"
    local arch="${2:-ppc}"
    local aix_maj

    aix_maj=$(echo "$ver" | cut -d. -f1)

    case "$arch" in
        ppc|powerpc|"")  arch="powerpc"   ;;
        ppc64|powerpc64) arch="powerpc64" ;;
        rs6000)          arch="rs6000"    ;;
        *)
            echo "ERROR: Unknown arch '$arch' for AIX. Use: ppc, ppc64, rs6000" >&2
            return 1
            ;;
    esac

    case "$ver" in
        3|3.2|3.2.*)
            arch="rs6000"
            TARGET="rs6000-ibm-aix3.2"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.20"
            GCC_MIN_HOST_VER="2.95"
            ;;
        4.1|4.1.*)
            TARGET="powerpc-ibm-aix4.1"
            LAST_GCC_VER="6.5.0"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        4.2|4.2.*)
            TARGET="powerpc-ibm-aix4.2"
            LAST_GCC_VER="6.5.0"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        4.3|4.3.*)
            TARGET="powerpc-ibm-aix4.3"
            LAST_GCC_VER="6.5.0"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        5.1|5.1.*)
            TARGET="powerpc-ibm-aix5.1"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        5.2|5.2.*)
            TARGET="powerpc-ibm-aix5.2"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        5.3|5.3.*)
            TARGET="powerpc-ibm-aix5.3"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        6|6.1|6.1.*)
            TARGET="${arch}-ibm-aix6.1"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        7|7.1|7.1.*)
            TARGET="${arch}-ibm-aix7.1"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        7.2|7.2.*)
            TARGET="${arch}-ibm-aix7.2"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        7.3|7.3.*)
            TARGET="${arch}-ibm-aix7.3"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        *)
            echo "ERROR: Unknown AIX version '$ver'" >&2
            echo "       Valid: 3.2, 4.1, 4.2, 4.3, 5.1, 5.2, 5.3, 6.1, 7.1, 7.2, 7.3" >&2
            return 1
            ;;
    esac

    TARGET_ABI="xcoff"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# HP-UX
# ---------------------------------------------------------------------------
_platform_hpux() {
    local ver="$1"
    local arch="${2:-}"
    local hpux_maj hpux_triple_ver

    hpux_maj=$(echo "$ver" | cut -d. -f1)

    # Determine architecture from version if not specified
    if [ -z "$arch" ]; then
        case "$ver" in
            9|9.*) arch="parisc" ;;
            10|10.*) arch="parisc" ;;
            11.0|11.00|11.11) arch="parisc" ;;
            11.23|11.31) arch="ia64" ;;
            11|11.*) arch="ia64" ;;  # 11.23+ default to IA-64
            *) arch="parisc" ;;
        esac
    fi

    case "$arch" in
        parisc|pa-risc|hppa|parisc1.1|parisc2.0) : ;;
        ia64|itanium) arch="ia64" ;;
        *)
            echo "ERROR: Unknown arch '$arch' for HP-UX. Use: parisc, ia64" >&2
            return 1
            ;;
    esac

    case "$ver" in
        9|9.*)
            if [ "$arch" = "ia64" ]; then
                echo "ERROR: HP-UX 9.x is PA-RISC only" >&2; return 1
            fi
            TARGET="hppa1.1-hp-hpux9.05"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.20"
            GCC_MIN_HOST_VER="2.95"
            TARGET_ABI="som"
            ;;
        10|10.*)
            if [ "$arch" = "ia64" ]; then
                echo "ERROR: HP-UX 10.x is PA-RISC only" >&2; return 1
            fi
            TARGET="hppa2.0-hp-hpux10.20"
            LAST_GCC_VER="7.5.0"
            DEFAULT_BINUTILS_VER="2.32"
            TARGET_ABI="som"
            ;;
        11.0|11.00)
            if [ "$arch" = "ia64" ]; then
                echo "ERROR: HP-UX 11.0 is PA-RISC only" >&2; return 1
            fi
            TARGET="hppa2.0w-hp-hpux11.00"
            LAST_GCC_VER="11.4.0"
            DEFAULT_BINUTILS_VER="2.38"
            TARGET_ABI="som"
            ;;
        11.11)
            if [ "$arch" = "ia64" ]; then
                echo "ERROR: HP-UX 11.11 is PA-RISC only" >&2; return 1
            fi
            TARGET="hppa2.0w-hp-hpux11.11"
            LAST_GCC_VER="11.4.0"
            DEFAULT_BINUTILS_VER="2.38"
            TARGET_ABI="som"
            ;;
        11.23)
            case "$arch" in
                ia64) TARGET="ia64-hp-hpux11.23"
                      LAST_GCC_VER="14.2.0"
                      DEFAULT_BINUTILS_VER="2.40"
                      TARGET_ABI="elf"
                      ;;
                parisc*)
                    TARGET="hppa2.0w-hp-hpux11.23"
                    LAST_GCC_VER="11.4.0"
                    DEFAULT_BINUTILS_VER="2.38"
                    TARGET_ABI="som"
                    ;;
            esac
            ;;
        11.31|11.3|11)
            case "$arch" in
                ia64) TARGET="ia64-hp-hpux11.31"
                      LAST_GCC_VER="14.2.0"
                      DEFAULT_BINUTILS_VER="2.40"
                      TARGET_ABI="elf"
                      ;;
                parisc*)
                    echo "WARNING: HP-UX 11.31 on PA-RISC: GCC support ended at 11.x" >&2
                    TARGET="hppa2.0w-hp-hpux11.31"
                    LAST_GCC_VER="11.4.0"
                    DEFAULT_BINUTILS_VER="2.38"
                    TARGET_ABI="som"
                    ;;
            esac
            ;;
        *)
            echo "ERROR: Unknown HP-UX version '$ver'" >&2
            echo "       Valid: 9, 10.20, 11.0, 11.11, 11.23, 11.31" >&2
            return 1
            ;;
    esac

    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror --enable-targets=all"
}

# ---------------------------------------------------------------------------
# Tru64 UNIX / Digital UNIX / OSF/1
# ---------------------------------------------------------------------------
_platform_tru64() {
    local ver="$1"
    local arch="${2:-alpha}"

    if [ -n "$arch" ] && [ "$arch" != "alpha" ]; then
        echo "WARNING: Tru64/OSF is Alpha-only; ignoring -a $arch" >&2
    fi

    # OSF/1 3.x = Digital OSF/1 3.x
    # Tru64 4.x = Digital UNIX 4.0 = OSF/1 4.0
    # Tru64 5.x = Tru64 UNIX 5.x

    case "$ver" in
        3|3.2|3.x|osf3*)
            TARGET="alpha-dec-osf3.2"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.20"
            GCC_MIN_HOST_VER="2.95"
            ;;
        4|4.0|4.0d|4.0e|4.0f|4.0g)
            TARGET="alpha-dec-osf4.0"
            LAST_GCC_VER="4.6.4"
            DEFAULT_BINUTILS_VER="2.38"
            ;;
        5|5.0|5.0a|5.0b)
            TARGET="alpha-dec-osf5.0"
            LAST_GCC_VER="4.6.4"
            DEFAULT_BINUTILS_VER="2.38"
            ;;
        5.1|5.1a|5.1b|tru64|latest)
            TARGET="alpha-dec-osf5.1"
            LAST_GCC_VER="4.6.4"
            DEFAULT_BINUTILS_VER="2.38"
            ;;
        *)
            echo "ERROR: Unknown Tru64/OSF version '$ver'" >&2
            echo "       Valid: 3.2, 4.0, 5.0, 5.1" >&2
            return 1
            ;;
    esac

    TARGET_ABI="elf"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# IRIX
# ---------------------------------------------------------------------------
_platform_irix() {
    local ver="$1"
    local arch="${2:-mips}"
    local mips_endian="mips"  # big-endian default

    case "$arch" in
        mips|mips32|mips-be|"") mips_endian="mips"   ;;
        mipsel|mips-le|mips-el) mips_endian="mipsel" ;;
        mips64)                  mips_endian="mips64" ;;
        *)
            echo "ERROR: Unknown arch '$arch' for IRIX. Use: mips, mipsel, mips64" >&2
            return 1
            ;;
    esac

    case "$ver" in
        5|5.2|5.2.*)
            TARGET="${mips_endian}-sgi-irix5.2"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.32"
            TARGET_ABI="ecoff"
            ;;
        5.3|5.3.*)
            TARGET="${mips_endian}-sgi-irix5.3"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.32"
            TARGET_ABI="ecoff"
            ;;
        6.2|6.2.*)
            TARGET="${mips_endian}-sgi-irix6.2"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.32"
            TARGET_ABI="elf"
            ;;
        6.4|6.4.*)
            TARGET="${mips_endian}-sgi-irix6.4"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.32"
            TARGET_ABI="elf"
            ;;
        6.5|6.5.*|6|latest)
            TARGET="${mips_endian}-sgi-irix6.5"
            LAST_GCC_VER="8.5.0"
            DEFAULT_BINUTILS_VER="2.38"
            TARGET_ABI="elf"
            ;;
        *)
            echo "ERROR: Unknown IRIX version '$ver'" >&2
            echo "       Valid: 5.2, 5.3, 6.2, 6.4, 6.5" >&2
            return 1
            ;;
    esac

    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld --disable-multilib"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# NetBSD
# ---------------------------------------------------------------------------
_platform_netbsd() {
    local ver="$1"
    local arch="${2:-x86}"
    local nbsd_arch nbsd_triple

    arch=$(_normalize_arch "$arch")

    case "$arch" in
        i386)     nbsd_arch="i486" ;;
        x86_64)   nbsd_arch="x86_64" ;;
        sparc)    nbsd_arch="sparc" ;;
        sparc64)  nbsd_arch="sparc64" ;;
        ppc)      nbsd_arch="powerpc" ;;
        ppc64)    nbsd_arch="powerpc64" ;;
        mips)     nbsd_arch="mips" ;;
        mips64)   nbsd_arch="mips64el" ;;
        arm)      nbsd_arch="arm" ;;
        aarch64)  nbsd_arch="aarch64" ;;
        alpha)    nbsd_arch="alpha" ;;
        hppa)     nbsd_arch="hppa" ;;
        m68k)     nbsd_arch="m68k" ;;
        vax)      nbsd_arch="vax" ;;
        *)
            echo "ERROR: Unknown arch '$arch' for NetBSD" >&2
            return 1
            ;;
    esac

    local nbsd_maj
    nbsd_maj=$(echo "$ver" | cut -d. -f1)

    # NetBSD < 2.0: a.out on many architectures; ELF on newer ones
    # NetBSD >= 2.0: fully ELF
    case "$ver" in
        1.0|1.1|1.2|1.3|1.4)
            TARGET="${nbsd_arch}-unknown-netbsd${ver}"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            TARGET_ABI="aout"
            ;;
        1.5|1.5.*)
            TARGET="${nbsd_arch}-unknown-netbsdelf${ver}"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            ;;
        1.6|1.6.*)
            TARGET="${nbsd_arch}-unknown-netbsdelf${ver}"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        *)
            TARGET="${nbsd_arch}-unknown-netbsd${ver}"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
    esac

    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# FreeBSD
# ---------------------------------------------------------------------------
_platform_freebsd() {
    local ver="$1"
    local arch="${2:-x86}"
    local fbsd_arch

    arch=$(_normalize_arch "$arch")

    case "$arch" in
        i386)     fbsd_arch="i386"    ;;
        x86_64)   fbsd_arch="x86_64" ;;
        sparc64)  fbsd_arch="sparc64" ;;
        ppc)      fbsd_arch="powerpc" ;;
        ppc64)    fbsd_arch="powerpc64" ;;
        mips)     fbsd_arch="mips"   ;;
        mips64)   fbsd_arch="mips64el" ;;
        arm)      fbsd_arch="arm"    ;;
        aarch64)  fbsd_arch="aarch64" ;;
        alpha)    fbsd_arch="alpha"  ;;
        ia64)     fbsd_arch="ia64"   ;;
        *)
            echo "ERROR: Unknown arch '$arch' for FreeBSD" >&2
            return 1
            ;;
    esac

    local fbsd_maj
    fbsd_maj=$(echo "$ver" | cut -d. -f1)

    case "$fbsd_maj" in
        2)
            TARGET="${fbsd_arch}-unknown-freebsd${ver}"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            TARGET_ABI="aout"
            ;;
        3)
            TARGET="${fbsd_arch}-unknown-freebsd${ver}"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            TARGET_ABI="elf"
            ;;
        4|5)
            TARGET="${fbsd_arch}-unknown-freebsd${ver}"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        6|7|8|9|10|11|12|13|14|15)
            TARGET="${fbsd_arch}-unknown-freebsd${ver}"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        *)
            echo "ERROR: Unknown FreeBSD version '$ver'" >&2
            echo "       Valid: 2.2, 3.5, 4.11, 5.5, 6.4, 7.4, 8.4, 9.3, 10.4, 11.4, 12.4, 13.2, 14.x" >&2
            return 1
            ;;
    esac

    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# OpenBSD
# ---------------------------------------------------------------------------
_platform_openbsd() {
    local ver="$1"
    local arch="${2:-x86}"
    local obsd_arch

    arch=$(_normalize_arch "$arch")

    case "$arch" in
        i386)    obsd_arch="i386"    ;;
        x86_64)  obsd_arch="x86_64" ;;
        sparc)   obsd_arch="sparc"  ;;
        sparc64) obsd_arch="sparc64" ;;
        ppc)     obsd_arch="powerpc" ;;
        mips64)  obsd_arch="mips64el" ;;
        arm)     obsd_arch="arm"    ;;
        aarch64) obsd_arch="aarch64" ;;
        alpha)   obsd_arch="alpha"  ;;
        hppa)    obsd_arch="hppa"   ;;
        m68k)    obsd_arch="m68k"   ;;
        *)
            echo "ERROR: Unknown arch '$arch' for OpenBSD" >&2
            return 1
            ;;
    esac

    local obsd_maj
    obsd_maj=$(echo "$ver" | cut -d. -f1)

    case "$obsd_maj" in
        2|3)
            TARGET="${obsd_arch}-unknown-openbsd${ver}"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            ;;
        4|5|6|7)
            TARGET="${obsd_arch}-unknown-openbsd${ver}"
            LAST_GCC_VER="14.2.0"
            DEFAULT_BINUTILS_VER="2.40"
            ;;
        *)
            echo "ERROR: Unknown OpenBSD version '$ver'" >&2
            return 1
            ;;
    esac

    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# Linux
# ---------------------------------------------------------------------------
_platform_linux() {
    local ver="$1"
    local arch="${2:-x86_64}"

    arch=$(_normalize_arch "$arch")

    local linux_arch linux_abi
    case "$arch" in
        i386|i486|i586|i686) linux_arch="i686"; linux_abi="gnu" ;;
        x86_64)   linux_arch="x86_64";   linux_abi="gnu"     ;;
        aarch64)  linux_arch="aarch64";  linux_abi="gnu"     ;;
        arm)      linux_arch="arm";      linux_abi="gnueabihf" ;;
        armhf)    linux_arch="arm";      linux_abi="gnueabihf" ;;
        armel)    linux_arch="arm";      linux_abi="gnueabi"  ;;
        ppc)      linux_arch="powerpc";  linux_abi="gnu"     ;;
        ppc64)    linux_arch="powerpc64";linux_abi="gnu"     ;;
        ppc64le)  linux_arch="powerpc64le"; linux_abi="gnu"  ;;
        mips)     linux_arch="mips";     linux_abi="gnu"     ;;
        mipsel)   linux_arch="mipsel";   linux_abi="gnu"     ;;
        mips64)   linux_arch="mips64";   linux_abi="gnuabi64";;
        mips64el) linux_arch="mips64el"; linux_abi="gnuabi64";;
        riscv64)  linux_arch="riscv64";  linux_abi="gnu"     ;;
        s390x)    linux_arch="s390x";    linux_abi="gnu"     ;;
        alpha)    linux_arch="alpha";    linux_abi="gnu"     ;;
        sparc)    linux_arch="sparc";    linux_abi="gnu"     ;;
        sparc64)  linux_arch="sparc64";  linux_abi="gnu"     ;;
        ia64)     linux_arch="ia64";     linux_abi="gnu"     ;;
        m68k)     linux_arch="m68k";     linux_abi="gnu"     ;;
        *)
            echo "ERROR: Unknown arch '$arch' for Linux" >&2
            return 1
            ;;
    esac

    TARGET="${linux_arch}-unknown-linux-${linux_abi}"
    LAST_GCC_VER="14.2.0"
    DEFAULT_BINUTILS_VER="2.40"
    TARGET_ABI="elf"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# SCO OpenServer
# ---------------------------------------------------------------------------
_platform_sco() {
    local ver="$1"
    local arch="${2:-i386}"

    case "$ver" in
        3|3.2|3.2v4|3.2v5)
            TARGET="i386-pc-sco3.2v5"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            ;;
        5|5.0|5.0.*)
            TARGET="i686-pc-sco5"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        *)
            echo "ERROR: Unknown SCO version '$ver'" >&2
            echo "       Valid: 3.2, 5.0" >&2
            return 1
            ;;
    esac

    TARGET_ABI="elf"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# UnixWare
# ---------------------------------------------------------------------------
_platform_unixware() {
    local ver="$1"
    local arch="${2:-i386}"

    case "$ver" in
        2|2.1|2.1.*)
            TARGET="i386-unixware2.1"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            ;;
        7|7.1|7.1.*)
            TARGET="i686-pc-sysv5"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        *)
            echo "ERROR: Unknown UnixWare version '$ver'" >&2
            echo "       Valid: 2.1, 7.1" >&2
            return 1
            ;;
    esac

    TARGET_ABI="elf"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# Interix / Windows Services for UNIX
# ---------------------------------------------------------------------------
_platform_interix() {
    local ver="${1:-3.5}"
    TARGET="i586-pc-interix${ver}"
    LAST_GCC_VER="4.9.4"
    DEFAULT_BINUTILS_VER="2.28"
    TARGET_ABI="elf"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# Architecture normalization helper
# ---------------------------------------------------------------------------
_normalize_arch() {
    local a="$1"
    case "$a" in
        x86|i386|i486|i586|i686|ia32) echo "i386" ;;
        x86_64|amd64|x64)             echo "x86_64" ;;
        ppc|powerpc|ppc32)             echo "ppc" ;;
        ppc64|powerpc64)               echo "ppc64" ;;
        ppc64le|powerpc64le)           echo "ppc64le" ;;
        arm|armhf|armv7)               echo "arm" ;;
        arm64|aarch64)                 echo "aarch64" ;;
        sparc|sparcv8)                 echo "sparc" ;;
        sparc64|sparcv9|ultrasparc)    echo "sparc64" ;;
        mips|mips32|mipsbe)            echo "mips" ;;
        mipsel|mipsle)                 echo "mipsel" ;;
        mips64|mips64be)               echo "mips64" ;;
        mips64el|mips64le)             echo "mips64el" ;;
        alpha)                         echo "alpha" ;;
        ia64|itanium)                  echo "ia64" ;;
        parisc|hppa|pa-risc)           echo "hppa" ;;
        riscv64|riscv)                 echo "riscv64" ;;
        s390|s390x)                    echo "s390x" ;;
        m68k|68k)                      echo "m68k" ;;
        vax)                           echo "vax" ;;
        *)                             echo "$a" ;;
    esac
}

# ===========================================================================
# Historical / early-era UNIX platforms
# ===========================================================================

# ---------------------------------------------------------------------------
# SunOS 4.x  (BSD-based, pre-Solaris Sun workstations, 1988-1994)
# sun3  = Motorola 68020/68030 hardware
# sun4  = SPARC V7/V8 hardware (4c = SPARC IPC/IPX/ELC/SLC, 4m = SS1/SS2/SS5)
# sun386i = rare Intel 386 variant
# ---------------------------------------------------------------------------
_platform_sunos4() {
    local ver="$1"
    local arch="${2:-sparc}"
    local sunos_ver

    case "$ver" in
        3.5|3.5.*)  sunos_ver="3.5";  arch="${2:-m68k}" ;;  # SunOS 3 on sun3
        4.0|4.0.*)  sunos_ver="4.0"  ;;
        4.1|4.1.0)  sunos_ver="4.1"  ;;
        4.1.1|4.1.1_U1) sunos_ver="4.1.1" ;;
        4.1.2)      sunos_ver="4.1.2" ;;
        4.1.3|4.1.3_U1|4.1.3B) sunos_ver="4.1.3" ;;
        4.1.4)      sunos_ver="4.1.4" ;;
        *)
            echo "ERROR: Unknown SunOS 4 version '$ver'" >&2
            echo "       Valid: 3.5, 4.0, 4.1, 4.1.1, 4.1.2, 4.1.3, 4.1.4" >&2
            return 1
            ;;
    esac

    case "$arch" in
        sparc|sparcv7|sparcv8|sun4|sun4c|sun4m|"") arch="sparc" ;;
        m68k|68k|68020|68030|sun3) arch="m68k" ;;
        i386|i486|sun386i)         arch="i386" ;;
        *)
            echo "ERROR: Unknown arch '$arch' for SunOS 4. Use: sparc, m68k, i386" >&2
            return 1
            ;;
    esac

    case "$arch" in
        sparc) TARGET="sparc-sun-sunos${sunos_ver}" ;;
        m68k)  TARGET="m68k-sun-sunos${sunos_ver}"  ;;
        i386)  TARGET="i386-sun-sunos${sunos_ver}"  ;;
    esac

    # GCC support: SunOS 4.x on SPARC lasted through GCC 8 on some configs.
    # GCC < 4.0 is recommended for era-appropriate builds.
    # GCC 2.7.2.3 was the classic SunOS 4.x cross-compiler.
    TARGET_ABI="aout"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"

    case "$sunos_ver" in
        3.5)
            # SunOS 3.x on sun3 (68020); GCC 2.7.x was widely used
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            ;;
        4.0|4.1|4.1.1|4.1.2|4.1.3|4.1.4)
            # GCC 8 dropped explicit SunOS 4.x support; GCC 4.7.4 is safest.
            # Use 2.7.2.3 for a period-appropriate cross-compiler.
            LAST_GCC_VER="4.7.4"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# DEC ULTRIX  (MIPS-based DEC workstations and servers, 1984-1995)
# DECstation 2100/3100/5000, VAX ULTRIX (less common for GCC cross)
# Succeeded by Digital UNIX / Tru64 on Alpha.
# ---------------------------------------------------------------------------
_platform_ultrix() {
    local ver="$1"
    local arch="${2:-mips}"
    local ultrix_ver

    case "$ver" in
        2.x|2*)        ultrix_ver="2.2"; arch="${2:-vax}"  ;;
        3.x|3*|3.1)   ultrix_ver="3.1"; arch="${2:-vax}"  ;;
        4.0|4.0.*)    ultrix_ver="4.0" ;;
        4.1|4.1.*)    ultrix_ver="4.1" ;;
        4.2|4.2.*)    ultrix_ver="4.2" ;;
        4.3|4.3.*)    ultrix_ver="4.3" ;;
        4.4|4.4.*|4.5) ultrix_ver="4.4" ;;
        *)
            echo "ERROR: Unknown ULTRIX version '$ver'" >&2
            echo "       Valid: 2.x, 3.x, 4.0, 4.1, 4.2, 4.3, 4.4" >&2
            return 1
            ;;
    esac

    case "$arch" in
        mips|mips-be|"") arch="mips" ;;
        mipsel|mips-le)  arch="mipsel" ;;
        vax)             arch="vax" ;;
        *)
            echo "ERROR: Unknown arch '$arch' for ULTRIX. Use: mips, mipsel, vax" >&2
            return 1
            ;;
    esac

    case "$arch" in
        mips|mipsel) TARGET="${arch}-dec-ultrix${ultrix_ver}" ;;
        vax)         TARGET="vax-dec-ultrix${ultrix_ver}"     ;;
    esac

    # GCC 3.4.6 was the last to have explicit ULTRIX support.
    # GCC 2.7.2.3 was era-appropriate for ULTRIX 4.x.
    TARGET_ABI="ecoff"   # ULTRIX MIPS used ECOFF object format
    LAST_GCC_VER="3.4.6"
    DEFAULT_BINUTILS_VER="2.17"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
    GCC_MIN_HOST_VER="2.95"
}

# ---------------------------------------------------------------------------
# NeXTStep / OpenStep  (NeXT workstations, 1988-1999)
# Used Mach-O object format; heavily patched GCC was shipped with NeXT SDK.
# Target: 68k NeXT hardware (NeXTStation, NeXTcube) or i386 NeXTStep Intel.
# NOTE: Requires NeXT-specific patches for GCC (not included here).
# ---------------------------------------------------------------------------
_platform_nextstep() {
    local ver="$1"
    local arch="${2:-m68k}"

    case "$arch" in
        m68k|68k|"") arch="m68k" ;;
        i386|i486|x86) arch="i386" ;;
        *)
            echo "ERROR: Unknown arch '$arch' for NeXTStep. Use: m68k, i386" >&2
            return 1
            ;;
    esac

    case "$ver" in
        1.0|2.0|2.1|3.0|3.1|3.2|3.3)
            TARGET="${arch}-next-nextstep${ver}"
            TARGET_ABI="macho"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            ;;
        4.0|4.1|4.2)   # OpenStep era
            TARGET="${arch}-next-openstep${ver}"
            TARGET_ABI="macho"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            ;;
        *)
            echo "ERROR: Unknown NeXTStep version '$ver'" >&2
            echo "       Valid: 2.0, 3.0, 3.1, 3.2, 3.3, 4.0, 4.1, 4.2" >&2
            return 1
            ;;
    esac

    echo "WARNING: NeXTStep requires NeXT-specific GCC patches." >&2
    echo "         Standard GCC will not produce Mach-O binaries without them." >&2
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# DYNIX/ptx  (Sequent Symmetry servers, SVR4-based SMP UNIX)
# ---------------------------------------------------------------------------
_platform_dynix() {
    local ver="$1"
    local arch="${2:-i386}"

    case "$ver" in
        1*|2*|3*)
            TARGET="i386-sequent-dynix${ver}"
            TARGET_ABI="aout"
            LAST_GCC_VER="3.4.6"
            DEFAULT_BINUTILS_VER="2.17"
            GCC_MIN_HOST_VER="2.95"
            ;;
        4*|ptx4*)
            TARGET="i386-sequent-ptx${ver}"
            TARGET_ABI="elf"
            LAST_GCC_VER="4.9.4"
            DEFAULT_BINUTILS_VER="2.28"
            ;;
        *)
            echo "ERROR: Unknown DYNIX version '$ver'" >&2
            return 1
            ;;
    esac

    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
}

# ---------------------------------------------------------------------------
# Linux 1.x  (kernel 1.0-1.2, a.out format, libc4)
# March 1994 - December 1995.  i386/i486 only for the initial a.out era.
# libc4 was based on the BSD libc port; a.out was the default object format.
# GCC 2.5.8 and 2.6.3 were the compilers of this era.
# binutils 2.5.2 is the era-correct cross-binutils (a.out default).
# NOTE: Modern binutils can still produce a.out for i386-linux but a.out
#       Linux is only practical to target with binutils <= 2.8.
# ---------------------------------------------------------------------------
_platform_linux1() {
    local ver="$1"
    local arch="${2:-i486}"

    case "$arch" in
        i386|i486|i586|x86|"") arch="i486" ;;
        *)
            echo "WARNING: Linux 1.x (libc4/a.out) was i386/i486 only." >&2
            echo "         Proceeding with arch '$arch' but results may vary." >&2
            arch=$(_normalize_arch "$arch")
            ;;
    esac

    case "$ver" in
        0.99*|1.0|1.0.*)  TARGET="${arch}-linux";       KERNEL_VER="1.0"  ;;
        1.1|1.1.*)         TARGET="${arch}-linux";       KERNEL_VER="1.1"  ;;
        1.2|1.2.*)         TARGET="${arch}-linux";       KERNEL_VER="1.2"  ;;
        *)
            echo "ERROR: Unknown Linux 1.x version '$ver'" >&2
            echo "       Valid: 0.99, 1.0, 1.1, 1.2" >&2
            return 1
            ;;
    esac

    TARGET_ABI="aout"
    # GCC 2.6.3 was the last era-appropriate compiler; 2.7.2.3 also works.
    # GCC 3.x and later can also target i486-linux but need --enable-a.out.
    LAST_GCC_VER="2.7.2.3"
    DEFAULT_GCC_VER="2.7.2.3"
    DEFAULT_BINUTILS_VER="2.7"
    LAST_BINUTILS_VER="2.7"
    GCC_MIN_HOST_VER="2.7"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
    LIBC_TYPE="libc4"

    echo "NOTE: Linux 1.x (libc4/a.out) cross-compiler." >&2
    echo "      Sysroot must contain libc4 headers and crt0.o." >&2
    echo "      See PROCEDURE.txt Section 5 for libc4 sysroot setup." >&2
}

# ---------------------------------------------------------------------------
# Linux 2.x  (kernel 2.0-2.2, ELF format, libc5)
# June 1996 - January 1999.  Dominant architectures: i386/i486/i586/i686.
# libc5 (5.x series) was the standard C library before glibc2.
# GCC 2.7.2.3 was the de-facto standard compiler for libc5 Linux.
# binutils 2.8.1 was widely used for this era.
# ---------------------------------------------------------------------------
_platform_linux2() {
    local ver="$1"
    local arch="${2:-i486}"

    arch=$(_normalize_arch "${arch:-i486}")

    case "$arch" in
        i386) arch="i486" ;;  # Minimum for Linux 2.0 era binaries
    esac

    case "$ver" in
        2.0|2.0.*)  TARGET="${arch}-unknown-linuxelf";  KERNEL_VER="2.0"  ;;
        2.1|2.1.*)  TARGET="${arch}-unknown-linuxelf";  KERNEL_VER="2.1"  ;;
        2.2|2.2.*)  TARGET="${arch}-unknown-linuxelf";  KERNEL_VER="2.2"  ;;
        # Allow short form
        2|elf)      TARGET="${arch}-unknown-linuxelf";  KERNEL_VER="2.0"  ;;
        *)
            echo "ERROR: Unknown Linux 2.x version '$ver'" >&2
            echo "       Valid: 2.0, 2.1, 2.2" >&2
            return 1
            ;;
    esac

    TARGET_ABI="elf"
    # GCC 2.7.2.3 was the canonical libc5 compiler; 2.95.3 also supports it.
    # Modern GCC can cross-compile for i486-linuxelf with a libc5 sysroot.
    LAST_GCC_VER="2.95.3"
    DEFAULT_GCC_VER="2.7.2.3"
    DEFAULT_BINUTILS_VER="2.8.1"
    LAST_BINUTILS_VER="2.28"
    GCC_MIN_HOST_VER="2.7"
    EXTRA_GCC_OPTS="--with-gnu-as --with-gnu-ld"
    EXTRA_BINUTILS_OPTS="--disable-werror"
    LIBC_TYPE="libc5"

    echo "NOTE: Linux 2.x (libc5/ELF) cross-compiler." >&2
    echo "      Sysroot must contain libc5 headers, crti.o, crtn.o, libc.so.5." >&2
    echo "      See PROCEDURE.txt Section 5 for libc5 sysroot setup." >&2
}

# ===========================================================================
# OLD-ERA GCC VERSION REFERENCE TABLE
# ===========================================================================
# GCC version history relevant to cross-compilation, earliest through 2.9x.
# "First targets" = architectures supported from that release onward.
#
# Version   Year  Notes / First new targets
# -------   ----  ---------------------------------------------------------
# 1.0        1987  VAX, 68000, SPARC (very limited, no cross-compiler path)
# 1.27       1988  First widely distributed release
# 1.37       1988  68020, ns32k added
# 1.40       1989  i386 added; stable 1.x milestone
# 1.42       1991  Last 1.x; some --target= support; RS/6000 prototype
# 2.0        1992  Complete RTL rewrite; i960, MIPS, RS/6000, PA-RISC, 88k
# 2.1        1992  PowerPC, Alpha stubs; more SPARC fixes
# 2.2.2      1992  H8/300, Convex, Clipper added
# 2.3.3      1992  HPPA/HP-UX, SH, i860 added
# 2.4.5      1993  x86-64 (very early), improvements
# 2.5.8      1994  Stable; standard for SunOS 4 and early Linux libc4
# 2.6.0      1994  First full ELF support; Linux ELF transition
# 2.6.3      1994  Last 2.6.x; stable for SunOS, IRIX, ULTRIX
# 2.7.0      1995  GCC 2.7; standard for Linux libc5 era
# 2.7.2      1996  Stable libc5 compiler; AIX, Solaris, HP-UX improved
# 2.7.2.1    1996  Patch release
# 2.7.2.2    1996  Patch release
# 2.7.2.3    1997  Final stable 2.7.x; last C-only era GCC
# 2.8.0      1998  C++ (g++) production quality
# 2.8.1      1998  Last 2.8.x; good SPARC/AIX/HP-UX support
# 2.95       1999  EGCS merge; major C++ improvement
# 2.95.1     1999  Bug fixes
# 2.95.2     2000  Widely deployed; standard in many distros
# 2.95.3     2001  Last 2.95.x; standard for old Solaris/AIX/HP-UX
# (3.x, 4.x ... covered in PROCEDURE.txt table)
#
# BINUTILS version history:
# 2.0        1991  Initial release
# 2.1        1992  gas 2.1; a.out and COFF support
# 2.2        1992  Alpha ELF, MIPS fixes
# 2.3        1993  Improved SPARC, i386
# 2.4        1993  SunOS 4 and Solaris 2 improvements
# 2.5        1993  ELF improvements; HPPA SOM
# 2.5.2      1994  Standard for Linux libc4 era; a.out by default for Linux
# 2.6        1995  ELF becomes standard for Linux; XCOFF improvements
# 2.7        1995  DWARF2 debugging; standard with GCC 2.7.x
# 2.8        1997  BFD improvements; ELF shared library support
# 2.8.1      1998  Bug fixes; standard with GCC 2.8.x and early 2.95
# 2.9.1      1998  Improved section handling
# 2.10       2000  Used with GCC 2.95.2+
# 2.10.1     2000  Widely deployed
# 2.11       2001  Bug fixes
# 2.11.2     2002  Patch release
# 2.12       2002  GCC 3.x era
# 2.13       2002
# 2.14       2003
# 2.15       2004
# 2.16       2005
# 2.17       2006  Used with GCC 3.4.6; last in old-gnu area on some mirrors
# (2.17 through 2.40 covered in PROCEDURE.txt table)
#
# GCC 1.x PLATFORM SUPPORT (cross-compiler targets available):
#   GCC 1.40: VAX, 68000/68020, SPARC, i386, ns32k, romp
#   GCC 1.42: above + RS/6000 (early), Pyramid, Alliant FX, Tron
#
# NOTE: GCC 1.x cross-compilation on modern Linux (GCC 6+) is extremely
# difficult due to K&R C code patterns and header conflicts. A Docker
# container with GCC 3.4.6 or 4.7 as host compiler is strongly recommended.
# See old-gcc-build.sh and PROCEDURE.txt for details.
