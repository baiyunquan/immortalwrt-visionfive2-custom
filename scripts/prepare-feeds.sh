#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/upstream/immortalwrt"
nikki_dir="$repo_root/feeds/nikki"
mwan3_feed_dir="$repo_root/feeds/mwan3"

"$repo_root/scripts/verify-versions.sh"

# Fix luci.mk include path for standalone luci-app-mwan3 feed
sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' "$mwan3_feed_dir/luci-app-mwan3/Makefile"

cp "$source_dir/feeds.conf.default" "$source_dir/feeds.conf"
printf '\nsrc-link nikki %s\n' "$nikki_dir" >> "$source_dir/feeds.conf"
printf '\nsrc-link mwan3 %s\n' "$mwan3_feed_dir" >> "$source_dir/feeds.conf"

cd "$source_dir"
./scripts/feeds update -a

# Install every official feed, but only the requested Nikki packages. Installing
# every package from the Nikki feed would also expose the mutually exclusive
# mihomo-alpha provider to Kconfig.
for feed in packages luci routing telephony video; do
	./scripts/feeds install -a -p "$feed"
done
./scripts/feeds install -p nikki nikki luci-app-nikki mihomo-meta

# Replace official mwan3 and luci-app-mwan3 with nftables versions from mwan3 feed
./scripts/feeds uninstall mwan3 luci-app-mwan3
rm -rf package/feeds/packages/mwan3 package/feeds/luci/luci-app-mwan3
./scripts/feeds install -p mwan3 mwan3 luci-app-mwan3

