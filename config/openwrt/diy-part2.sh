#!/bin/bash
# OpenWrt package and configuration customization after feeds are installed.

set -eu

default_ip="192.168.1.1"
ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
openwrt_ip="${1:-${default_ip}}"
use_ccache="${2:-true}"
openwrt_branch="${3:-openwrt-25.12}"
network_mode="${4:-bypass}"
network_gateway="${5:-10.0.0.1}"
network_dns="${6:-10.0.0.1}"

[[ "${openwrt_ip}" =~ ${ip_regex} ]] || {
    echo "Invalid OpenWrt IP address: ${openwrt_ip}" >&2
    exit 1
}

[[ "${network_gateway}" =~ ${ip_regex} ]] || {
    echo "Invalid network gateway: ${network_gateway}" >&2
    exit 1
}

[[ "${network_dns}" =~ ${ip_regex} ]] || {
    echo "Invalid network DNS server: ${network_dns}" >&2
    exit 1
}

case "${network_mode}" in
    bypass|router) ;;
    *)
        echo "Invalid network mode: ${network_mode}" >&2
        exit 1
        ;;
esac

set_package() {
    local package="${1}"
    sed -i -E "/^(# )?CONFIG_PACKAGE_${package}(=y| is not set)$/d" .config
    echo "CONFIG_PACKAGE_${package}=y" >>.config
}

unset_feed_repository() {
    local feed="${1}"
    sed -i -E "/^(# )?CONFIG_FEED_${feed}(=y|=m| is not set)$/d" .config
    echo "# CONFIG_FEED_${feed} is not set" >>.config
}

unset_package_family() {
    local pattern="${1}"
    sed -i -E "/^CONFIG_PACKAGE_.*${pattern}.*=y$/ {
        s/^CONFIG_PACKAGE_/# CONFIG_PACKAGE_/
        s/=y$/ is not set/
    }" .config
}

# This project intentionally uses APK and the nftables firewall stack only.
set_package apk-mbedtls
unset_package_family "(opkg|iptables|ip6tables|xtables|ipset)"
unset_package_family "kmod-ipt(-|$)"
unset_package_family "kmod-iptables"
unset_package_family "kmod-nf-ipt"
unset_package_family "kmod-nft-compat"
unset_package_family "br-netfilter"
unset_package_family "sched-connmark"
unset_package_family "nf-ipvs"
unset_package_family "libip[46]tc"
unset_package_family "iptext"
set_package firewall4
set_package nftables-json
set_package miniupnpd-nftables

# Keep the LuCI entry point and both template runtimes explicit. These options
# must be present after feed installation because the source configuration is
# loaded before the feeds exist, and make defconfig can otherwise discard them
# when a feed index is incomplete or changes package visibility.
set_package luci
set_package luci-light
set_package luci-base
set_package luci-compat
set_package luci-lua-runtime
set_package luci-mod-admin-full
set_package luci-theme-bootstrap
set_package ucode-mod-lua
set_package luci-app-package-manager
set_package rpcd-mod-luci
set_package uhttpd
set_package uhttpd-mod-ubus

# These repositories are source feeds used only during the build. They are
# not published at downloads.openwrt.org, so do not emit broken runtime APK
# URLs for them while keeping their packages in the image.
unset_feed_repository nikki
unset_feed_repository lucky
unset_feed_repository openlist
unset_feed_repository kms

# Keep the kernel-side nftables features needed by Nikki and firewall4.
set_package kmod-nft-bridge
set_package kmod-nft-socket
set_package kmod-nft-tproxy
set_package kmod-tun
set_package kmod-dummy
set_package kmod-veth

# Keep wireless support available for the N1 and optional USB/PCIe adapters.
# The N1 uses the Broadcom/Cypress BCM43455 (AP6255) SDIO chipset.
set_package kmod-brcmfmac
set_package kmod-brcmutil
set_package kmod-cfg80211
set_package kmod-mac80211
set_package cypress-firmware-43455-sdio
set_package brcmfmac-nvram-43455-sdio
set_package wifi-scripts
set_package wireless-regdb
set_package wpad-basic-mbedtls

# Personal package set.
set_package lucky
set_package luci-app-lucky
set_package luci-i18n-lucky-zh-cn
set_package mihomo-meta
set_package nikki
set_package luci-app-nikki
set_package luci-i18n-nikki-zh-cn
set_package openlist2
set_package luci-app-openlist2
set_package luci-i18n-openlist2-zh-cn
set_package vlmcsd
set_package luci-app-vlmcsd
set_package luci-i18n-vlmcsd-zh-cn
set_package luci-i18n-base-zh-cn
set_package luci-i18n-amlogic-zh-cn
set_package podman
set_package luci-app-podman
set_package luci-i18n-podman-zh-cn
set_package netavark
set_package aardvark-dns

# The current Nikki feed publishes two mutually conflicting providers for the
# mihomo virtual package. Keeping both package definitions in Kconfig creates
# a recursive dependency even when only the meta provider is selected. Nikki
# uses the virtual name, so keep the requested meta implementation and remove
# the unused alpha provider from the feed/package indexes.
remove_feed_package() {
    local feed="${1}"
    local package="${2}"
    local candidate

    for candidate in \
        "package/feeds/${feed}/${package}" \
        "feeds/${feed}/${package}"; do
        rm -rf -- "${candidate}"
    done
}

remove_feed_package nikki mihomo-alpha

# WeeChat is not part of this image. Its LuCI package currently creates a
# recursive dependency between the full and minimal provider variants during
# Kconfig generation, so omit the unused package family entirely.
remove_feed_package luci applications/luci-app-weechat
remove_feed_package packages net/weechat

# Default IP and root password are handled by the upstream build scripts.
if [[ "${openwrt_ip}" != "${default_ip}" ]]; then
    sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${openwrt_ip}\"}/" \
        package/base-files/*/bin/config_generate
fi

# The N1 is a single-port device. In bypass mode it uses a fixed LAN address,
# points its default route and resolver at the upstream router, and does not
# run a DHCP server. Use a first-boot UCI default so board-generated devices
# such as br-lan remain intact across OpenWrt releases.
network_defaults_file="files/etc/uci-defaults/99-personal-network"
rm -f "${network_defaults_file}"
if [[ "${network_mode}" == "bypass" ]]; then
    mkdir -p "$(dirname "${network_defaults_file}")"
    cat >"${network_defaults_file}" <<EOF
#!/bin/sh

uci set network.lan.proto='static'
uci set network.lan.ipaddr='${openwrt_ip}'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='${network_gateway}'
uci set network.lan.peerdns='0'
uci -q delete network.lan.dns
uci add_list network.lan.dns='${network_dns}'

uci set dhcp.lan.interface='lan'
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'

uci commit network
uci commit dhcp
exit 0
EOF
    chmod +x "${network_defaults_file}"
fi

# Keep radios disabled on the first boot. Users can enable them later from
# LuCI or with `uci set wireless.radioX.disabled=0`.
wireless_defaults_file="files/etc/uci-defaults/99-personal-wireless"
rm -f "${wireless_defaults_file}"
mkdir -p "$(dirname "${wireless_defaults_file}")"
cat >"${wireless_defaults_file}" <<'EOF'
#!/bin/sh

# Generate the hardware-backed wireless configuration when the base image did
# not create it yet, then disable each radio without removing its interfaces.
[ -x /sbin/wifi ] && wifi config >/dev/null 2>&1 || true

radios="$(uci -q show wireless | sed -n 's/^wireless\.\([^=]*\)=wifi-device$/\1/p')"
for radio in ${radios}; do
    uci set "wireless.${radio}.disabled=1"
done

[ -n "${radios}" ] && uci commit wireless
exit 0
EOF
chmod +x "${wireless_defaults_file}"

# Set the requested default root password. This is the MD5-crypt hash for
# "password", matching the login expected by the personal image.
root_password_hash='$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.'
sed -i "s#^root:[^:]*:#root:${root_password_hash}:#" \
    package/base-files/files/etc/shadow

sed -i '/CONFIG_DEVEL/d;/CONFIG_CCACHE/d;/CONFIG_CCACHE_DIR/d' .config
if [[ "${use_ccache}" == "true" ]]; then
    cat >>.config <<'EOF'
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_CCACHE_DIR="$(TOPDIR)/.ccache"
EOF
else
    cat >>.config <<'EOF'
# CONFIG_DEVEL is not set
# CONFIG_CCACHE is not set
CONFIG_CCACHE_DIR=""
EOF
fi

sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/base-files/files/etc/openwrt_release
sed -i "s|DISTRIB_SOURCEREPO='.*'|DISTRIB_SOURCEREPO='github.com/openwrt/openwrt'|g" package/base-files/files/etc/openwrt_release
sed -i "s|DISTRIB_SOURCECODE='.*'|DISTRIB_SOURCECODE='openwrt'|g" package/base-files/files/etc/openwrt_release
sed -i "s|DISTRIB_SOURCEBRANCH='.*'|DISTRIB_SOURCEBRANCH='${openwrt_branch}'|g" package/base-files/files/etc/openwrt_release

amlogic_repo_dir="$(mktemp -d)"
git clone --depth 1 https://github.com/ophub/luci-app-amlogic.git "${amlogic_repo_dir}"
rm -rf package/luci-app-amlogic
cp -a "${amlogic_repo_dir}/luci-app-amlogic" package/luci-app-amlogic
rm -rf -- "${amlogic_repo_dir}"

# OpenWrt 25.12's netavark package does not yet pass the firewall backend to
# Cargo. Netavark otherwise compiles with its upstream iptables default.
netavark_makefile=""
for candidate in \
    package/feeds/packages/netavark/Makefile \
    feeds/packages/net/netavark/Makefile; do
    if [[ -f "${candidate}" ]]; then
        netavark_makefile="${candidate}"
        break
    fi
done

[[ -n "${netavark_makefile}" ]] || {
    echo "Unable to locate the OpenWrt netavark Makefile" >&2
    exit 1
}

# Force the value before RustBinPackage is evaluated. Appending a variable
# after the eval call is too late for OpenWrt's Rust package helper.
sed -i -E 's/NETAVARK_DEFAULT_FW=[^[:space:]\\]+/NETAVARK_DEFAULT_FW=nftables/g' \
    "${netavark_makefile}"
if ! grep -q 'NETAVARK_DEFAULT_FW=nftables' "${netavark_makefile}"; then
    sed -i '/^[[:space:]]*\$(eval \$(call RustBinPackage,netavark))/i CARGO_PKG_VARS += NETAVARK_DEFAULT_FW=nftables' \
        "${netavark_makefile}"
fi

grep -q 'NETAVARK_DEFAULT_FW=nftables' "${netavark_makefile}" || {
    echo "Unable to force netavark's nftables backend" >&2
    exit 1
}

# Make the nftables backend explicit in Podman's network configuration. The
# upstream file already defines the network table, but keep this tolerant of
# future package layout changes.
podman_containers_conf=""
for candidate in \
    package/feeds/packages/podman/files/containers.conf \
    feeds/packages/utils/podman/files/containers.conf; do
    if [[ -f "${candidate}" ]]; then
        podman_containers_conf="${candidate}"
        break
    fi
done

[[ -n "${podman_containers_conf}" ]] || {
    echo "Unable to locate the Podman containers.conf" >&2
    exit 1
}

if grep -q '^\[network\]' "${podman_containers_conf}"; then
    for setting in network_backend firewall_driver network_config_dir default_network; do
        case "${setting}" in
            network_backend) value='"netavark"' ;;
            firewall_driver) value='"nftables"' ;;
            network_config_dir) value='"/etc/containers/networks/"' ;;
            default_network) value='"podman"' ;;
        esac

        if grep -q -E "^#?${setting}[[:space:]]*=" "${podman_containers_conf}"; then
            sed -i -E "s|^#?${setting}[[:space:]]*=.*$|${setting} = ${value}|" \
                "${podman_containers_conf}"
        else
            sed -i "/^\[network\]$/a\\${setting} = ${value}" \
                "${podman_containers_conf}"
        fi
    done
else
    cat >>"${podman_containers_conf}" <<'EOF'

[network]
network_backend = "netavark"
firewall_driver = "nftables"
network_config_dir = "/etc/containers/networks/"
default_network = "podman"
EOF
fi

# The LuCI package ships its defaults as luci-podman-opkg and migrates them
# during first boot. Keep the configured service priority within its 0-99
# accepted range so the live UCI value is deterministic.
luci_podman_defaults="package/luci-app-podman/root/etc/config/luci-podman-opkg"
if [[ -f "${luci_podman_defaults}" ]]; then
    sed -i "s/option init_start_priority '100'/option init_start_priority '99'/" \
        "${luci_podman_defaults}"
else
    echo "Unable to locate the LuCI Podman default configuration" >&2
    exit 1
fi

podman_init_file=""
for candidate in \
    package/feeds/packages/podman/files/podman.init \
    feeds/packages/utils/podman/files/podman.init; do
    if [[ -f "${candidate}" ]]; then
        podman_init_file="${candidate}"
        break
    fi
done

[[ -n "${podman_init_file}" ]] || {
    echo "Unable to locate the Podman init script" >&2
    exit 1
}

# The data partition must be mounted before Podman is allowed to start. This
# prevents a missing p4 mount from silently filling the system overlay.
if ! grep -q 'personal-podman-storage' "${podman_init_file}"; then
    sed -i '/^start_service() {/a\
    if ! grep -qs "[[:space:]]/mnt/mmcblk2p4[[:space:]]" /proc/mounts; then\
        logger -t podman "Podman not started: /mnt/mmcblk2p4 is not mounted"\
        return 1\
    fi\
    mkdir -p /mnt/mmcblk2p4/podman /run/containers/storage /run/podman\
    # personal-podman-storage: keep this guard tied to the customized image\
' "${podman_init_file}"
fi

# Podman requires a cgroup v2 hierarchy at the conventional path. OpenWrt's
# base-files package does not mount it automatically on every supported
# kernel, so install a small idempotent service before Podman's START=99
# service. Keep this in the source customization script so it follows future
# OpenWrt branches without maintaining a second rootfs tree.
cgroup_init_file="files/etc/init.d/personal-cgroup"
rm -f "${cgroup_init_file}"
mkdir -p "$(dirname "${cgroup_init_file}")"
cat >"${cgroup_init_file}" <<'EOF'
#!/bin/sh /etc/rc.common

START=95
STOP=01

cgroup_mount="/sys/fs/cgroup"

mounted_type() {
    awk -v target="${cgroup_mount}" '
        $5 == target {
            for (i = 6; i <= NF; i++) {
                if ($i == "-") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ' /proc/self/mountinfo
}

start() {
    mkdir -p "${cgroup_mount}"

    current_type="$(mounted_type)"
    if [ "${current_type}" = "cgroup2" ] &&
        [ -r "${cgroup_mount}/cgroup.controllers" ]; then
        return 0
    fi

    if [ -n "${current_type}" ]; then
        logger -t personal-cgroup \
            "${cgroup_mount} is already mounted as ${current_type}; cgroup2 is required"
        return 1
    fi

    if ! mount -t cgroup2 cgroup2 "${cgroup_mount}"; then
        logger -t personal-cgroup "unable to mount cgroup2 at ${cgroup_mount}"
        return 1
    fi

    if [ "$(mounted_type)" != "cgroup2" ] ||
        [ ! -r "${cgroup_mount}/cgroup.controllers" ]; then
        logger -t personal-cgroup "cgroup2 mount verification failed"
        return 1
    fi
}

stop() {
    return 0
}
EOF
chmod +x "${cgroup_init_file}"

# Prepare a rootful Podman installation on first boot. The data partition is
# mounted by block-mount and is the only location used for persistent storage.
storage_conf_file="files/etc/containers/storage.conf"
rm -f "${storage_conf_file}"
mkdir -p "$(dirname "${storage_conf_file}")"
cat >"${storage_conf_file}" <<'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/mnt/mmcblk2p4/podman"
EOF

podman_defaults_file="files/etc/uci-defaults/99-personal-podman"
rm -f "${podman_defaults_file}"
mkdir -p "$(dirname "${podman_defaults_file}")"
cat >"${podman_defaults_file}" <<'EOF'
#!/bin/sh

if [ -x /etc/init.d/personal-cgroup ]; then
    /etc/init.d/personal-cgroup enable
fi

if [ -x /etc/init.d/personal-cgroup ] &&
    /etc/init.d/personal-cgroup start &&
    [ -r /sys/fs/cgroup/cgroup.controllers ] &&
    grep -qs "[[:space:]]/mnt/mmcblk2p4[[:space:]]" /proc/mounts; then
    mkdir -p /mnt/mmcblk2p4/podman /run/containers/storage /run/podman
    if [ -x /etc/init.d/podman ]; then
        /etc/init.d/podman enable
        /etc/init.d/podman start
    fi
else
    logger -t personal-podman \
        "Podman not started: cgroup2 or /mnt/mmcblk2p4 is unavailable" 2>/dev/null || true
fi

# The LuCI package's migration script has already moved this configuration by
# this point; enforce the supported priority if the package is present.
if [ -f /etc/config/luci-podman ]; then
    uci set luci-podman.globals.init_start_priority='99'
    uci commit luci-podman
fi

exit 0
EOF
chmod +x "${podman_defaults_file}"
