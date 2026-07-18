#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/versions.env"

check_revision() {
	local path="$1"
	local expected="$2"
	local label="$3"
	local actual

	actual="$(git -C "$path" rev-parse HEAD)"
	if [[ "$actual" != "$expected" ]]; then
		echo "$label revision mismatch: expected $expected, got $actual" >&2
		exit 1
	fi
	echo "$label: $actual"
}

check_revision "$repo_root/upstream/immortalwrt" "$IMMORTALWRT_COMMIT" ImmortalWrt
check_revision "$repo_root/feeds/nikki" "$NIKKI_COMMIT" Nikki

actual_mihomo_version="$(sed -n 's/^PKG_SOURCE_VERSION:=//p' "$repo_root/feeds/nikki/mihomo-meta/Makefile")"
if [[ "$actual_mihomo_version" != "$MIHOMO_SOURCE_VERSION" ]]; then
	echo "Mihomo source version mismatch: expected $MIHOMO_SOURCE_VERSION, got $actual_mihomo_version" >&2
	exit 1
fi
echo "Mihomo source: $actual_mihomo_version"
