#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/upstream/immortalwrt"
nikki_dir="$repo_root/feeds/nikki"

"$repo_root/scripts/verify-versions.sh"

cp "$source_dir/feeds.conf.default" "$source_dir/feeds.conf"
printf '\nsrc-link nikki %s\n' "$nikki_dir" >> "$source_dir/feeds.conf"

cd "$source_dir"
./scripts/feeds update -a

# Install every official feed, but only the requested Nikki packages. Installing
# every package from the Nikki feed would also expose the mutually exclusive
# mihomo-alpha provider to Kconfig.
for feed in packages luci routing telephony video; do
	./scripts/feeds install -a -p "$feed"
done
./scripts/feeds install -p nikki nikki luci-app-nikki mihomo-meta
