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
set_package firewall4
set_package nftables-json
set_package miniupnpd-nftables

# Keep the kernel-side nftables features needed by Nikki and firewall4.
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
set_package mihomo-meta
set_package nikki
set_package luci-app-nikki
set_package luci-i18n-nikki-zh-cn
set_package openlist2
set_package luci-app-openlist2
set_package vlmcsd
set_package luci-app-vlmcsd
set_package podman
set_package luci-app-podman
set_package luci-i18n-podman-zh-cn

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

rm -rf package/luci-app-amlogic
git clone --depth 1 https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic
