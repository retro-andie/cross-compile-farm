#!/bin/sh
# test-builds.sh - Exercise suite for historical cross-compiler builds.
#
# Runs dry-run validation, optional bootstrap GCC smoke tests, and optionally
# real builds for all supported historical cross-compiler configurations.
#
# Usage:
#   ./test-builds.sh                         # dry-run tests only
#   ./test-builds.sh --bootstrap             # also build bootstrap GCC 2.7.2.3
#   ./test-builds.sh --era era1              # real builds for GCC 1.x targets only
#   ./test-builds.sh --era era2-early        # real builds for GCC 2.0-2.4 targets
#   ./test-builds.sh --era era2-late         # real builds for GCC 2.5-2.8 targets
#   ./test-builds.sh --era all               # all eras (slow; real downloads+builds)
#   ./test-builds.sh --target i486-linux     # single target real build
#   ./test-builds.sh --list                  # list all test cases
#
# Exit codes:
#   0   all selected tests passed
#   1   one or more tests failed (summary printed at end)

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/prereqs.sh"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0
FAILURES=""

DO_BOOTSTRAP=""
ERA_FILTER=""
TARGET_FILTER=""
LIST_ONLY=""

# Colors (suppressed if not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; RESET='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; RESET=''
fi

# ---------------------------------------------------------------------------
# Test case table
# Format: era|gcc_ver|binutils_ver|platform|platform_ver|arch_flag
# arch_flag is optional (-a <arch>) — empty means use platform default
# ---------------------------------------------------------------------------
TEST_CASES='
era1|1.42|2.7|linux1|1.0|
era1|1.40|2.7|linux1|1.0|
era2-early|2.3.3|2.7|linux1|1.0|
era2-early|2.3.3|2.7|linux2|2.0|
era2-early|2.4.5|2.7|linux2|2.0|
era2-late|2.5.8|2.7|linux2|2.0|
era2-late|2.7.2.3|2.7|linux2|2.0|
era2-late|2.7.2.3|2.8.1|linux2|2.2|
era2-late|2.7.2.3|2.28|sunos4|4.1.4|
era2-late|2.7.2.3|2.17|ultrix|4.4|
era2-late|2.8.1|2.8.1|linux2|2.2|
era2-95|2.95.3|2.8.1|linux2|2.2|
era2-95|2.95.3|2.17|ultrix|4.4|
era2-95|2.95.3|2.17|sunos4|4.1.4|
era2-95|2.95.3|2.17|tru64|4.0|
modern|3.4.6|2.17|tru64|5.1|
modern|3.4.6|2.17|solaris|2.6|
modern|4.6.4|2.38|irix|6.5|
modern|4.9.4|2.38|solaris|2.9|
modern|8.5.0|2.38|hpux|11.0|
'

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --bootstrap)     DO_BOOTSTRAP="yes" ;;
        --era)           ERA_FILTER="$2"; shift ;;
        --target)        TARGET_FILTER="$2"; shift ;;
        --list)          LIST_ONLY="yes" ;;
        --help|-h)
            grep '^#' "$0" | head -20 | sed 's/^# //'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_pass() { printf "${GREEN}PASS${RESET} %s\n" "$*"; PASS=$((PASS+1)); }
_fail() { printf "${RED}FAIL${RESET} %s\n" "$*"; FAIL=$((FAIL+1)); FAILURES="$FAILURES\n  FAIL: $*"; }
_skip() { printf "${YELLOW}SKIP${RESET} %s\n" "$*"; SKIP=$((SKIP+1)); }
_info() { printf "     %s\n" "$*"; }

# Run build-cross.sh -n (dry run) and check exit code
_dry_run_test() {
    local label="$1"; shift
    if sh "$SCRIPT_DIR/build-cross.sh" -n "$@" > /tmp/test_out_$$.txt 2>&1; then
        _pass "$label"
        return 0
    else
        _fail "$label (exit $?)"
        _info "Output: $(tail -5 /tmp/test_out_$$.txt | tr '\n' '|')"
        return 1
    fi
}

# Run a real build test (requires internet for source downloads)
_real_build_test() {
    local label="$1"; shift
    local logfile="/tmp/test_build_$$.log"
    if sh "$SCRIPT_DIR/build-cross.sh" "$@" > "$logfile" 2>&1; then
        _pass "$label"
        return 0
    else
        # Network/availability failures are SKIP, not FAIL
        if grep -q 'Could not download\|Failed to download' "$logfile" 2>/dev/null; then
            _skip "$label (source not available for download)"
            return 0
        fi
        _fail "$label"
        _info "Log: $logfile"
        _info "Last error: $(grep -i 'error\|ERROR' "$logfile" | tail -3 | tr '\n' '|')"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# List test cases
# ---------------------------------------------------------------------------
if [ -n "$LIST_ONLY" ]; then
    printf "%-12s %-10s %-10s %-12s %-8s %s\n" ERA GCC BINUTILS PLATFORM VER ARCH
    printf '%s\n' "-------------------------------------------------------"
    _tc_list=$(mktemp /tmp/test_casesXXXXXX)
    echo "$TEST_CASES" | grep -v '^$' > "$_tc_list"
    while IFS='|' read era gcc_ver bu_ver plat plat_ver arch; do
        printf "%-12s %-10s %-10s %-12s %-8s %s\n" \
            "$era" "$gcc_ver" "$bu_ver" "$plat" "$plat_ver" "${arch:-(default)}"
    done < "$_tc_list"
    rm -f "$_tc_list"
    exit 0
fi

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo ""
echo "Cross-compiler test suite"
echo "========================="
echo "Script: $SCRIPT_DIR/build-cross.sh"
echo "Date:   $(date)"
echo ""

# ---------------------------------------------------------------------------
# Phase 0: Syntax checks
# ---------------------------------------------------------------------------
echo "Phase 0: Script syntax checks"
echo "------------------------------"
for f in \
        "$SCRIPT_DIR/build-cross.sh" \
        "$SCRIPT_DIR/lib/platforms.sh" \
        "$SCRIPT_DIR/lib/prereqs.sh" \
        "$SCRIPT_DIR/lib/fetch.sh" \
        "$SCRIPT_DIR/lib/old-gcc-build.sh" \
        "$SCRIPT_DIR/lib/bootstrap-gcc.sh" \
        "$SCRIPT_DIR/lib/build-binutils.sh" \
        "$SCRIPT_DIR/lib/build-gcc.sh" \
        "$SCRIPT_DIR/lib/old-host.sh" \
        "$SCRIPT_DIR/lib/libc5-sysroot.sh"; do
    if sh -n "$f" 2>/dev/null; then
        _pass "syntax: $(basename $f)"
    else
        _fail "syntax: $(basename $f)"
    fi
done
echo ""

# ---------------------------------------------------------------------------
# Phase 1: Dry-run tests for all test cases
# ---------------------------------------------------------------------------
echo "Phase 1: Dry-run tests (no downloads, no builds)"
echo "-------------------------------------------------"
_tc_file=$(mktemp /tmp/test_casesXXXXXX)
echo "$TEST_CASES" | grep -v '^$' > "$_tc_file"
while IFS='|' read era gcc_ver bu_ver plat plat_ver arch; do
    # Apply ERA_FILTER
    if [ -n "$ERA_FILTER" ] && [ "$ERA_FILTER" != "all" ]; then
        [ "$era" = "$ERA_FILTER" ] || continue
    fi

    _label="dry-run: $era  gcc=$gcc_ver  $plat $plat_ver"
    _arch_flag=""
    [ -n "$arch" ] && _arch_flag="-a $arch"

    _dry_run_test "$_label" -g "$gcc_ver" -b "$bu_ver" $_arch_flag "$plat" "$plat_ver"
done < "$_tc_file"
rm -f "$_tc_file"
echo ""

# ---------------------------------------------------------------------------
# Phase 2: Bootstrap GCC build (optional)
# ---------------------------------------------------------------------------
if [ -n "$DO_BOOTSTRAP" ]; then
    echo "Phase 2: Bootstrap GCC 2.7.2.3 build"
    echo "--------------------------------------"

    # Set path variables BEFORE sourcing libs: bootstrap-gcc.sh evaluates
    # BOOTSTRAP_GCC_PREFIX at source time, so it must already be set.
    export HOST_CC="${HOST_CC:-gcc}"
    export HOST_CXX="${HOST_CXX:-g++}"
    export GNU_MIRROR="${GNU_MIRROR:-https://ftpmirror.gnu.org}"
    export CROSS_SRCDIR="${CROSS_SRCDIR:-/opt/cross-src}"
    export CROSS_BUILDDIR="${CROSS_BUILDDIR:-/tmp/cross-build-test-$$}"
    export BOOTSTRAP_GCC_PREFIX="${BOOTSTRAP_GCC_PREFIX:-/tmp/bootstrap-gcc-test}"

    # Load libraries needed by build_bootstrap_gcc
    log() { echo "==> $*"; }
    for _lib in fetch old-gcc-build bootstrap-gcc; do
        . "$SCRIPT_DIR/lib/${_lib}.sh"
    done

    # Check 32-bit support (use a real source file, not /dev/null)
    _m32_tmp=$(mktemp /tmp/m32checkXXXXXX)
    printf 'int main(void){return 0;}\n' > "$_m32_tmp"
    if "${HOST_CC}" -m32 -x c -o /dev/null "$_m32_tmp" 2>/dev/null; then
        _info "32-bit (-m32) support: available"
    else
        _info "32-bit (-m32) support: NOT available (bootstrap will attempt without -m32)"
    fi
    rm -f "$_m32_tmp"

    mkdir -p "$CROSS_SRCDIR" "$CROSS_BUILDDIR"

    if build_bootstrap_gcc 2>&1; then
        _pass "bootstrap GCC 2.7.2.3 build"
        if [ -x "$BOOTSTRAP_GCC_PREFIX/bin/gcc" ]; then
            _info "Bootstrap GCC: $BOOTSTRAP_GCC_PREFIX/bin/gcc"
            if _bootstrap_smoke_test "$BOOTSTRAP_GCC_PREFIX/bin/gcc"; then
                _pass "bootstrap GCC K&R smoke test"
            else
                _fail "bootstrap GCC K&R smoke test"
            fi
        fi
    else
        _fail "bootstrap GCC 2.7.2.3 build"
        _info "See $CROSS_BUILDDIR/bootstrap-gcc-2.7.2.3/ for logs"
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# Phase 3: Real builds (only when --era or --target specified)
# ---------------------------------------------------------------------------
if [ -n "$ERA_FILTER" ] || [ -n "$TARGET_FILTER" ]; then
    echo "Phase 3: Real builds"
    echo "--------------------"
    _info "NOTE: This phase downloads sources and builds compilers."
    _info "      Requires internet access and may take 30+ minutes per target."
    echo ""

    CROSS_SRCDIR="${CROSS_SRCDIR:-/opt/cross-src}"
    CROSS_PREFIX="${CROSS_PREFIX:-/opt/cross}"
    CROSS_BUILDDIR="${CROSS_BUILDDIR:-/tmp/cross-build-test-$$}"
    export CROSS_SRCDIR CROSS_PREFIX CROSS_BUILDDIR

    _tc_file2=$(mktemp /tmp/test_casesXXXXXX)
    echo "$TEST_CASES" | grep -v '^$' > "$_tc_file2"
    while IFS='|' read era gcc_ver bu_ver plat plat_ver arch; do
        # Apply ERA_FILTER
        if [ -n "$ERA_FILTER" ] && [ "$ERA_FILTER" != "all" ]; then
            [ "$era" = "$ERA_FILTER" ] || continue
        fi

        _label="build: $era  gcc=$gcc_ver  $plat $plat_ver"
        _arch_flag=""
        [ -n "$arch" ] && _arch_flag="-a $arch"

        # Apply TARGET_FILTER if specified
        if [ -n "$TARGET_FILTER" ]; then
            # Quick dry run to get the target triple
            _triple=$(sh "$SCRIPT_DIR/build-cross.sh" -n -g "$gcc_ver" \
                $_arch_flag "$plat" "$plat_ver" 2>/dev/null | \
                grep 'Target' | head -1 | awk '{print $NF}')
            [ "$_triple" = "$TARGET_FILTER" ] || continue
        fi

        _real_build_test "$_label" \
            -g "$gcc_ver" -b "$bu_ver" $_arch_flag \
            "$plat" "$plat_ver" || true
    done < "$_tc_file2"
    rm -f "$_tc_file2"
    echo ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=============================="
echo "Test summary"
echo "=============================="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Skipped: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    printf "$FAILURES\n"
    echo ""
    exit 1
fi

echo "All tests passed."
