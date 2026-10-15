#!/bin/bash

set -eu

forbidden="$(grep -E '^CONFIG_PACKAGE_.*(iptables|ip6tables|xtables|ipset).*=(y|m)$|^CONFIG_PACKAGE_(kmod-ipt(-|$)|kmod-ip6tables(-|$)|kmod-iptables(-|$)|kmod-nf-ipt(-|$)|libxtables|libipset).*=(y|m)$' .config || true)"
if [[ -n "${forbidden}" ]]; then
    echo "Forbidden iptables compatibility packages are enabled:" >&2
    echo "${forbidden}" >&2
    exit 1
fi

grep -q '^CONFIG_PACKAGE_firewall4=y$' .config
grep -q '^CONFIG_PACKAGE_nftables-json=y$' .config
