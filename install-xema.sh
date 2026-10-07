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

# Whether Xema V2 can be installed on the machine an os-release describes: the sentence that says why not, and status 1,
# or nothing and status 0. The path defaults to /etc/os-release and is an argument so it can be tested.
#
# **Ubuntu 24.04 or later, and nothing else** (Vasu, 2026-10-08: "change the v2 installer require Ubuntu 24 minimum").
# ahmedabad was converted on 22.04, whose newest Asterisk, 18.10, answers BSNL's `tel:` request URIs with 416, and whose
# systemd 249 does not know unit keys V2 writes. V2 needs the Asterisk 22 and the systemd 24.04 and later carry.
# **Nothing passes for want of knowing**: an os-release that is missing or unreadable, or an Ubuntu without a version
# this can read, is refused too. Read, not sourced, so nothing in the file is run. Asked before anything is installed.
function os_release_refusal() {
    local file="${1:-/etc/os-release}"
    local requirement="Xema V2 needs Ubuntu 24.04 or later"
    local key value id="" version="" name=""

    if [[ ! -f $file || ! -r $file ]]; then
        echo "This server's $file could not be read, so which operating system it runs cannot be told. $requirement."
        return 1
    fi

    while IFS='=' read -r key value || [[ -n $key ]]; do
        value=${value%\"}; value=${value#\"}; value=${value%\'}; value=${value#\'}
        case $key in
        ID) id=$value ;;
        VERSION_ID) version=$value ;;
        NAME) name=$value ;;
        esac
    done < "$file"

    if [[ $id != "ubuntu" ]]; then
        echo "This server runs ${name:-${id:-an operating system its os-release does not name}}${version:+ $version}." \
            "$requirement; install it on Ubuntu and run this again."
        return 1
    fi

    if [[ ! $version =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        echo "This server runs Ubuntu, but $file gives no version that can be read${version:+ (\"$version\")}. $requirement."
        return 1
    fi

    # Compared as numbers, so 24.10 is after 24.04 and 26.04 after both.
    local year=$((10#${BASH_REMATCH[1]})) month=$((10#${BASH_REMATCH[2]}))
    if (( year < 24 || (year == 24 && month < 4) )); then
        echo "This server runs Ubuntu $version. $requirement; upgrade the operating system and run this again."
        return 1
    fi
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

# The release the channel's files are attached to.
function channel_tag() {
    if [ "$channel" == "dev" ]; then echo "dev"; else echo "v2.0"; fi
}

# **A channel is installed from only once it has a release**, which its manifest is: everything `xema` does next reads
# it, and without one the channel's `Cli.zip` is whatever was last left there. The stable channel held an unversioned CLI
# from August, `xema 1.0.0`, which installed and then could never update (2026-10-06). Asked before anything is installed,
# so a refusal leaves the machine as it was.
function channel_has_release() {
    header
    if ! curl -fsSL -o /dev/null -m 60 "https://github.com/inukollu/xema-site/releases/download/$(channel_tag)/manifest.json"; then
        echo "${red}$LINENO: the $channel channel has no release yet, so there is no xema to install from it.${reset}"
        echo "Install from the dev channel:  curl -fsSL https://www.xema.in/install-xema.sh | sudo bash -s -- -d"
        footer
        return 1
    fi
    footer
}

function install_tools_and_binaries() {
    header
    installed="no"

    log "-> xema_capable_operating_environment"
    xema_capable_operating_environment

    if [[ $capable == "yes" ]] && channel_has_release; then
        log "-> install_tools"
        echo "${green}Installing tools ...${reset}"
        install_tools

        # The runtime, because the CLI is framework-dependent: `Cli.csproj` is
        # `<SelfContained>false`, so a single-file `xema` still needs .NET on the box. Installing it
        # is the larger half of "make the CLI runnable" and the only reason this script needs the
        # network for anything but the CLI itself.
        # Each step's failure stops it: carrying on past a missing runtime is how this once said "installed" over a
        # `xema` that could not start.
        log "-> install_dotnet"
        echo "${green}Installing .NET runtime ...${reset}"
        if install_dotnet; then
            log "-> install_xema_cli"
            echo "${green}Installing Xema CLI ...${reset}"
            if install_xema_cli; then
                installed="yes"
            fi
        fi
    fi

    footer installed="$installed"
}

function xema_capable_operating_environment() {
    header
    capable="no"

    log "-> detect_host"
    detect_host
    if [[ ! $kernel = *Linux* ]]; then
        echo "${red}$kernel Environment is not supported.${reset}"
    elif ! refusal=$(os_release_refusal /etc/os-release); then
        echo "${red}$refusal${reset}"
    else
        capable="yes"
        log "os-release: Ubuntu 24.04 or later"
    fi

    footer capable="$capable"
}

function install_tools() {
    header

    apt $apt_quiet update
    apt $apt_quiet install -y curl wget unzip at sngrep libpcap0.8
    # apt $apt_quiet install -y git sipsak linphone-cli

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
# Whether `xema` can start here: a .NET 10 runtime, not merely some `dotnet`. A V1 server has V1's .NET Core 3.1, and
# reading that as "installed" left `xema` unable to start ("libhostfxr.so does not support single-file apps") while
# this script reported success (bsnldialer2, 2026-10-06).
#
# **Both frameworks `xema` names**, because the published binary asks for `Microsoft.AspNetCore.App` beside
# `Microsoft.NETCore.App`: with the base runtime alone it still refuses to start ("Framework: 'Microsoft.AspNetCore.App',
# version '10.0.0' ... No frameworks were found", bsnldialer2, 2026-10-06).
function has_dotnet_10() {
    command -v dotnet >/dev/null 2>&1 \
        && dotnet --list-runtimes 2>/dev/null | grep -q '^Microsoft\.NETCore\.App 10\.' \
        && dotnet --list-runtimes 2>/dev/null | grep -q '^Microsoft\.AspNetCore\.App 10\.'
}

# variable $dotnet_replaced
function install_dotnet() {
    header
    dotnet_replaced=""

    if has_dotnet_10; then
        footer "dotnet 10 already installed"
        return 0
    fi

    # Said in the closing message: an older .NET from Microsoft's feed is replaced (Vasu, 2026-10-06: "we dont need
    # 3.1 anymore"), because Ubuntu's `dotnet-host-10.0` conflicts with Microsoft's `dotnet-host` and apt takes it out.
    local before=""
    if command -v dotnet >/dev/null 2>&1; then
        before=$(dotnet --list-runtimes 2>/dev/null | awk '/^Microsoft\.NETCore\.App /{print $2}')
    fi

    # **Ubuntu's own build, never Microsoft's feed.** Where Microsoft's feed has .NET 10 it lays it
    # out in /usr/share/dotnet against Ubuntu's /usr/lib/dotnet; mixing the two is how a box ends
    # up with a runtime that `xema` cannot find. Pinned, so a feed some other package registered cannot win.
    cat > /etc/apt/preferences.d/xema-dotnet <<'PIN'
Package: dotnet* aspnet* netstandard*
Pin: origin "packages.microsoft.com"
Pin-Priority: -10
PIN

    # 24.04 and later carry .NET 10 in the archive itself, so no other source is added.
    apt $apt_quiet update

    # The runtimes, not the SDK: ASP.NET Core's, which brings the base runtime with it, because `xema` asks for both.
    apt $apt_quiet install -y aspnetcore-runtime-10.0

    # Said out loud rather than left to fail later: without a runtime the CLI cannot start, and "installed" would be a
    # lie.
    if ! has_dotnet_10; then
        echo "${red}$LINENO: .NET 10 was not installed, so the Xema CLI will not run${reset}"
        footer
        return 1
    fi

    # Only what is gone now: a runtime apt does not own stays where it was, and is not said to have been replaced.
    local after
    after=$(dotnet --list-runtimes 2>/dev/null | awk '/^Microsoft\.NETCore\.App /{print $2}')
    dotnet_replaced=$(comm -23 <(echo "$before" | sed '/^$/d' | sort -u) <(echo "$after" | sort -u) | paste -sd, -)

    footer
}

function install_xema_cli() {
    header

    rm -rf /tmp/cli.zip

    release_tag=$(channel_tag)

    wget -q --show-progress https://github.com/inukollu/xema-site/releases/download/$release_tag/Cli.zip -O /tmp/cli.zip
    # The binary on the PATH, and the operator's scripts beside the rest of Xema's code — not unpacked whole, which
    # put scripts/ in /usr/local/bin. Placed here because `xema update` places them only when it replaces the
    # binary, and straight after this the binary is the channel's already. A V1 server is not read as V2 for it:
    # discovery does not count scripts as a component.
    unzip -qo /tmp/cli.zip xema -d /usr/local/bin
    if unzip -l /tmp/cli.zip 'scripts/*' >/dev/null 2>&1; then
        mkdir -p /opt/techsudoku/xema
        unzip -qo /tmp/cli.zip 'scripts/*' -d /opt/techsudoku/xema
        chmod +x /opt/techsudoku/xema/scripts/*.sh
    fi
    chmod +x /usr/local/bin/xema

    # Run once before anything relies on it: a binary that cannot start is not an installed CLI.
    if ! /usr/local/bin/xema --version > /dev/null; then
        echo "${red}$LINENO: the Xema CLI was placed but does not start${reset}"
        footer
        return 1
    fi

    # A minimal Ubuntu has no bash-completion directory, and writing into one that is not there failed and was passed over.
    mkdir -p /etc/bash_completion.d
    /usr/local/bin/xema completion bash > /etc/bash_completion.d/xema

    # The channel this was installed from, so the first `xema update` or `xema upgrade` takes it without being told
    # again. Recorded through `xema`, which owns where it lives; a file only, nothing a V1 server reads.
    if ! /usr/local/bin/xema channel set "$channel" > /dev/null; then
        echo "${red}$LINENO: the Xema CLI could not record the $channel channel${reset}"
        footer
        return 1
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
    echo "Syntax: ./install-xema.sh [-d|h|v]"
    echo "options:"
    echo "h     Print this Help."
    echo "d     Install the Dev release."
    echo "v     Increase verbosity (use up to -vvv to remove apt quiet flags)."
    echo
    echo 'This installs the xema command only. Everything else is done afterwards, with xema.'
    echo 'Xema V2 needs Ubuntu 24.04 or later.'
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

verbosity=0
while getopts hdv option; do
    case $option in
    h) # display Help
        help
        exit
        ;;
    d) # Dev release
        channel="dev"
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
    echo "${green}Installed the Xema CLI${reset} and the .NET 10 runtime it runs on. Nothing else was installed and"
    echo "nothing was configured. Run ${green}xema --help${reset} to go on."
    if [[ -n $dotnet_replaced ]]; then
        echo "The .NET runtime this machine had (${dotnet_replaced}) was replaced by .NET 10."
    fi
    echo
else
    echo
    echo "${red}The Xema CLI was not installed.${reset} The first red line above says why."
    echo
    exit 1
fi
