#!/bin/bash
#
# Installs (or updates) the Demo Launcher canvas so it's available in every
# GitHub Copilot session, plus the standalone Demo Launcher fallback service
# that runs alongside it
# (http://127.0.0.1:4747/), without rerunning the full setup.sh.
# Safe to re-run. See https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine
#
# Usage: bash install-demo-launcher.sh [--port N] [--no-service] [--uninstall]
#

# setup.sh only runs main when executed directly, so sourcing it just loads its helpers
# shellcheck source=setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup.sh"

usage() {
    echo "Usage: bash install-demo-launcher.sh [--port N] [--no-service] [--uninstall]"
    echo "  --port N      Port for the standalone Demo Launcher service (default: config.json, 4747)"
    echo "  --no-service  Only install the Copilot canvas, not the standalone fallback service"
    echo "  --uninstall   Remove the canvas loader and the standalone service"
}

# Removes the service and the canvas loader, whichever installers are present
demo_launcher_uninstall() {
    local installer service_installer found=false
    installer="$(demo_launcher_repo_dir)/.github/extensions/demo-launcher/install.sh"
    service_installer=$(demo_launcher_service_installer)

    if [[ -f "$service_installer" ]]; then
        found=true
        bash "$service_installer" --uninstall || exit 1
    fi
    if [[ -f "$installer" ]]; then
        found=true
        bash "$installer" --uninstall || exit 1
    fi
    if [[ "$found" != "true" ]]; then
        log_error "Demo Launcher installer not found at ${installer/#$HOME/~}"
        exit 1
    fi
    log_success "Demo Launcher removed. Restart the GitHub Copilot app to unload it."
}

demo_launcher_main() {
    local installer
    installer="$(demo_launcher_repo_dir)/.github/extensions/demo-launcher/install.sh"
    local uninstall=false port="" no_service=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall) uninstall=true; shift ;;
            --no-service) no_service=true; shift ;;
            --port)
                if [[ ! "${2:-}" =~ ^[0-9]+$ ]]; then
                    usage >&2; exit 2
                fi
                port="$2"; shift 2 ;;
            -h|--help) usage; return ;;
            *) usage >&2; exit 2 ;;
        esac
    done

    if [[ "$uninstall" == "true" ]]; then
        demo_launcher_uninstall
        return
    fi

    load_config
    [[ -n "$port" ]] && DEMO_LAUNCHER_SERVICE_PORT="$port"
    [[ "$no_service" == "true" ]] && DEMO_LAUNCHER_SERVICE_ENABLED=false

    check_demo_launcher_prereqs || exit 1
    # install_demo_launcher pulls an existing checkout; only clone here
    [[ -d "$(demo_launcher_repo_dir)/.git" ]] || sync_demo_launcher_repo

    # install.sh is idempotent, so always run it to refresh the loader
    FORCE_REINSTALL=true
    install_demo_launcher
    install_demo_launcher_service

    if [[ ! -f "$installer" ]]; then
        failed_items+=("Demo Launcher (install.sh not found in $DEMO_LAUNCHER_REPO)")
    fi

    print_summary
    if [[ ${#failed_items[@]} -gt 0 ]]; then
        exit 1
    fi

    log_success "Demo Launcher installed"
    log_info "Restart the GitHub Copilot app (or reload extensions), then ask Copilot to \"open the demo launcher\" in any session."
    if [[ "$DEMO_LAUNCHER_SERVICE_ENABLED" == "true" && -f "$(demo_launcher_service_installer)" ]]; then
        log_info "The standalone Demo Launcher fallback (alongside the canvas) is at http://127.0.0.1:$DEMO_LAUNCHER_SERVICE_PORT/ in any browser."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_launcher_main "$@"
fi
