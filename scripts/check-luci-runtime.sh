#!/bin/bash

set -euo pipefail

rootfs_archive="${1:-}"

required_packages=(
    luci
    luci-light
    luci-base
    luci-compat
    luci-lua-runtime
    luci-mod-admin-full
    luci-theme-bootstrap
    ucode-mod-lua
    luci-app-package-manager
    rpcd-mod-luci
    uhttpd
    uhttpd-mod-ubus
    luci-app-amlogic
    luci-i18n-base-zh-cn
    luci-i18n-amlogic-zh-cn
    luci-i18n-lucky-zh-cn
    luci-i18n-nikki-zh-cn
    luci-i18n-openlist2-zh-cn
    luci-i18n-vlmcsd-zh-cn
    luci-i18n-podman-zh-cn
)

for package in "${required_packages[@]}"; do
    if ! grep -q "^CONFIG_PACKAGE_${package}=y$" .config; then
        echo "Required LuCI package is not enabled in the final .config: ${package}" >&2
        if [[ "${package}" == "luci-i18n-base-zh-cn" ]]; then
            echo "Relevant final configuration:" >&2
            grep -E '^(# )?CONFIG_(LUCI_LANG_zh_Hans|PACKAGE_luci-base|PACKAGE_luci-i18n-base-zh-cn)(=y|=m| is not set)$' .config >&2 || true

            for metadata_file in tmp/.config-package.in tmp/.packageinfo; do
                echo "Package metadata: ${metadata_file}" >&2
                if [[ ! -f "${metadata_file}" ]]; then
                    echo "  metadata file not found" >&2
                    continue
                fi

                if [[ "${metadata_file}" == "tmp/.config-package.in" ]]; then
                    grep -n -B 3 -A 8 -F 'luci-i18n-base-zh-cn' "${metadata_file}" >&2 ||
                        echo "  no luci-i18n-base-zh-cn symbol found" >&2
                else
                    grep -n -B 2 -A 12 -F 'Package: luci-i18n-base-zh-cn' "${metadata_file}" >&2 ||
                        echo "  no luci-i18n-base-zh-cn package record found" >&2
                fi
            done
        fi
        exit 1
    fi
done

forbidden_packages="$(grep -E '^CONFIG_PACKAGE_(luci-app-(ddns|frpc|frps|samba4|ttyd|upnp)|luci-i18n-(ddns|frpc|frps|samba4|ttyd|upnp)-[^=]+|ddns-scripts.*|frpc|frps|samba4-[^=]+|ttyd|miniupnpd-nftables|luci-theme-material)=(y|m)$' .config || true)"
if [[ -n "${forbidden_packages}" ]]; then
    echo "Unrequested LuCI services or the Material theme are enabled:" >&2
    echo "${forbidden_packages}" >&2
    exit 1
fi

if ! grep -q '^CONFIG_LUCI_LANG_zh_Hans=y$' .config; then
    echo "Simplified Chinese LuCI language is not enabled in the final .config" >&2
    exit 1
fi

if [[ -z "${rootfs_archive}" ]]; then
    echo "LuCI configuration check passed"
    exit 0
fi

if [[ ! -f "${rootfs_archive}" ]]; then
    echo "Rootfs archive does not exist: ${rootfs_archive}" >&2
    exit 2
fi

archive_entries="$(tar -tzf "${rootfs_archive}")"
required_entries=(
    etc/config/luci
    usr/lib/ucode/lua.so
    usr/share/ucode/luci/runtime.uc
    usr/share/ucode/luci/template/header.ut
    usr/share/ucode/luci/template/themes/bootstrap/header.ut
    www/luci-static/bootstrap/cascade.css
    etc/containers/storage.conf
    etc/init.d/personal-cgroup
    etc/init.d/podman
    etc/uci-defaults/99-personal-podman
    etc/uci-defaults/99-personal-theme
    usr/sbin/openwrt-install-amlogic
)

required_lmo=(
    usr/lib/lua/luci/i18n/base.zh-cn.lmo
    usr/lib/lua/luci/i18n/amlogic.zh-cn.lmo
    usr/lib/lua/luci/i18n/lucky.zh-cn.lmo
    usr/lib/lua/luci/i18n/nikki.zh-cn.lmo
    usr/lib/lua/luci/i18n/openlist2.zh-cn.lmo
    usr/lib/lua/luci/i18n/vlmcsd.zh-cn.lmo
    usr/lib/lua/luci/i18n/podman.zh-cn.lmo
)

required_luci_files=(
    usr/share/luci/menu.d/luci-app-amlogic.json
    usr/share/luci/menu.d/luci-app-lucky.json
    usr/share/luci/menu.d/luci-app-nikki.json
    usr/share/luci/menu.d/luci-app-openlist2.json
    usr/share/luci/menu.d/luci-app-vlmcsd.json
    usr/share/luci/menu.d/luci-app-podman.json
    usr/share/rpcd/acl.d/luci-app-amlogic.json
    usr/share/rpcd/acl.d/luci-app-lucky.json
    usr/share/rpcd/acl.d/luci-app-nikki.json
    usr/share/rpcd/acl.d/luci-app-openlist2.json
    usr/share/rpcd/acl.d/luci-app-vlmcsd.json
    usr/share/rpcd/acl.d/luci-app-podman.json
)

for entry in "${required_entries[@]}"; do
    if ! grep -Eq "(^|/)${entry}$" <<<"${archive_entries}"; then
        echo "Required LuCI runtime file is missing from rootfs: ${entry}" >&2
        exit 1
    fi
done

for entry in "${required_lmo[@]}" "${required_luci_files[@]}"; do
    if ! grep -Eq "(^|/)${entry}$" <<<"${archive_entries}"; then
        echo "Required LuCI translation/menu/ACL file is missing from rootfs: ${entry}" >&2
        exit 1
    fi
done

storage_conf_entry="$(grep -E '(^|/)etc/containers/storage\.conf$' <<<"${archive_entries}" | head -n 1)"
storage_conf="$(tar -xOzf "${rootfs_archive}" "${storage_conf_entry}")"
grep -q '^driver = "overlay"$' <<<"${storage_conf}"
grep -q '^runroot = "/run/containers/storage"$' <<<"${storage_conf}"
grep -q '^graphroot = "/mnt/mmcblk2p4/podman"$' <<<"${storage_conf}"

podman_init_entry="$(grep -E '(^|/)etc/init\.d/podman$' <<<"${archive_entries}" | head -n 1)"
podman_init="$(tar -xOzf "${rootfs_archive}" "${podman_init_entry}")"
grep -q '/mnt/mmcblk2p4' <<<"${podman_init}"

theme_defaults_entry="$(grep -E '(^|/)etc/uci-defaults/99-personal-theme$' <<<"${archive_entries}" | head -n 1)"
theme_defaults="$(tar -xOzf "${rootfs_archive}" "${theme_defaults_entry}")"
grep -q 'set luci.main.mediaurlbase=/luci-static/bootstrap' <<<"${theme_defaults}"

amlogic_installer_entry="$(grep -E '(^|/)usr/sbin/openwrt-install-amlogic$' <<<"${archive_entries}" | head -n 1)"
amlogic_installer="$(tar -xOzf "${rootfs_archive}" "${amlogic_installer_entry}")"
installer_guard_line="$(grep -n 'personal-podman-before-emmc-unmount' <<<"${amlogic_installer}" | cut -d: -f1)"
installer_unmount_line="$(grep -n '# umount all other mount points' <<<"${amlogic_installer}" | cut -d: -f1)"
if [[ -z "${installer_guard_line}" || -z "${installer_unmount_line}" ||
    "${installer_guard_line}" -ge "${installer_unmount_line}" ]]; then
    echo "The Amlogic installer does not stop Podman before unmounting eMMC" >&2
    exit 1
fi

repositories_entry="$(grep -E '(^|/)etc/apk/repositories\.d/distfeeds\.list$' <<<"${archive_entries}" | head -n 1)"
if [[ -n "${repositories_entry}" ]]; then
    repositories="$(tar -xOzf "${rootfs_archive}" "${repositories_entry}")"
    if grep -Eq '/(kms|lucky|nikki|openlist)/packages\.adb([[:space:]]|$)' <<<"${repositories}"; then
        echo "Custom source feeds were incorrectly emitted as runtime APK repositories" >&2
        grep -E '/(kms|lucky|nikki|openlist)/packages\.adb' <<<"${repositories}" >&2
        exit 1
    fi
fi

echo "LuCI runtime check passed: ${rootfs_archive}"
