#!/bin/bash

set -eu

forbidden="$(grep -E '^CONFIG_PACKAGE_.*(iptables|ip6tables|xtables|ipset|iptext|nf-ipvs|br-netfilter|sched-connmark).*=(y|m)$|^CONFIG_PACKAGE_(kmod-ipt(-|$)|kmod-ip6tables(-|$)|kmod-iptables(-|$)|kmod-nf-ipt(-|$)|kmod-nf-ipvs(-|$)|kmod-br-netfilter(-|$)|kmod-sched-connmark(-|$)|libxtables|libip[46]tc|libipset).*=(y|m)$' .config || true)"
if [[ -n "${forbidden}" ]]; then
    echo "Forbidden iptables compatibility packages are enabled:" >&2
    echo "${forbidden}" >&2
    exit 1
fi

grep -q '^CONFIG_PACKAGE_firewall4=y$' .config
grep -q '^CONFIG_PACKAGE_nftables-json=y$' .config
if grep -q '^CONFIG_PACKAGE_kmod-nft-compat=[ym]$' .config; then
    echo "The nftables compatibility kernel module must remain disabled:" >&2
    grep '^CONFIG_PACKAGE_kmod-nft-compat=' .config >&2
    exit 1
fi
