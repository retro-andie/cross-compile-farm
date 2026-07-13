# cross-compile-farm
The cross-compile-farm is a set of shell scripts meant to run on modern Linux and NetBSD to setup cross-compilers for a variety of legacy UNIX systems.

There are a set of patches for GCC and binutils that will allow versions down to GCC 2.7 to build on modern systems. GCC 1 requires that we use GCC 2.7.2.3 as an intermediate compiler.


Full options:
  ./build-cross.sh [options] <platform> <version>  

  -a <arch>   Architecture override: sparc, x86, x86_64, ppc, ppc64, mips,  
                  mips64, alpha, ia64, parisc, arm, aarch64  
  -g <ver>    GCC version override (e.g., 4.6.4, 8.5.0, 13.3.0)  
  -b <ver>    Binutils version override (e.g., 2.28, 2.40)  
  -p <dir>    Install prefix (default: /opt/cross)  
  -s <dir>    Sysroot base directory (default: /opt/sysroots)  
  -S <dir>    Exact sysroot path (overrides auto-detection from -s)  
  -j <n>      Parallel make jobs (default: auto-detect nproc/ncpu)  
  -d <dir>    Build work directory (default: /tmp/cross-build-PID)  
  -D <dir>    Source download directory (default: /opt/cross-src)  
  -H <triple> Canadian cross: the compiler will RUN on <triple>, not the  
              build machine.  Requires BUILD→HOST cross-compiler already  
              installed.  Example: -H sparc-sun-solaris2.6  
  -r          Build runtime libraries (libgcc, libstdc++) -- requires  
              complete sysroot with target libc  
  -k          Keep build directory after successful build  
  -n          Dry run: show what would happen  
  -v          Verbose output  
  -h          Show help  
  
Environment overrides:  
  CROSS_PREFIX          Installation prefix  
  CROSS_SYSROOT         Sysroot base directory  
  CROSS_SRCDIR          Source download directory  
  MAKE_JOBS             Parallel build jobs  
  HOST_CC               Host C compiler (default: gcc)  
  HOST_CXX              Host C++ compiler (default: g++)  
  GNU_MIRROR            GNU FTP mirror (default: https://ftpmirror.gnu.org)  
  COMPILER_HOST         Canadian cross host triple (same as -H)  
  COMPILER_HOST_SYSROOT Sysroot for the COMPILER_HOST system  
  
By default, the last supported GCC and binutils for the target platform is   picked.

We use the GCC major version to roughly split this up into eras.  
Era 1 - GCC 1.x  
Early Era 2 - GCC 2.x through 2.7  
Late Era 2 - GCC 2.7 through 2.95  
Modern: GCC 3 through 4  
Current: GCC 5+  
