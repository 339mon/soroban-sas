#!/usr/bin/env bash
#
# scripts/bootstrap.sh — check or install toolchain dependencies for soroban-sas.
#
# Default (no flags): report the current state of Rust, the wasm32 target, and
# the Stellar CLI. Does not modify the machine.
#
# --install: install pinned versions of anything missing or out of date.
#            Running twice in a row performs no work the second time.
#
# --check:   exit non-zero with a diagnostic if any tool is missing or the
#            wrong version. Intended for CI.
#
# Usage:
#   ./scripts/bootstrap.sh              # report only
#   ./scripts/bootstrap.sh --install    # install/upgrade as needed
#   ./scripts/bootstrap.sh --check      # assert versions, exit 1 on mismatch
#
set -euo pipefail

readonly RUST_TARGET="wasm32-unknown-unknown"
readonly STELLAR_CLI_VERSION="${STELLAR_CLI_VERSION:-28.0.0}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: ./scripts/bootstrap.sh [--install | --check] [-h|--help]

Modes (mutually exclusive, default is report-only):
  (no flag)    Print current toolchain state. Does not modify the machine.
  --install    Install the missing ${RUST_TARGET} target and Stellar CLI
               v${STELLAR_CLI_VERSION}. Idempotent — skips anything already
               installed at a compatible version.
  --check      Exit non-zero if any required tool is missing or at the
               wrong version. Intended for CI.

Other:
  -h, --help   Show this help.

Environment overrides:
  STELLAR_CLI_VERSION   Pin a different CLI version (default: ${STELLAR_CLI_VERSION})
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE="report"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) MODE="install"; shift ;;
        --check)   MODE="check";   shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Find the Stellar CLI. Prefers the current name `stellar` (v23+); falls back
# to the legacy `soroban` binary for older installs.
find_cli() {
    local candidate
    for candidate in stellar soroban; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Extract a semver triple from arbitrary CLI --version output, e.g.
#   "stellar 22.0.1 (abc123)"        -> 22.0.1
#   "soroban-cli 21.3.0"             -> 21.3.0
#   "stellar-cli 28.0.0-rc.1"        -> 28.0.0
cli_version() {
    local bin="$1" out
    out="$("$bin" --version 2>/dev/null || true)"
    printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
}

# ---------------------------------------------------------------------------
# Rust / Cargo
# ---------------------------------------------------------------------------
step "Checking Rust & Cargo"
RUST_OK=false
if command -v rustup >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
    info "rustup: $(command -v rustup)"
    info "cargo:  $(command -v cargo) ($(cargo --version 2>/dev/null | awk '{print $2}'))"
    RUST_OK=true
else
    if [[ "$MODE" == "check" ]]; then
        die "rustup and/or cargo not found. Install Rust via https://rustup.rs"
    fi
    warn "rustup and/or cargo not found — install Rust via https://rustup.rs"
fi

# ---------------------------------------------------------------------------
# wasm32-unknown-unknown target
# ---------------------------------------------------------------------------
step "Checking ${RUST_TARGET} target"
TARGET_OK=false
if [[ "$RUST_OK" == true ]] && rustup target list --installed 2>/dev/null | grep -qx "$RUST_TARGET"; then
    info "${RUST_TARGET} target is installed"
    TARGET_OK=true
else
    if [[ "$MODE" == "install" ]]; then
        info "installing ${RUST_TARGET} target"
        rustup target add "$RUST_TARGET"
        TARGET_OK=true
    elif [[ "$MODE" == "check" ]]; then
        die "${RUST_TARGET} target is not installed. Run: ./scripts/bootstrap.sh --install"
    else
        warn "${RUST_TARGET} target is NOT installed"
    fi
fi

# ---------------------------------------------------------------------------
# Stellar CLI
# ---------------------------------------------------------------------------
step "Checking Stellar CLI (want v${STELLAR_CLI_VERSION})"
CLI_BIN=""
CLI_VERSION=""
CLI_OK=false

if CLI_BIN="$(find_cli)"; then
    CLI_VERSION="$(cli_version "$CLI_BIN")"
    if [[ -z "$CLI_VERSION" ]]; then
        warn "found '$CLI_BIN' at $(command -v "$CLI_BIN") but could not parse its version"
    elif [[ "$CLI_VERSION" == "$STELLAR_CLI_VERSION" ]]; then
        info "found '$CLI_BIN' v${CLI_VERSION} — matches required version"
        CLI_OK=true
    else
        info "found '$CLI_BIN' v${CLI_VERSION} — required v${STELLAR_CLI_VERSION}"
    fi
else
    info "no 'stellar' or 'soroban' binary on PATH"
fi

if [[ "$CLI_OK" != true ]]; then
    case "$MODE" in
        install)
            info "installing stellar-cli v${STELLAR_CLI_VERSION} (this may take a few minutes)"
            cargo install --locked stellar-cli --version "$STELLAR_CLI_VERSION" --force
            info "stellar-cli v${STELLAR_CLI_VERSION} installed"
            CLI_OK=true
            ;;
        check)
            if [[ -z "$CLI_BIN" ]]; then
                die "no Stellar CLI on PATH. Run: ./scripts/bootstrap.sh --install"
            fi
            if [[ -z "$CLI_VERSION" ]]; then
                die "found '$CLI_BIN' but could not determine version. Reinstall via: cargo install --locked stellar-cli --version ${STELLAR_CLI_VERSION} --force"
            fi
            die "Stellar CLI version mismatch: found v${CLI_VERSION}, want v${STELLAR_CLI_VERSION}. Run: cargo install --locked stellar-cli --version ${STELLAR_CLI_VERSION} --force"
            ;;
        report)
            warn "Stellar CLI v${STELLAR_CLI_VERSION} is required. Run: ./scripts/bootstrap.sh --install"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
case "$MODE" in
    report)
        step "Report complete (no changes made)"
        printf '  %-14s %s\n' "rustup:"  "$([[ "$RUST_OK" == true ]] && echo OK || echo MISSING)"
        printf '  %-14s %s\n' "target:"  "$([[ "$TARGET_OK" == true ]] && echo OK || echo MISSING) (${RUST_TARGET})"
        printf '  %-14s %s\n' "stellar:" "$([[ "$CLI_OK" == true ]] && echo "OK (v${CLI_VERSION})" || echo "NEEDS INSTALL (want v${STELLAR_CLI_VERSION})")"
        printf '\nRun with --install to fix missing items.\n'
        ;;
    install)
        step "Environment bootstrap complete"
        printf '  %-14s %s\n' "rustup:"  "OK"
        printf '  %-14s %s\n' "target:"  "OK (${RUST_TARGET})"
        printf '  %-14s %s\n' "stellar:" "OK (v${STELLAR_CLI_VERSION})"
        ;;
    check)
        step "All required toolchain components present"
        printf '  %-14s %s\n' "rustup:"  "OK"
        printf '  %-14s %s\n' "target:"  "OK (${RUST_TARGET})"
        printf '  %-14s %s\n' "stellar:" "OK (v${CLI_VERSION})"
        ;;
esac