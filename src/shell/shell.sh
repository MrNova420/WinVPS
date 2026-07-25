#!/usr/bin/env bash
# WinVPS Natural Language Shell (Linux/Ubuntu)
# Usage: winvps-shell [query]    (one-shot)
#        winvps-shell           (interactive REPL)

set -euo pipefail

WINVPS_DIR="${WINVPS_DIR:-$HOME/.winvps}"
SRC_DIR="$WINVPS_DIR/src"
VERSION="1.1.0"

CLI_SH="$SRC_DIR/cli/winvps.sh"
CLI_PS="$SRC_DIR/cli/winvps.ps1"
if [[ -f "$CLI_SH" ]]; then
    run_cli() { bash "$CLI_SH" "$@"; }
elif [[ -f "$CLI_PS" ]] && command -v pwsh &>/dev/null; then
    run_cli() { pwsh -NoProfile -ExecutionPolicy Bypass -File "$CLI_PS" "$@"; }
else
    run_cli() { echo "  x WinVPS CLI not found"; }
fi

R='\033[0m'; B='\033[1m'; D='\033[2m'
RD='\033[31m'; GN='\033[32m'; YL='\033[33m'
BL='\033[34m'; CY='\033[36m'

ALL_SERVICES="ssh web httpd supervisor healthcheck security fail2ban stealth obfuscate tamper wipe vpn-killswitch encrypt tor storage autoupdate lightweight tunnel telegram discord nginx apache node python java redis postgres mysql mongo mail ftp dns rdesktop wireguard tailscale"

find_service() {
    local text="$1"
    for svc in $ALL_SERVICES; do
        if echo "$text" | grep -qiw "$svc"; then echo "$svc"; return; fi
    done
    if echo "$text" | grep -qiwE '(web|dashboard|panel|ui)'; then echo "web"; return; fi
    if echo "$text" | grep -qiwE '(ssh|remote|terminal)'; then echo "ssh"; return; fi
    if echo "$text" | grep -qiwE '(tor|proxy|anon)'; then echo "tor"; return; fi
    if echo "$text" | grep -qiwE '(tunnel|ngrok|cloudflare)'; then echo "tunnel"; return; fi
    if echo "$text" | grep -qiw 'telegram'; then echo "telegram"; return; fi
    if echo "$text" | grep -qiw 'discord'; then echo "discord"; return; fi
    echo ""
}

parse_intent() {
    local text
    text=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 \-\/]//g' | sed 's/  */ /g' | xargs)
    INTENT_CMD=""; INTENT_ARGS=""; INTENT_DESC=""; INTENT_KIND="unknown"; INTENT_RAW="$1"
    local svc=""

    if [[ "$text" =~ ^(exit|quit|bye|close|leave|q)$ ]]; then INTENT_KIND="exit"; return; fi
    if [[ "$text" =~ ^(\?|help|tips|what\ can|commands) ]]; then INTENT_KIND="help"; return; fi
    if [[ "$text" =~ (what.*is.*winvps|about|describe) ]]; then INTENT_KIND="about"; return; fi
    if [[ "$text" =~ (status|how.*(server|system|doing|going|health)|overview|dashboard) ]]; then
        INTENT_CMD="status"; INTENT_DESC="Show system status (CPU, RAM, disk, uptime, services)"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (health.?check|diagnos|doctor|check.*health|is.*everything|all.*ok|healthy) ]]; then
        INTENT_CMD="doctor"; INTENT_DESC="Run full system diagnostics"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (monitor|watch|resource|live|real.?time|cpu.*usage|ram.*usage|performance) ]]; then
        INTENT_CMD="monitor"; INTENT_DESC="Live resource monitor"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (list.*service|service.*list|all.*service|what.*running|show.*service) ]]; then
        INTENT_CMD="service"; INTENT_ARGS="list"; INTENT_DESC="List all services"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (start|launch|run|spin.?up|boot|enable|activate|turn\ on) ]]; then
        svc=$(find_service "$text")
        if [[ -n "$svc" ]]; then INTENT_CMD="service"; INTENT_ARGS="start $svc"; INTENT_DESC="Start service: $svc"; INTENT_KIND="run"; return; fi
        INTENT_CMD="service"; INTENT_ARGS="list"; INTENT_DESC="Which service?"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (stop|kill|halt|shutdown|disable|deactivate|turn\ off|drop) ]]; then
        svc=$(find_service "$text")
        if [[ -n "$svc" ]]; then INTENT_CMD="service"; INTENT_ARGS="stop $svc"; INTENT_DESC="Stop service: $svc"; INTENT_KIND="run"; return; fi
        INTENT_CMD="service"; INTENT_ARGS="list"; INTENT_DESC="Which service?"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (restart|reboot|reload|refresh|recycle|bounce) ]]; then
        svc=$(find_service "$text")
        if [[ -n "$svc" ]]; then INTENT_CMD="service"; INTENT_ARGS="restart $svc"; INTENT_DESC="Restart service: $svc"; INTENT_KIND="run"; return; fi
        INTENT_CMD="service"; INTENT_ARGS="list"; INTENT_DESC="Which service?"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (log|logs|error|errors|what.*wrong|tail|recent) ]]; then
        svc=$(find_service "$text")
        if [[ -n "$svc" ]]; then INTENT_CMD="logs"; INTENT_ARGS="$svc 50"; INTENT_DESC="Last 50 lines of $svc logs"; INTENT_KIND="run"; return; fi
        INTENT_CMD="logs"; INTENT_DESC="List all log files"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (backup|back.?up|save|snapshot) ]]; then
        if [[ "$text" =~ (list|show|view) ]]; then INTENT_CMD="backup"; INTENT_ARGS="list"; INTENT_DESC="List all backups"; INTENT_KIND="run"; return; fi
        if [[ "$text" =~ (restore|recover) ]]; then INTENT_CMD="backup"; INTENT_ARGS="restore"; INTENT_DESC="Restore latest backup"; INTENT_KIND="confirm"; return; fi
        INTENT_CMD="backup"; INTENT_ARGS="create"; INTENT_DESC="Create timestamped backup"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (config|setting|configure) ]]; then
        INTENT_CMD="config"; INTENT_ARGS="show"; INTENT_DESC="Show configuration"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (security|secure|harden|firewall|protect|shield|lockdown) ]]; then
        if [[ "$text" =~ (scan|check|audit) ]]; then INTENT_CMD="security"; INTENT_ARGS="scan"; INTENT_DESC="Run security scan"; INTENT_KIND="run"; return; fi
        if [[ "$text" =~ (harden|fix|strengthen) ]]; then INTENT_CMD="security"; INTENT_ARGS="harden"; INTENT_DESC="Apply security hardening"; INTENT_KIND="confirm"; return; fi
        INTENT_CMD="security"; INTENT_ARGS="status"; INTENT_DESC="Security status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (fail2ban|brute|ban.*ip|intruder|attack) ]]; then
        if [[ "$text" =~ (start|enable|on) ]]; then INTENT_CMD="fail2ban"; INTENT_ARGS="start"; INTENT_DESC="Start fail2ban"; INTENT_KIND="run"; return; fi
        if [[ "$text" =~ (stop|disable|off) ]]; then INTENT_CMD="fail2ban"; INTENT_ARGS="stop"; INTENT_DESC="Stop fail2ban"; INTENT_KIND="run"; return; fi
        INTENT_CMD="fail2ban"; INTENT_ARGS="status"; INTENT_DESC="Fail2ban status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (stealth|invisible|hide|covert|incognito) ]]; then
        if [[ "$text" =~ (enable|on) ]]; then INTENT_CMD="stealth"; INTENT_ARGS="enable"; INTENT_DESC="Enable stealth mode"; INTENT_KIND="confirm"; return; fi
        if [[ "$text" =~ (disable|off) ]]; then INTENT_CMD="stealth"; INTENT_ARGS="disable"; INTENT_DESC="Disable stealth mode"; INTENT_KIND="run"; return; fi
        INTENT_CMD="stealth"; INTENT_ARGS="status"; INTENT_DESC="Stealth status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (encrypt|encryption|bitlocker|veracrypt) ]]; then
        if [[ "$text" =~ (init|setup|enable|mount) ]]; then INTENT_CMD="encrypt"; INTENT_ARGS="init"; INTENT_DESC="Initialize encrypted storage"; INTENT_KIND="confirm"; return; fi
        if [[ "$text" =~ (unmount|unlock|disable) ]]; then INTENT_CMD="encrypt"; INTENT_ARGS="unmount"; INTENT_DESC="Unmount volume"; INTENT_KIND="confirm"; return; fi
        INTENT_CMD="encrypt"; INTENT_ARGS="status"; INTENT_DESC="Encryption status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (tor|onion|hidden.?service|anonymous) ]]; then
        if [[ "$text" =~ (start|enable|on) ]]; then INTENT_CMD="tor"; INTENT_ARGS="start"; INTENT_DESC="Start Tor gateway"; INTENT_KIND="run"; return; fi
        if [[ "$text" =~ (stop|disable|off) ]]; then INTENT_CMD="tor"; INTENT_ARGS="stop"; INTENT_DESC="Stop Tor gateway"; INTENT_KIND="run"; return; fi
        INTENT_CMD="tor"; INTENT_ARGS="status"; INTENT_DESC="Tor status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (tunnel|expose|ngrok|cloudflare|bore|public.*url) ]]; then
        if [[ "$text" =~ (start|open|enable) ]]; then INTENT_CMD="tunnel"; INTENT_ARGS="start"; INTENT_DESC="Start tunnel"; INTENT_KIND="run"; return; fi
        if [[ "$text" =~ (stop|close|kill|disable) ]]; then INTENT_CMD="tunnel"; INTENT_ARGS="stop"; INTENT_DESC="Stop tunnel"; INTENT_KIND="run"; return; fi
        INTENT_CMD="tunnel"; INTENT_ARGS="status"; INTENT_DESC="Tunnel status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (tamper|integrity|dead.?man) ]]; then
        if [[ "$text" =~ (init|setup|enable) ]]; then INTENT_CMD="tamper"; INTENT_ARGS="init"; INTENT_DESC="Init tamper detection"; INTENT_KIND="confirm"; return; fi
        if [[ "$text" =~ (verify|check|test) ]]; then INTENT_CMD="tamper"; INTENT_ARGS="verify"; INTENT_DESC="Verify integrity"; INTENT_KIND="run"; return; fi
        INTENT_CMD="tamper"; INTENT_ARGS="status"; INTENT_DESC="Tamper status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (kill.?switch|vpn.*block|leak) ]]; then
        if [[ "$text" =~ (enable|on) ]]; then INTENT_CMD="killswitch"; INTENT_ARGS="enable"; INTENT_DESC="Enable VPN kill switch"; INTENT_KIND="confirm"; return; fi
        if [[ "$text" =~ (disable|off) ]]; then INTENT_CMD="killswitch"; INTENT_ARGS="disable"; INTENT_DESC="Disable kill switch"; INTENT_KIND="run"; return; fi
        INTENT_CMD="killswitch"; INTENT_ARGS="status"; INTENT_DESC="Kill switch status"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (obfuscat|randomiz|disguis|camouflage) ]]; then
        INTENT_CMD="obfuscate"; INTENT_ARGS="all"; INTENT_DESC="Randomize hostname, MAC, SSH keys"; INTENT_KIND="confirm"; return; fi
    if [[ "$text" =~ (tier|ram.*tier|memory.*class) ]]; then
        INTENT_CMD="tier"; INTENT_ARGS="info"; INTENT_DESC="RAM tier info"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (version|ver\b|what.*version) ]]; then
        INTENT_CMD="version"; INTENT_DESC="Show version"; INTENT_KIND="run"; return; fi
    if [[ "$text" =~ (uninstall|remove|delete.*winvps) ]]; then INTENT_KIND="uninstall"; return; fi
}

show_box() {
    local cmd="$1" desc="$2"
    local indent="  "
    local cmdLen=${#cmd}
    local boxW=$((cmdLen > 42 ? cmdLen + 4 : 46))
    echo ""
    echo -e "${indent}${D}+-- Suggested Command --$(printf '%*s' $((boxW - 42)) '' | tr ' ' '-')-+${R}"
    printf "${indent}${D}|${R}${B}${CY}  %-${boxW}s${R}${D}|${R}\n" "$cmd"
    if [[ -n "$desc" ]]; then
        printf "${indent}${D}|${R}  ${D}%-${boxW}s${R}${D}|${R}\n" "$desc"
    fi
    echo -e "${indent}${D}+$(printf '%*s' $((boxW + 2)) '' | tr ' ' '-')+${R}"
}

show_prompt() {
    echo ""
    echo -e "  ${B}Execute?${R} ${GN}[Y]${R}es  ${YL}[E]${R}dit  ${RD}[N]${R}o  ${D}[S]kip${R}"
}

show_examples() {
    echo ""
    echo -e "  ${B}${CY}Examples:${R}"
    echo -e "  ${D}Natural Language${R}              ${D}Translates to${R}"
    echo -e "  ${GN}how's my server doing${R}         ${B}winvps status${R}"
    echo -e "  ${GN}start the web server${R}          ${B}winvps service start web${R}"
    echo -e "  ${GN}stop ssh${R}                      ${B}winvps service stop ssh${R}"
    echo -e "  ${GN}restart the database${R}          ${B}winvps service restart postgres${R}"
    echo -e "  ${GN}show me recent errors${R}         ${B}winvps logs${R}"
    echo -e "  ${GN}run diagnostics${R}               ${B}winvps doctor${R}"
    echo -e "  ${GN}create a backup${R}               ${B}winvps backup create${R}"
    echo -e "  ${GN}open a tunnel${R}                 ${B}winvps tunnel start${R}"
    echo -e "  ${GN}harden the server${R}             ${B}winvps security harden${R}"
    echo -e "  ${GN}enable stealth mode${R}           ${B}winvps stealth enable${R}"
    echo -e "  ${GN}show all config${R}               ${B}winvps config show${R}"
    echo ""
}

show_about() {
    echo ""
    echo -e "  ${B}${CY}WinVPS v${VERSION}${R}"
    echo -e "  ${D}Turn any machine into a self-managed${R}"
    echo -e "  ${D}auto-healing, remotely accessible VPS.${R}"
    echo ""
    echo -e "  ${B}Features:${R}"
    echo "  Service supervisor | Web dashboard | Security hardening"
    echo "  Cloud tunnels | Tor gateway | Telegram & Discord bots"
    echo "  Encrypted storage | Tamper detection | Stealth mode"
    echo "  RAM tiering | Auto-updates | Backup system"
    echo ""
    echo -e "  ${D}https://github.com/MrNova420/WinVPS${R}"
    echo ""
}

banner() {
    echo ""
    echo -e "${CY}${B}      _    __        ______                __  ${R}"
    echo -e "${CY}${B}     | |  / /__     / ____/___  _________/ /__${R}"
    echo -e "${CY}${B}     | | / / _ \   / /   / __ \/ ___/ __  / _ \${R}"
    echo -e "${CY}${B}     | |/ /  __/  / /___/ /_/ / /  / /_/ /  __/${R}"
    echo -e "${CY}${B}     |___/\___/   \____/\____/_/   \__,_/\___/ ${R}"
    echo -e "${D}       v${VERSION}  -  Natural Language Shell${R}"
    echo ""
    echo -e "${D}  Describe a command in plain English and I'll translate it.${R}"
    echo -e "${D}  Type ${YL}?${D} for examples.  ${YL}exit${D} to quit.${R}"
    echo ""
}

dispatch() {
    case "$INTENT_KIND" in
        exit) echo -e "\n  ${CY}See you!${R}\n"; return 1 ;;
        help) show_examples ;;
        about) show_about ;;
        uninstall) echo -e "\n  ${YL}!${R} Use: ${B}winvps uninstall${R}\n" ;;
        unknown)
            echo -e "\n  ${YL}?${R} I didn't understand that. Type ${YL}?${R} for examples.\n" ;;
        run|confirm)
            local full_cmd="winvps $INTENT_CMD $INTENT_ARGS"
            full_cmd=$(echo "$full_cmd" | xargs)
            show_box "$full_cmd" "$INTENT_DESC"
            show_prompt
            local response
            read -rp '  > ' response
            response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
            case "$response" in
                y|yes|"")
                    echo -e "  ${GN}>${R} Running..."
                    echo ""
                    run_cli $INTENT_CMD $INTENT_ARGS
                    echo "" ;;
                e*)
                    echo -e "  ${D}Edit the command:${R}"
                    read -rp '  winvps ' edited
                    if [[ -n "$edited" ]]; then
                        echo -e "  ${GN}>${R} Running: winvps $edited"
                        echo ""
                        run_cli $edited
                        echo ""
                    fi ;;
                *) echo -e "  ${D}Cancelled.${R}\n" ;;
            esac ;;
    esac
}

if [[ $# -gt 0 ]]; then
    parse_intent "$*"
    dispatch
else
    banner
    while true; do
        echo -ne "${CY}${B}  you>${R} "
        read -r input || break
        [[ -z "$input" ]] && continue
        parse_intent "$input"
        dispatch || break
    done
fi
