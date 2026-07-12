#!/bin/sh
# lib/libc5-sysroot.sh - Helpers for setting up libc4 and libc5 sysroots.
#
# Linux libc4 (a.out) sysroot: for Linux 1.0 (kernel 1.0-1.2, ~1994)
# Linux libc5 (ELF)   sysroot: for Linux 2.0 (kernel 2.0-2.2, ~1996-1998)
#
# The sysroot must contain:
#   libc4: kernel 1.x headers + libc4 headers + crt0.o
#   libc5: kernel 2.x headers + libc5 headers + crti.o/crtn.o/crt1.o + libc.so.5
#
# Source packages for libc4/libc5 headers:
#   Slackware 2.x/3.x CDROMs (libc4/libc5 era)
#   Red Hat Linux 4.x/5.x (last libc5 release: RHL 4.2, March 1997)
#   Debian 1.3 "Bo" (July 1997, last Debian with libc5)
#   MCC Interim Linux (early 1.0 era, libc4)
#   SLS Linux 1.05 (libc4)
#
# Package names:
#   Debian libc5:  libc5-dev_5.4.46-9_i386.deb (headers + libs)
#   Red Hat libc5: libc-5.3.12-18.i386.rpm, libc-devel-5.3.12.rpm
#   Slackware:     files from /var/adm/packages
#
# Linux kernel headers:
#   Kernel 1.0: https://mirrors.kernel.org/pub/linux/kernel/v1.0/linux-1.0.tar.gz
#   Kernel 2.0: https://mirrors.kernel.org/pub/linux/kernel/v2.0/linux-2.0.tar.gz
#
# libc5 source:
#   ftp://ftp.ibiblio.org/pub/Linux/libs/libc/5.x/
#   Typical: libc-5.4.46.tar.gz

# ---------------------------------------------------------------------------
# Print sysroot setup instructions for libc4 targets
# ---------------------------------------------------------------------------
print_libc4_sysroot_instructions() {
    local sysroot="$1"
    cat <<EOF
libc4 / Linux 1.0 Sysroot Setup
================================
Target sysroot: $sysroot

A libc4 sysroot requires headers from the Linux 1.0 kernel and libc4
(the BSD-based C library used on early Linux, a.out format).

Step 1: Create the sysroot directories
  mkdir -p $sysroot/usr/include
  mkdir -p $sysroot/usr/lib
  mkdir -p $sysroot/lib

Step 2: Get Linux 1.0 kernel headers
  # Download Linux 1.0 source
  wget https://mirrors.kernel.org/pub/linux/kernel/v1.0/linux-1.0.tar.gz
  tar xzf linux-1.0.tar.gz
  # Copy kernel headers
  cp -r linux-1.0/include/linux   $sysroot/usr/include/
  cp -r linux-1.0/include/asm-i386 $sysroot/usr/include/asm
  # Note: asm -> asm-i386 for i386 target

Step 3: Get libc4 headers and libraries
  Method A: Extract from a Slackware 1.x or SLS disk image
    # Example from Slackware 1.01:
    # The libc.a and header files are in the 'a' disk series.

  Method B: Extract from an old Linux installation tarball
    # Some archives of early Linux distributions are at:
    # https://archive.org/details/slackware-linux-1.0
    # https://archive.org/details/sls-linux-1.05

  Method C: Build libc4 from source (advanced)
    # libc4 source was the Linux port of BSD libc
    # Available at old mirrors (e.g., tsx-11.mit.edu archives)

  After obtaining libc4:
    cp stdio.h stdlib.h string.h ... $sysroot/usr/include/
    cp libc.a $sysroot/usr/lib/
    cp crt0.o $sysroot/usr/lib/

Step 4: Verify the sysroot
  ls $sysroot/usr/include/stdio.h
  ls $sysroot/usr/include/linux/version.h
  ls $sysroot/usr/lib/libc.a
  ls $sysroot/usr/lib/crt0.o

Minimal required headers for C cross-compilation:
  stdio.h stdlib.h string.h unistd.h errno.h sys/types.h
  sys/stat.h fcntl.h limits.h time.h signal.h
  linux/types.h linux/fs.h linux/kernel.h

Note on a.out format:
  Linux 1.0 uses a.out object format.  The cross-assembler (gas) and
  cross-linker (ld) from binutils 2.5.2 will produce a.out by default
  when targeting i486-linux.  Modern binutils may default to ELF;
  use binutils 2.5.2 or 2.6 for era-correct a.out output.
EOF
}

# ---------------------------------------------------------------------------
# Print sysroot setup instructions for libc5 targets
# ---------------------------------------------------------------------------
print_libc5_sysroot_instructions() {
    local sysroot="$1"
    cat <<EOF
libc5 / Linux 2.0 Sysroot Setup
================================
Target sysroot: $sysroot

A libc5 sysroot requires:
  - Linux 2.0 kernel headers (for sys/ and asm/ headers)
  - libc5 C library headers (stdio.h, stdlib.h, etc.)
  - libc5 startup files: crt1.o, crti.o, crtn.o
  - libc5 libraries: libc.a, libc.so.5.x, libm.a, libm.so.5.x

Step 1: Create sysroot directories
  mkdir -p $sysroot/usr/include
  mkdir -p $sysroot/usr/lib
  mkdir -p $sysroot/lib

Step 2: Get Linux 2.0 kernel headers
  wget https://mirrors.kernel.org/pub/linux/kernel/v2.0/linux-2.0.tar.gz
  tar xzf linux-2.0.tar.gz
  cp -r linux-2.0/include/linux   $sysroot/usr/include/
  cp -r linux-2.0/include/asm-i386 $sysroot/usr/include/asm
  ln -sfn asm-i386 $sysroot/usr/include/asm  # i386 target symlink

Step 3: Get libc5 headers and libraries

  Method A: From Debian 1.3 "Bo" packages (recommended)
    # Download libc5-dev package from Debian archive:
    # http://archive.debian.org/debian/dists/bo/main/binary-i386/libs/
    # File: libc5-dev_5.4.46-9_i386.deb
    apt-get download libc5-dev  # or use ar/dpkg to extract
    dpkg -x libc5-dev_5.4.46-9_i386.deb /tmp/libc5-extract
    cp -r /tmp/libc5-extract/usr/include/* $sysroot/usr/include/
    cp -r /tmp/libc5-extract/usr/lib/*     $sysroot/usr/lib/

  Method B: From Red Hat Linux 4.2 RPMs
    # http://archive.redhat.com/pub/redhat/linux/4.2/i386/RedHat/RPMS/
    # Packages: libc-5.3.12-18.i386.rpm, libc-devel-5.3.12-18.i386.rpm
    rpm2cpio libc-devel-5.3.12-18.i386.rpm | cpio -id
    rpm2cpio libc-5.3.12-18.i386.rpm | cpio -id
    cp -r usr/include/* $sysroot/usr/include/
    cp -r usr/lib/*     $sysroot/usr/lib/
    cp -r lib/*         $sysroot/lib/

  Method C: Build libc5 from source
    # libc5 source: ftp://ftp.ibiblio.org/pub/Linux/libs/libc/5.x/
    # Typical: libc-5.4.46.tar.gz
    # Build requires Linux kernel headers (step 2 must be done first)
    # See libc5 README for build instructions (requires special flags)

Step 4: Ensure shared library symlinks are correct
  # libc5 expects these symlinks:
  ls $sysroot/lib/libc.so.5     # should exist or be symlinked
  ls $sysroot/lib/ld-linux.so.1 # Linux dynamic linker for libc5

  # Create symlinks if needed:
  ln -sfn libc.so.5.x.y $sysroot/lib/libc.so.5
  ln -sfn ld-linux.so.1.x.y $sysroot/lib/ld-linux.so.1

Step 5: Verify the sysroot
  ls $sysroot/usr/include/stdio.h
  ls $sysroot/usr/include/linux/version.h
  ls $sysroot/usr/lib/libc.a
  ls $sysroot/usr/lib/crt1.o       # ELF startup file
  ls $sysroot/usr/lib/crti.o       # ELF init section
  ls $sysroot/usr/lib/crtn.o       # ELF fini section

libc5 vs glibc2 note:
  Linux distributions began switching to glibc2 (libc6) around 1997-1998.
  Red Hat Linux 5.0 (October 1997) was the first major glibc2 distribution.
  Debian 2.0 "Hamm" (July 1998) completed the transition.
  For glibc2 cross-compilation, use the standard 'linux' platform type.

Testing the cross-compiler:
  # After building, test with a minimal C program:
  echo 'int main(){return 0;}' > /tmp/test.c
  i486-unknown-linuxelf-gcc -nostdlib -o /tmp/test /tmp/test.c $sysroot/usr/lib/crt1.o
  # The resulting binary should be ELF, i386, dynamically linked to libc.so.5
  file /tmp/test
EOF
}

# ---------------------------------------------------------------------------
# Attempt to set up a minimal libc5 sysroot automatically from Debian archive
# ---------------------------------------------------------------------------
setup_libc5_sysroot_from_debian() {
    local sysroot="$1"
    local work="$2"

    local deb_base="http://archive.debian.org/debian/dists/bo/main/binary-i386/libs"
    local libc5_dev_deb="libc5-dev_5.4.46-9_i386.deb"
    local libc5_deb="libc5_5.4.46-9_i386.deb"

    if ! command -v dpkg-deb >/dev/null 2>&1 && ! command -v ar >/dev/null 2>&1; then
        echo "ERROR: Need dpkg-deb or ar to extract .deb packages" >&2
        return 1
    fi

    mkdir -p "$work" "$sysroot/usr/include" "$sysroot/usr/lib" "$sysroot/lib"

    log "Downloading Debian libc5-dev from archive.debian.org..."
    _download_file "${deb_base}/${libc5_dev_deb}" "${work}/${libc5_dev_deb}" || return 1
    _download_file "${deb_base}/${libc5_deb}"     "${work}/${libc5_deb}"     || return 1

    _extract_deb "${work}/${libc5_dev_deb}" "${work}/libc5-dev"
    _extract_deb "${work}/${libc5_deb}"     "${work}/libc5"

    [ -d "${work}/libc5-dev/usr/include" ] && \
        cp -r "${work}/libc5-dev/usr/include/." "$sysroot/usr/include/"
    [ -d "${work}/libc5-dev/usr/lib" ] && \
        cp -r "${work}/libc5-dev/usr/lib/."     "$sysroot/usr/lib/"
    [ -d "${work}/libc5/lib" ] && \
        cp -r "${work}/libc5/lib/."             "$sysroot/lib/"
    [ -d "${work}/libc5/usr/lib" ] && \
        cp -r "${work}/libc5/usr/lib/."         "$sysroot/usr/lib/"

    log "libc5 sysroot populated at $sysroot"
    log "Next: add Linux kernel headers (see print_libc5_sysroot_instructions)"
}

_extract_deb() {
    local deb="$1"
    local dest="$2"
    mkdir -p "$dest"
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "$deb" "$dest"
    else
        # Manual extraction with ar + tar
        (cd "$dest" && \
            ar x "$deb" && \
            if [ -f data.tar.xz ]; then
                xz -dc data.tar.xz | tar xf -
            elif [ -f data.tar.gz ]; then
                gzip -dc data.tar.gz | tar xf -
            elif [ -f data.tar.bz2 ]; then
                bzip2 -dc data.tar.bz2 | tar xf -
            fi
        )
    fi
}

# ---------------------------------------------------------------------------
# Kernel header extraction helper
# ---------------------------------------------------------------------------
setup_kernel_headers() {
    local kernel_ver="$1"
    local sysroot="$2"
    local work="$3"
    local arch="${4:-i386}"

    local kernel_url
    local kernel_major
    kernel_major=$(echo "$kernel_ver" | cut -d. -f1-2)

    case "$kernel_major" in
        1.0|1.1|1.2|1.3) kernel_url="https://mirrors.kernel.org/pub/linux/kernel/v1.0/linux-${kernel_ver}.tar.gz" ;;
        2.0|2.1|2.2)     kernel_url="https://mirrors.kernel.org/pub/linux/kernel/v2.0/linux-${kernel_ver}.tar.gz" ;;
        2.4)              kernel_url="https://mirrors.kernel.org/pub/linux/kernel/v2.4/linux-${kernel_ver}.tar.gz" ;;
        *)
            echo "ERROR: Unsupported kernel version for header extraction: $kernel_ver" >&2
            return 1
            ;;
    esac

    local archive="${work}/linux-${kernel_ver}.tar.gz"
    mkdir -p "$work"

    log "Downloading Linux $kernel_ver kernel headers..."
    _download_file "$kernel_url" "$archive" || return 1

    log "Extracting kernel headers..."
    (cd "$work" && gzip -dc "$archive" | tar xf - \
        "linux-${kernel_ver}/include/linux" \
        "linux-${kernel_ver}/include/asm-${arch}" \
        2>/dev/null || \
     gzip -dc "$archive" | tar xf - \
        --wildcards \
        "linux-${kernel_ver}/include/linux/*" \
        "linux-${kernel_ver}/include/asm-${arch}/*" \
        2>/dev/null
    ) || {
        echo "ERROR: Failed to extract kernel headers" >&2
        return 1
    }

    mkdir -p "$sysroot/usr/include"
    cp -r "${work}/linux-${kernel_ver}/include/linux" "$sysroot/usr/include/"
    cp -r "${work}/linux-${kernel_ver}/include/asm-${arch}" "$sysroot/usr/include/asm"

    log "Kernel $kernel_ver headers installed to $sysroot/usr/include/"
}
