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
)

for package in "${required_packages[@]}"; do
    if ! grep -q "^CONFIG_PACKAGE_${package}=y$" .config; then
        echo "Required LuCI package is not enabled in the final .config: ${package}" >&2
        exit 1
    fi
done

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
)

for entry in "${required_entries[@]}"; do
    if ! grep -Eq "(^|/)${entry}$" <<<"${archive_entries}"; then
        echo "Required LuCI runtime file is missing from rootfs: ${entry}" >&2
        exit 1
    fi
done

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
