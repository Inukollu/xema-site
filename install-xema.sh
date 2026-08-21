#!/bin/bash

# Where this script's own files live.
#
# They used to be fetched one at a time from github.com/xema-in/install, which made an install
# depend on a second repository being reachable and in step with this one — a unit file could be
# newer than the binaries it started, and nothing would say so. They travel with the script now, and
# where the binaries themselves are hosted is a separate decision that has not been taken.

# https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux
# https://stackoverflow.com/questions/17336915/return-value-in-a-bash-function
# https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html#index-FUNCNAME
# https://www.redhat.com/sysadmin/arguments-options-bash-scripts


# This script installs binaries. That is the whole of its job.
#
# It used to decide things as well: -r said what the server was for, it created a MariaDB user with
# a known password, and it seeded every service's settings from a release's defaults. All three
# were decisions taken by whoever happened to run an install, at the one moment nobody knew yet
# what the machine was for — and the settings seeding was worse than useless, because a per-service
# file holding a copy of the defaults silently overrode the wiring the cluster later worked out.
#
# So the machine gets the software, and an administrator says what it is for afterwards, with the
# `xema` command. What that involves is not spelled out here: this file is fetched over the public
# internet, so it describes what it installs and not how a site is put together.
#
# Two exceptions, and neither is a role.
#
# `host` is the node agent: it applies what an administrator decided — the network plan, the clock,
# the units, the realms — and it is what makes a machine into a node. It goes on before anything
# else has an opinion, and nothing can turn it off, because there would be nothing left to turn it
# back on.
#
# `manager` serves the console those decisions are made in. It administers; it does not apply.
#
# Everything else waits to be asked for.
#
# The role names are deliberately not listed here. Nothing in this script reads them — they were
# only ever printed in the closing message — and a list of what a site runs is not something to
# publish in a file fetched over the public internet.

# Where things live on a server.
#
# Program code, configuration and state have three different lifetimes: code is replaced
# wholesale on upgrade, configuration is edited by the administrator, state is written by the
# service. Keeping them apart is what stops an upgrade destroying settings, and lets a service
# run without write access to its own binaries. FHS puts vendor code under /opt, configuration
# under /etc and state under /var/lib.
XEMA_INSTALL_DIR="/opt/techsudoku/xema"
XEMA_CONFIG_DIR="/etc/xema"
XEMA_STATE_DIR="/var/lib/xema"

# The layout before this change: everything, including configuration, in one directory.
XEMA_LEGACY_DIR="/var/lib/xema"

# Define the support matrix in a central place
function define_support_matrix() {
    # Define arrays for each configuration
    # Format: distro|hostsys|kernel|version|installable|supported|details
    SUPPORT_MATRIX=(
        "Ubuntu|Linux|Linux|20|no|no"
        "Ubuntu|Linux|Linux|22|yes|yes"
        "Ubuntu|Linux|Linux|24|yes|no"
        "Ubuntu|Linux|Linux|25|yes|no"
        "Ubuntu|Linux|Linux|26|yes|no"
        "CentOS|Linux|Linux|4|no|no"
        "Ubuntu|WSL|Linux|25|yes|no"
    )
}

function set_colors() {
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    reset=$(tput sgr0)
}

function dep() {
    i=$depth
    while [[ $i -gt 0 ]]; do
        echo -n "  "
        let "i-=1"
    done
    echo -n ""
}

function lineno1() {
    lineno="...........1."${BASH_LINENO[1]}
    echo -n ${lineno:(-5)}
}

function lineno2() {
    # space is not working, so, using . to pad
    lineno="...........2."${BASH_LINENO[2]}
    echo -n ${lineno:(-5)}
}

function lineno3() {
    lineno="...........3."${BASH_LINENO[3]}
    echo -n ${lineno:(-5)}
}

function header() {
    logger+=$(lineno1)".H.: "$(dep)${FUNCNAME[1]}$'()\n'
    let "depth++"
}

function footer() {
    let "depth--"
    logger+=$(lineno1)".F.: "$(dep)${FUNCNAME[1]}"() completed. "$1$'\n'
}

log() {
    logger+=$(lineno1)".L.: "$(dep)$1$'\n'
    # echo "DEBUG: $1"
}

# variable: $hostsys $kernel
function detect_host() {
    header

    unameOut="$(uname -sro)"
    log "uname -sro: ""${green}$unameOut${reset}"

    case "${unameOut}" in
    Darwin*) hostsys="Mac" ;;
    Linux*Microsoft* | Linux*microsoft*) hostsys="WSL" ;;
    Linux*) hostsys="Linux" ;;
    CYGWIN* | MINGW*) hostsys="Windows" ;;
    *) hostsys="Unknown" ;;
    esac

    case "${unameOut}" in
    Darwin*) kernel="OS X" ;;
    Linux*) kernel="Linux" ;;
    CYGWIN* | MINGW*) kernel="Windows" ;;
    *) kernel="Unknown" ;;
    esac

    footer hostsys="$hostsys",kernel="$kernel"
}

# variable $oever
function detect_ubuntu_version() {
    header

    lsbOut="$(lsb_release -rs)"
    log "lsb_release -rs: ""${green}$lsbOut${reset}"

    case "${lsbOut}" in
    18.*) oever="18" ;;
    20.*) oever="20" ;;
    22.*) oever="22" ;;
    24.*) oever="24" ;;
    25.*) oever="25" ;;
    26.*) oever="26" ;;
    # 24.*) oever="24" ;;
    *) oever="Unknown" ;;
    esac

    footer oever="$oever"
}

# variable $oever
function detect_centos_version() {
    header

    log "${red}Not implemented${reset}"

    footer
}

# variable $distro
function detect_distro() {
    header

    if [[ $(lsb_release -is) = *Ubuntu* ]]; then
        log "lsb_release -is: "${green}$(lsb_release -is)${reset}
        distro="Ubuntu"
        detect_ubuntu_version
    elif [[ $(cat /etc/os-release | grep "^NAME=") = *CentOS* ]]; then
        distro="CentOS"
        detect_centos_version
    else
        distro="Unknown"
    fi

    footer distro="$distro"
}

# variable $supported, $installable
function check_support_matrix() {
    header
    supported="no"
    installable="no"

    log "${red}$hostsys $kernel $distro $oever${reset}"

    # Call the common function to define the support matrix
    define_support_matrix

    # Check the current configuration against the matrix
    for config in "${SUPPORT_MATRIX[@]}"; do
        # More compatible way to split the string
        OLD_IFS="$IFS"
        IFS="|"
        set -- $config
        conf_distro="$1"
        conf_hostsys="$2"
        conf_kernel="$3"
        conf_version="$4"
        conf_installable="$5"
        conf_supported="$6"
        IFS="$OLD_IFS"
        
        if [[ $distro == "$conf_distro" && $hostsys == "$conf_hostsys" && $kernel == "$conf_kernel" && $oever == "$conf_version" ]]; then
            installable="$conf_installable"
            supported="$conf_supported"
            break
        fi
    done

    footer installable="$installable",supported="$supported"
}

function print_support_matrix() {
    header

    # Call the common function to define the support matrix
    define_support_matrix

    # Table header
    printf "+------------------+----------+----------+----------+\n"
    printf "| %-16s | %-8s | %-8s | %-8s |\n" "Environment" "Version" "Install" "Support"
    printf "+------------------+----------+----------+----------+\n"
    
    # Loop through the support matrix to print each configuration
    for config in "${SUPPORT_MATRIX[@]}"; do
        # More compatible way to split the string
        OLD_IFS="$IFS"
        IFS="|"
        set -- $config
        conf_distro="$1"
        conf_hostsys="$2"
        conf_kernel="$3"
        conf_version="$4"
        conf_installable="$5"
        conf_supported="$6"
        IFS="$OLD_IFS"
                
        # Format the install and support status with fixed column width
        if [[ $conf_installable == "yes" ]]; then
            install_mark="   ${green}✅${reset}   "
        else
            install_mark="   ${red}❌${reset}   "
        fi
        
        if [[ $conf_supported == "yes" ]]; then
            support_mark="   ${green}✅${reset}   "
        else
            support_mark="   ${red}❌${reset}   "
        fi
        
        # Print the row with fixed column widths
        printf "| %-16s | %-8s | %-8s | %-8s |\n" "$conf_distro ($conf_hostsys)" "$conf_version" "$install_mark" "$support_mark"
    done
    
    # Footer line
    printf "+------------------+----------+----------+----------+\n"

    footer
}

# Install one Xema component.
#
# Every component goes on every server. A role decides what a machine *runs*, not what it has:
# `xema node apply` can only switch on something that is already there, and a server given a role
# it has no binaries for fails in a way that looks like a broken role rather than a missing
# install.
#
# The work is the CLI's — `xema component install` fetches the release, unpacks it under /opt,
# makes the state directory and installs the unit. This is the only caller that passes --force,
# because re-running the installer is how an upgrade is done and an upgrade must replace the code
# that is there.
function install_component() {
    local role="$1"
    local label="$2"
    local component="$3"

    # Releases are built for Ubuntu, and the CLI is only put on Ubuntu. The old code returned
    # quietly here too; keeping that, rather than failing on a distro nothing supports yet.
    if [ "$distro" != "Ubuntu" ]; then
        log "skipping $role: $distro is not supported"
        return 0
    fi

    log "-> xema component install $component"
    echo "${green}Installing $label ...${reset}"

    if ! xema_cli component install "$component" --channel "$channel" --force; then
        echo "${red}$LINENO: could not install $label${reset}"
        return 1
    fi
}

# The CLI, wherever it ended up. PATH is not reliable inside a script that has just installed it.
function xema_cli() {
    if [ -x /usr/local/bin/xema ]; then
        /usr/local/bin/xema "$@"
    else
        echo "${red}the xema CLI is not installed; cannot install components${reset}"
        return 1
    fi
}

function install_tools_and_binaries() {
    header
    installed="no"

    log "-> xema_capable_operating_environment"
    xema_capable_operating_environment

    if [[ $installable == "yes" ]]; then
        log "-> install_tools"
        echo "${green}Installing tools ...${reset}"
        install_tools

        log "-> install_dependencies"
        echo "${green}Installing dependencies ...${reset}"
        install_dependencies

        log "-> migrate_xema_layout"
        echo "${green}Checking filesystem layout ...${reset}"
        migrate_xema_layout

        # The CLI comes first, because everything below is installed *by* it.
        #
        # This script's job is the part the CLI cannot do for itself: apt, .NET, nginx, the
        # infrastructure, and the layout. Once those are on the machine, putting a Xema component
        # in place is a zip into /opt and a unit file — and that is `xema component install`,
        # which an operator and the admin UI can also reach. One implementation of it, rather
        # than one here and a second one there drifting apart.
        log "-> install_xema_cli"
        echo "${green}Installing Xema CLI ...${reset}"
        install_xema_cli

        # Each component only where it is wanted. Manager is below, and always.
        install_component fastagi     "Xema FastAGI"        fastagi
        install_component astermq     "Xema AsterMQ"        astermq
        # Fastlane goes wherever AsterMQ goes: AsterMQ carries Asterisk's events out, Fastlane
        # takes actions in. A node with one and not the other is half-connected.
        install_component fastlane    "Xema Fastlane"       fastlane
        install_component simplecdr   "Xema SimpleCdr"      simplecdr
        install_component bff         "Xema BFF"            bff
        install_component queue       "Xema Queue"          queue
        install_component dialer      "Xema Dialer"         dialer
        install_component tracer      "Xema Tracer"         tracer
        install_component sipper      "Xema Sipper"         sipper
        install_component ava         "Xema Ava"            ava
        install_component metrics     "Xema Metrics"        metrics

        # Tools rather than services: they are run by hand when needed, and are small. Not
        # components — they have no unit and nothing starts them — so they stay here.
        log "-> install_xema_missingcdrs"
        echo "${green}Installing Xema MissingCdrs ...${reset}"
        install_xema_missingcdrs

        log "-> install_xema_metricsbackfill"
        echo "${green}Installing Xema Metrics Backfill ...${reset}"
        install_xema_metricsbackfill

        log "-> install_xema_binary"
        echo "${green}Installing Xema Manager ...${reset}"
        install_xema_binary

        installed="yes"
    fi

    footer installed="$installed"
}

function xema_capable_operating_environment() {
    header

    log "-> detect_host"
    detect_host
    if [[ ! $kernel = *Linux* ]]; then
        echo "${red}$kernel Environment is not supported.${reset}"
    else
        log "-> detect_distro and version"
        detect_distro
        # detect_distro also calls version detection
        if [[ ! $distro = *Ubuntu* ]]; then
            echo "${red}$distro Linux Distribution is not supported.${reset}"
        else
            log "-> check_support_matrix"
            check_support_matrix

            if [[ $installable == "yes" && $supported == "no" ]]; then
                log "-> print_support_matrix"
                print_support_matrix
                echo "${red}Unsupported configuration.${reset} $hostsys $kernel $distro $oever"
                echo "${red}!!! Install at your own risk !!! ${reset}"
            elif [[ $installable == "no" ]]; then
                echo "${red}!!! Unable to install !!! ${reset}"
                echo "${red}Unsupported configuration.${reset} $hostsys $kernel $distro $oever"
            fi

            if [[ $installable == "yes" ]]; then
                # echo "${green}"
                echo -e "Distro:  " $distro
                echo -e "Version: " $oever
                if [[ $supported == "yes" ]]; then echo -e "Support:  ${green}✅${reset}"; fi
                if [[ $supported == "no" ]]; then echo -e "Support:  ${red}❌${reset}"; fi
                # echo "${reset}"
            fi
        fi
    fi

    footer
}

function install_tools() {
    header

    if [ "$distro" == "Ubuntu" ]; then
        apt $apt_quiet update
        apt $apt_quiet install -y curl wget unzip at sngrep libpcap0.8
        # apt $apt_quiet install -y git sipsak linphone-cli
    fi

    if [ "$distro" == "CentOS" ]; then
        echo "${red}$LINENO: Not implemented${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function install_dependencies() {
    header

    if [ "$distro" == "Ubuntu" ]; then
        ubuntu_dependencies
        ubuntu_dotnet
    fi

    if [ "$distro" == "CentOS" ]; then
        centos_dependencies
        centos_dotnet
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

# ubuntu dependencies
function ubuntu_dependencies() {
    header

    # nginx serves the admin pages for Manager, which runs everywhere, so it is not a role.
    which nginx >/dev/null
    if [ "$?" -ne "0" ]; then
        apt $apt_quiet install -y nginx
        systemctl start nginx
    fi

    which prometheus >/dev/null
    if [ "$?" -ne "0" ]; then
        apt $apt_quiet install -y prometheus
        systemctl start prometheus
    fi

    # The infrastructure a single server needs to be a whole call centre. Installed on every box
    # because that is what makes the ordinary deployment work out of the box; which of them a
    # *site* actually uses is a role, recorded later, and a daemon nobody's site points at simply
    # sits there.
    which asterisk >/dev/null
    if [ "$?" -ne "0" ]; then
        apt $apt_quiet install -y asterisk
        systemctl start asterisk
    fi

    which rabbitmq-server >/dev/null
    if [ "$?" -ne "0" ]; then
        apt $apt_quiet install -y rabbitmq-server
        systemctl start rabbitmq-server
    fi

    which redis-server >/dev/null
    if [ "$?" -ne "0" ]; then
        apt $apt_quiet install -y redis-server
        systemctl start redis-server
    fi

    install_mariadb="no"

    which mysql >/dev/null
    if [ "$?" -ne "0" ]; then
        install_mariadb="yes"
    fi

    mysql -e "show databases" >/dev/null
    if [ "$?" -ne "0" ]; then
        install_mariadb="yes"
    fi

    if [ "$install_mariadb" == "yes" ]; then
        apt $apt_quiet install -y mariadb-server
        systemctl start mariadb
    fi

    footer
}

function centos_dependencies() {
    header

    echo "${red}$LINENO: Not implemented${reset}"

    footer
}

# centos dotnet
function centos_dotnet() {
    header

    echo "${red}$LINENO: Not implemented${reset}"

    footer
}

# SIP realms: the templated unit that runs one SIP proxy per carrier, each inside that
# carrier's own network namespace.
#
# NOT WIRED UP. Nothing calls this yet and the kamailio package is not installed by default.
# Add the call to install_tools_and_binaries once realms are ready to ship.
function install_kamailio_realms() {
    header

    if [ "$distro" == "Ubuntu" ]; then
        mkdir -p /etc/kamailio/realms

        # The kamailio-realm@ template is carried by the CLI and placed by `xema node files`.
    fi

    footer
}

function xema_release_tag() {
    if [ "$channel" == "dev" ]; then
        echo "dev"
    else
        echo "v2.0"
    fi
}

# Fetch a release zip and unpack it under the install dir.
#
# Only the two tools use this now — MissingCdrs and MetricsBackfill, which have no unit and
# nothing starts them, so they are not components and the CLI does not manage them. Every real
# component goes through `xema component install`, which does this and the unit besides.
function install_xema_tool() {
    local dir="$1"
    local zip="$2"
    local tag
    tag=$(xema_release_tag)

    if [ "$distro" != "Ubuntu" ]; then
        return 0
    fi

    mkdir -p "$XEMA_INSTALL_DIR/$dir"
    rm -rf "/tmp/$zip"

    wget -q --show-progress "https://github.com/inukollu/xema-site/releases/download/$tag/$zip" -O "/tmp/$zip"
    unzip -qo "/tmp/$zip" -d "$XEMA_INSTALL_DIR/$dir"

    # Nothing is seeded into /etc/xema. A release's appsettings.json ships beside the code and is
    # read as the defaults it is; copying it into /etc/xema turned every default into an explicit
    # override, and an override beats the settings a cluster derives — by design. That is how
    # seven of one server's eight services ended up pinned to localhost with no symptom.
    #
    # /etc/xema holds what somebody decided: `xema connect-database` writes the database, joining a
    # site writes the site's, and an administrator's own file beats both.
    mkdir -p "$XEMA_CONFIG_DIR"

    # State is the service's to write, and is the one thing that stays in /var/lib.
    mkdir -p "$XEMA_STATE_DIR/$dir"
}

function install_xema_missingcdrs() {
    header
    install_xema_tool "import" "MissingCdrs.zip"
    footer
}

function install_xema_metricsbackfill() {
    header
    install_xema_tool "backfill" "MetricsBackfill.zip"
    footer
}

function install_xema_cli() {
    header

    rm -rf /tmp/cli.zip

    if [ "$channel" == "dev" ]; then
        release_tag="dev"
    else
        release_tag="v2.0"
    fi

    if [ "$distro" == "Ubuntu" ]; then
        wget -q --show-progress https://github.com/inukollu/xema-site/releases/download/$release_tag/Cli.zip -O /tmp/cli.zip
        unzip -qo /tmp/cli.zip -d /usr/local/bin
        chmod +x /usr/local/bin/xema
        /usr/local/bin/xema completion bash > /etc/bash_completion.d/xema
    fi

    footer
}

# Move a server laid out the old way — everything in /var/lib/xema — onto the split layout.
#
# Deliberately conservative: it copies configuration out and leaves the old tree entirely alone.
# A migration that both relocates everything and deletes the original has no way back when it is
# wrong, and this one runs unattended on live call centres. The old directory simply stops being
# used; a later release removes it once this has proven itself.
#
# Safe to run repeatedly: it never overwrites a file that already exists at the destination.
function migrate_xema_layout() {
    header

    mkdir -p "$XEMA_CONFIG_DIR" "$XEMA_INSTALL_DIR" "$XEMA_STATE_DIR"

    if [ ! -d "$XEMA_LEGACY_DIR" ]; then
        footer "nothing to migrate"
        return 0
    fi

    # Configuration is the only thing here that cannot simply be downloaded again, so it moves
    # first and is never clobbered.
    local dir
    for dir in manager fastagi astermq fastlane simplecdr bff queue dialer tracer sipper import ava metrics backfill; do
        if [ -f "$XEMA_LEGACY_DIR/$dir/appsettings.json" ] && [ ! -f "$XEMA_CONFIG_DIR/$dir.json" ]; then
            cp "$XEMA_LEGACY_DIR/$dir/appsettings.json" "$XEMA_CONFIG_DIR/$dir.json"
            log "migrated settings: $dir"
        fi
    done

    # State stays exactly where it is. /var/lib is already the right place for it, so
    # simplecdr/state, network/, and the database dumps at the root of /var/lib/xema are
    # untouched by any of this.

    # Prune the unbounded pile of dated Manager copies the old backup step left behind.
    local old
    for old in "$XEMA_LEGACY_DIR"/manager.[0-9]*; do
        [ -d "$old" ] || continue
        rm -rf "$old"
        log "removed stale backup: $old"
    done

    footer
}

function install_xema_binary() {
    header

    backup_existing_installation

    if [ "$channel" == "release" ]; then
        log "-> install_xema_prod_channel"
        install_xema_prod_channel
    fi

    if [ "$channel" == "dev" ]; then
        log "-> install_xema_dev_channel"
        install_xema_dev_channel
    fi

    add_default_settings

    footer
}

function backup_existing_installation() {
    header

    # One previous copy, beside the current one, so a bad upgrade can be stepped back.
    #
    # This used to copy the whole tree into /var/lib/xema/manager.<date> on every run and never
    # remove any of them — 1.4 GB of dead Manager trees had accumulated on one box. A backup
    # nobody prunes is a disk-full waiting to happen, and the state directory is the wrong place
    # for program code besides.
    if [ -d "$XEMA_INSTALL_DIR/manager" ]; then
        rm -rf "$XEMA_INSTALL_DIR/manager.previous"
        cp -a "$XEMA_INSTALL_DIR/manager" "$XEMA_INSTALL_DIR/manager.previous"
    fi

    rm -rf /tmp/manager.zip

    footer
}

# https://github.com/inukollu/xema-site/releases/download/v2.0/Manager.zip
function install_xema_prod_channel() {
    header

    echo "Installing from ${green}$channel${reset} channel ..."

    if [ "$distro" == "Ubuntu" ]; then
        mkdir -p "$XEMA_INSTALL_DIR/manager"
        wget -q --show-progress https://github.com/inukollu/xema-site/releases/download/v2.0/Manager.zip -O /tmp/manager.zip
        unzip -qo /tmp/manager.zip -d "$XEMA_INSTALL_DIR/manager"
    fi

    if [ "$distro" != "Ubuntu" ]; then
        echo "${red}$LINENO: $distro not implemented${reset}"
    fi

    footer
}

# https://github.com/inukollu/xema-site/releases/download/dev/Manager.zip
function install_xema_dev_channel() {
    header

    echo "Installing from ${green}$channel${reset} channel ..."

    if [ "$distro" == "Ubuntu" ]; then
        mkdir -p "$XEMA_INSTALL_DIR/manager"
        wget -q --show-progress https://github.com/inukollu/xema-site/releases/download/dev/Manager.zip -O /tmp/manager.zip
        unzip -qo /tmp/manager.zip -d "$XEMA_INSTALL_DIR/manager"
    fi

    if [ "$distro" != "Ubuntu" ]; then
        echo "${red}$LINENO: $distro not implemented${reset}"
    fi

    footer
}

function add_default_settings() {
    header

    # Deliberately adds no settings. The name is kept because the call sites read well, but a
    # release's defaults stay with the release: seeding them into /etc/xema made every default an
    # explicit override of the wiring a cluster derives. /etc/xema is for decisions, and on a fresh
    # box the first one is `xema connect-database`.
    mkdir -p "$XEMA_CONFIG_DIR"
    mkdir -p "$XEMA_STATE_DIR/manager"

    footer
}

# variable $configured
# Ask the CLI to place the files it carries. It is installed before this runs, and it is the one
# thing that knows which of them this machine has a use for.
function configure_node_files() {
    header

    if [ -x /usr/local/bin/xema ]; then
        /usr/local/bin/xema node files
    else
        echo "${red}$LINENO: xema is not installed, so its files were not placed${reset}"
    fi

    footer
}

function configure_components() {
    header
    configured="no"

    if [[ $installed == "yes" ]]; then

        log "-> configure_firewall"
        configure_firewall

        # Everything a node needs that is not a binary: the units, the nginx site, the log
        # rotation, the Prometheus scrape, the syslog rule. The CLI carries them all and is already
        # installed by this point, so it writes them rather than this script fetching them.
        log "-> configure_node_files"
        configure_node_files

        log "-> configure_nginx"
        configure_nginx

        log "-> configure_asterisk"
        configure_asterisk

        log "-> configure_mysql"
        configure_mysql

        log "-> configure_logrotate"
        configure_logrotate

        log "-> configure_prometheus"
        configure_prometheus

        log "-> configure_xema_service"
        configure_xema_service

        log "-> configure_admin_access"
        configure_admin_access

        configured="yes"
    fi

    footer configured="$configured"
}

function configure_firewall() {
    header

    # Ubuntu: ufw
    # CentOS: firewalld

    if [ "$distro" == "Ubuntu" ]; then
        ufw disable
    fi

    if [ "$distro" == "CentOS" ]; then
        systemctl stop firewalld
        systemctl disable firewalld
        systemctl mask --now firewalld
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function configure_nginx() {
    header

    generate_self_signed_ssl

    if [ "$distro" == "Ubuntu" ]; then

        # The site is placed, enabled and reloaded by `xema node files`, which carries it and
        # will not reload nginx over a configuration nginx itself rejects.

        ls /etc/nginx/sites-enabled/default
        if [ "$?" -eq "0" ]; then
            rm /etc/nginx/sites-enabled/default
        fi

        nginx -s reload

    fi

    if [ "$distro" == "CentOS" ]; then
        # Not implemented. On Ubuntu the site is placed by `xema node files`.
        echo "${red}$LINENO: Not implemented${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function generate_self_signed_ssl() {
    header

    if [ "$distro" == "Ubuntu" ]; then

        ls /etc/ssl/private/key.pem
        if [ "$?" -ne "0" ]; then
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/key.pem -out /etc/ssl/certs/certificate.pem -subj "/CN=xema-manager"
        fi

    fi

    if [ "$distro" == "CentOS" ]; then
        echo "${red}$LINENO: Not implemented${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function configure_asterisk() {
    header

    # Where Asterisk writes recordings started through ARI, which is how the Queue service records
    # a conversation. Asterisk will not create it: asked to record into a directory that is not
    # there, it answers 500 and the call carries on unrecorded. Nothing else fails, so a box can
    # run for weeks before anyone goes looking for a recording that was never written. It used to
    # be a note in the source saying to make the folder by hand.
    if [ ! -d /var/spool/asterisk/recording ]; then
        log "creating /var/spool/asterisk/recording"
        mkdir -p /var/spool/asterisk/recording
    fi

    # Owned by Asterisk whether we made it or found it — a directory created by hand as root is
    # exactly the case that leaves recording broken in a way that looks like it works.
    chown asterisk:asterisk /var/spool/asterisk/recording

    if [ "$distro" == "CentOS" ]; then
        echo "${red}$LINENO: Not implemented${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function configure_mysql() {
    header

    # No user is created here any more, and no password is chosen here.
    #
    # It used to make 'xema'@'localhost' with the password 'xema' — the same credentials on every
    # Xema server anywhere, decided by an install script. Worse, they only reached the software
    # because a release's appsettings.json was copied into /etc/xema, which is what let a file full
    # of defaults nobody chose override the wiring a cluster later derived.
    #
    # An administrator says what the software connects to, once, with their own login as the
    # credential — which makes the database user with a generated password, records it where every
    # service reads it, and creates and migrates the databases. `xema --help` on the box says how.

    # A local MariaDB is not a given any more: the site's database may be on another machine
    # entirely, and this box may simply have the package sitting unused.
    if ! command -v mysql >/dev/null 2>&1; then
        footer "no local mysql"
        return 0
    fi

    # migrate Xema tables from Compact to Dynamic row format
    compact_tables=$(mysql -u root -N -B -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='Xema' AND ROW_FORMAT='Compact' AND ENGINE='InnoDB';" 2>/dev/null)

    log "compact_tables=$compact_tables"

    if [ -n "$compact_tables" ] && [ "$compact_tables" -gt "0" ]; then
        echo "${green}Converting $compact_tables Xema tables to DYNAMIC row format ...${reset}"

        mysql -u root -N -B -e "SELECT CONCAT('ALTER TABLE \`Xema\`.\`', TABLE_NAME, '\` ROW_FORMAT=DYNAMIC;')
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='Xema' AND ROW_FORMAT='Compact' AND ENGINE='InnoDB';" | mysql -u root Xema
    fi

    # if [ "$distro" == "Ubuntu" ]; then
    #     echo "${red}$LINENO: Not implemented${reset}"
    # fi

    # if [ "$distro" == "CentOS" ]; then
    #     echo "${red}$LINENO: Not implemented${reset}"
    # fi

    # if [ "$distro" == "Unknown" ]; then
    #     echo "${red}$LINENO: $distro OS${reset}"
    # fi

    footer
}

function configure_logrotate() {
    header

    # Placed by `xema node files`, which carries the file. See configure_node_files.

    footer
}

function configure_prometheus() {
    header

    # Placed by `xema node files`, which carries prometheus.yml and target-xema.json.

    footer
}

function configure_xema_service() {
    header

    if [[ $hostsys == "WSL" && $kernel == "Linux" ]]; then
        # wsl
        # `xema node files` places the init script where there is no systemd, and marks it
        # executable. Registering it with update-rc.d is still this script's, because it is a
        # Debian-ism rather than something the CLI should know.
        if [ -f /etc/init.d/xema-manager ]; then
            update-rc.d xema-manager defaults
        fi

    elif [[ $hostsys == "Linux" && $kernel == "Linux" ]]; then
        # Ubuntu, CentOS
        #
        # Manager's unit is fetched and enabled here, and it is the only one. Manager is not a
        # role: it always runs, it is the node agent that acts on role changes, and it serves the
        # console an administrator sets the rest up in. A machine with nothing enabled at all
        # would have no way to be told anything.
        #
        # Every other unit is installed by `xema component install` and left switched off.
        # Declaring what a server runs is `xema role add`; switching it on is `xema node apply`.
        # Enabling them here would put a fresh box straight into service as something nobody had
        # chosen yet.
        #
        # Nothing is ever disabled. An upgrade re-runs this script on a live call centre, and a
        # release that switched services off would take every one of them dark.
        # xema-manager and xema-host are placed and enabled by `xema node files`, which carries
        # them. Every other unit is installed by `xema component install` and left switched off:
        # declaring what a server runs is `xema role add`, switching it on is `xema node apply`.
        #
        # Nothing is ever disabled here. An upgrade re-runs this script on a live call centre, and a
        # release that switched services off would take every one of them dark.
        :
    fi

    footer
}

function configure_admin_access() {
    header

    if [ "$distro" == "Ubuntu" ]; then
        ssh-import-id-gh VasuInukollu
    fi

    if [ "$distro" == "CentOS" ]; then
        echo "${red}$LINENO: Not implemented${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function reload_configurations() {
    header

    # if [[ $configured == "yes" ]]; then

    # fi

    log "-> reload_nginx"
    reload_nginx

    log "-> reload_prometheus"
    reload_prometheus

    footer
}

function reload_nginx() {
    header

    if [ "$distro" == "Ubuntu" ]; then
        nginx -s reload
    fi

    if [ "$distro" == "CentOS" ]; then
        nginx -s reload
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function reload_prometheus() {
    header

    if [ "$distro" == "Ubuntu" ]; then
        systemctl restart prometheus
    fi

    if [ "$distro" == "CentOS" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    footer
}

function install_and_configure_system() {
    header

    log "-> install_tools_and_binaries"
    install_tools_and_binaries

    log "-> configure_components"
    configure_components

    log "-> reload_configurations"
    reload_configurations

    footer
}

# variable $started
function setup_and_start_services() {
    header
    started="no"

    log "-> install_and_configure_system"
    install_and_configure_system

    if [[ $configured == "yes" ]]; then

        # do anything else neededd

        started="yes"
    fi

    footer started="$started"
}

help() {
    # Display Help
    echo "Install Xema Platform software."
    echo "Syntax: ./install-xema.sh [-d|h|m|v]"
    echo "options:"
    echo "h     Print this Help."
    echo "d     Install the Dev release."
    echo "m     Display the OS support matrix."
    echo "v     Increase verbosity (use up to -vvv to remove apt quiet flags)."
    echo
    echo "This installs the software. What the server is for is decided afterwards, with `xema`."
    echo
}

# variable $success
function bootstrap() {
    header
    success="no"

    echo "Selected ${green}$channel${reset} channel ..."

    log "-> setup_and_start_services"
    setup_and_start_services

    if [[ $started == "yes" ]]; then

        # do anything else neededd

        success="yes"
    fi

    footer success="$success"
}

function show_log() {
    # "" required to display new lines
    echo "$logger"
}

function detect_installed_channel() {
    header

    if [[ -f /var/lib/xema/manager/appsettings.json ]]; then
        channel=$(cat /var/lib/xema/manager/appsettings.json | grep '"Channel":' | cut -d'"' -f4)
    fi

    footer channel="$channel"
}

# finally
channel="release"
display_matrix="false"
verbosity=0
while getopts hdmv option; do
    case $option in
    h) # display Help
        help
        exit
        ;;
    d) # Dev release
        channel="dev"
        ;;
    m) # Display support matrix
        display_matrix="true"
        ;;
    v) # Increase verbosity
        verbosity=$((verbosity + 1))
        ;;
    \?) # Invalid option
        # -r used to name what the server was for. It is gone rather than ignored: a script that
        # silently installed everything when told to install a subset would be believed for
        # months. Roles are `xema role add` now, after the install.
        echo "Error: Invalid option"
        echo
        help
        exit
        ;;
    esac
done

# Set apt quiet flags: -qqq by default, one q removed per -v
_quiet_level=$((3 - verbosity))
if [ $_quiet_level -lt 0 ]; then _quiet_level=0; fi
if [ $_quiet_level -eq 0 ]; then
    apt_quiet=""
else
    apt_quiet="-$(printf 'q%.0s' $(seq 1 $_quiet_level))"
fi
unset _quiet_level

#detect_installed_channel

log "channel: ""${green}$channel${reset}"

# Display just the support matrix if requested
if [[ $display_matrix == "true" ]]; then
    print_support_matrix
    exit 0
fi

depth=0
set_colors
bootstrap
if [[ $success == "no" || $channel == "dev" ]]; then show_log; fi

# Says it finished, and nothing more. What to do next is not printed here: this script is fetched
# over the public internet and its output is the one part of it anybody running it will read, so it
# is not the place to describe how a site is put together. `xema --help` covers it on the box.
if [[ $success == "yes" ]]; then
    echo
    echo "${green}Installed.${reset} Manager is running; nothing else is, yet."
    echo
fi
