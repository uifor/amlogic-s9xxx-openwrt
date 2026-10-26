#!/bin/bash
# OpenWrt feed customization before feeds are updated.

set -eu

openwrt_branch="${1:-openwrt-25.12}"
feed_branch="${openwrt_branch}"
[[ "${feed_branch}" == "main" ]] && feed_branch="master"

# Keep the official feeds aligned with the selected OpenWrt branch. This lets
# the same project follow a future openwrt-26.x branch without code changes.
sed -i -E \
    "s#^(src-git (packages|luci|routing|telephony|video) [^;]+;).*\$#\1${feed_branch}#" \
    feeds.conf.default
