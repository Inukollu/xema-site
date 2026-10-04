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


# This script makes the `xema` command runnable. That is the whole of its job.
#
# Vasu, 2026-10-01: *"the install.sh will only be used to ensure the cli is able to run .. the rest
# should be handled by the cli"*, and *"on the first install, only cli should be installed to ensure
# the existing V1 installation is not affected"*.
#
# **What it no longer does, and why none of it belonged here.** It used to install and start nginx,
# Prometheus, Asterisk, RabbitMQ, Redis and MariaDB on every machine; unpack fifteen Xema components
# and the Manager; disable the firewall; delete the nginx site the box was being served from;
# convert the row format of the Xema tables a running system was reading; and copy settings out of
# the old layout while pruning directories inside it.
#
# Every one of those is a decision about what a machine is for, taken by whoever happened to run an
# install, at the one moment nobody knew yet. On a server already running Xema V1 -- which is what
# this lands on -- they are decisions about somebody else's live call centre, taken before anyone
# had chosen to migrate, and not undone by running the script again.
#
# So: the operating system is checked, the tools and the .NET runtime go on, the CLI is fetched, and
# the script stops. An administrator says what the server is for afterwards, with `xema`. What that
# involves is not spelled out here -- this file is fetched over the public internet, so it describes
# what it installs and not how a site is put together. `xema --help` covers it on the box.
#
# **Where things live is the CLI's business too.** This script used to own the layout -- vendor code
# under /opt, configuration under /etc, state under /var/lib, and the migration from the older
# single-directory arrangement. It installs one binary to /usr/local/bin now and knows nothing about
# the rest, so the constants that described that layout have gone with the code that used them.

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

function install_tools_and_binaries() {
    header
    installed="no"

    log "-> xema_capable_operating_environment"
    xema_capable_operating_environment

    if [[ $installable == "yes" ]]; then
        log "-> install_tools"
        echo "${green}Installing tools ...${reset}"
        install_tools

        # The runtime, because the CLI is framework-dependent: `Cli.csproj` is
        # `<SelfContained>false`, so a single-file `xema` still needs .NET on the box. Installing it
        # is the larger half of "make the CLI runnable" and the only reason this script needs the
        # network for anything but the CLI itself.
        log "-> install_dotnet"
        echo "${green}Installing .NET runtime ...${reset}"
        install_dotnet

        log "-> install_xema_cli"
        echo "${green}Installing Xema CLI ...${reset}"
        install_xema_cli

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

# The .NET runtime the CLI needs, and nothing else.
#
# **This replaces `install_dependencies`, which installed and started nginx, Prometheus, Asterisk,
# RabbitMQ, Redis and MariaDB on every box.** Those are a site's infrastructure, not a prerequisite
# for running `xema`, and starting a database on a machine already running one is exactly the kind
# of thing this script no longer decides.
#
# **It also replaces a call that did not exist.** `install_dependencies` called `ubuntu_dotnet`,
# which was never defined anywhere in this file. With no `set -e`, bash printed
# `ubuntu_dotnet: command not found` and carried on, so no Ubuntu install has ever had .NET put on
# it by this script -- and the binaries are framework-dependent, so they could only ever have run
# on a box where something else had already installed it. The failure was one line in a long
# install log, which is why it survived.
function install_dotnet() {
    header

    # Already there, whatever put it there. The CLI needs a runtime, not a particular provenance.
    if command -v dotnet >/dev/null 2>&1; then
        footer "dotnet already installed"
        return 0
    fi

    if [ "$distro" == "Ubuntu" ]; then
        # Microsoft's feed, registered the way this repository has always registered it --
        # `install/xema-manager.sh` does the same per-release `packages-microsoft-prod.deb`. The
        # release is the one already detected, rather than a guess, so an unsupported Ubuntu fails
        # here saying which version it is instead of installing something arbitrary.
        wget -q "https://packages.microsoft.com/config/ubuntu/$version.04/packages-microsoft-prod.deb" \
            -O /tmp/packages-microsoft-prod.deb
        if [ "$?" -ne "0" ]; then
            echo "${red}$LINENO: no Microsoft package feed for Ubuntu $version${reset}"
            footer
            return 1
        fi

        dpkg -i /tmp/packages-microsoft-prod.deb
        rm -f /tmp/packages-microsoft-prod.deb
        apt $apt_quiet update

        # The runtime, not the SDK, and not ASP.NET: `xema` is a console application. A node that
        # later runs Manager or the BFF needs `aspnetcore-runtime`, and installing that is the
        # CLI's business when it installs those components.
        apt $apt_quiet install -y dotnet-runtime-10.0
    fi

    if [ "$distro" == "CentOS" ]; then
        echo "${red}$LINENO: Not implemented${reset}"
    fi

    if [ "$distro" == "Unknown" ]; then
        echo "${red}$LINENO: $distro OS${reset}"
    fi

    # Said out loud rather than left to fail later: without a runtime the CLI cannot start, and
    # "installed" would be a lie.
    if ! command -v dotnet >/dev/null 2>&1; then
        echo "${red}$LINENO: .NET was not installed, so the Xema CLI will not run${reset}"
        footer
        return 1
    fi

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

function install_and_configure_system() {
    header

    log "-> install_tools_and_binaries"
    install_tools_and_binaries

    # **Nothing is configured here, by design.**
    #
    # Vasu, 2026-10-01: *"the install.sh will only be used to ensure the cli is able to run .. the
    # rest should be handled by the cli"*, and *"on the first install, only cli should be installed
    # to ensure the existing V1 installation is not affected"*.
    #
    # Everything this phase used to do reached into the machine rather than adding to it: it
    # installed and started nginx, Prometheus, Asterisk, RabbitMQ, Redis and MariaDB; disabled the
    # firewall; deleted the nginx site the box was being served from; converted the row format of
    # the Xema tables a running V1 was reading; and copied V1's settings out while pruning
    # directories inside V1's own tree. A script fetched over the public internet and piped into
    # `sudo bash` is the wrong place to decide any of that, and on a live V1 call centre it is the
    # wrong moment.
    #
    # The CLI does it instead, when an administrator says so and in an order it controls.

    footer
}

# variable $started
function setup_and_start_services() {
    header
    started="no"

    log "-> install_and_configure_system"
    install_and_configure_system

    # Done when the CLI is in place: that is the whole of this script's job since configuring moved to the CLI.
    # It waited on `configured`, which nothing sets any more, so every install ended "success=no" and skipped the
    # closing message — seen on mini5, 2026-10-05, after an install that had worked.
    if [[ $installed == "yes" ]]; then
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
    echo 'This installs the xema command only. Everything else is done afterwards, with xema.'
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
    # Says what it did *and* what it did not, because the difference is the whole point: somebody
    # running this on a live V1 server needs to know their server was not otherwise touched.
    echo "${green}Installed the Xema CLI.${reset} Nothing else was installed and nothing was configured;"
    echo "whatever is already running on this machine is untouched. Run ${green}xema --help${reset} to go on."
    echo
fi
