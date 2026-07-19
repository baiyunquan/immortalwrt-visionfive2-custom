#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${SOURCE_DIR:-$repo_root/upstream/immortalwrt}"

# shellcheck disable=SC1091
source "$repo_root/versions.env"

clone_pinned() {
	local url="$1"
	local commit="$2"
	local destination="$3"
	local label="$4"
	local actual

	if [[ -e "$destination" ]]; then
		if [[ ! -d "$destination/.git" ]]; then
			echo "$label target already exists and is not a Git checkout: $destination" >&2
			exit 1
		fi

		actual="$(git -C "$destination" rev-parse HEAD)"
		if [[ "$actual" != "$commit" ]]; then
			echo "$label target has revision $actual; expected $commit" >&2
			exit 1
		fi

		echo "$label already present at $actual"
		return
	fi

	mkdir -p -- "$(dirname -- "$destination")"
	git init --quiet "$destination"
	git -C "$destination" remote add origin "$url"
	git -C "$destination" fetch --quiet --depth 1 origin "$commit"
	git -C "$destination" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD

	actual="$(git -C "$destination" rev-parse HEAD)"
	if [[ "$actual" != "$commit" ]]; then
		echo "$label checkout mismatch: expected $commit, got $actual" >&2
		exit 1
	fi

	echo "$label: $actual"
}

custom_dir="$source_dir/package/custom"

clone_pinned \
	'https://github.com/jerrykuku/luci-theme-argon.git' \
	"$ARGON_THEME_COMMIT" \
	"$custom_dir/luci-theme-argon" \
	'Argon theme'

clone_pinned \
	'https://github.com/jerrykuku/luci-app-argon-config.git' \
	"$ARGON_CONFIG_COMMIT" \
	"$custom_dir/luci-app-argon-config" \
	'Argon configuration app'

# ImmortalWrt's pinned official feeds already provide current vlmcsd,
# luci-app-vlmcsd, docker, dockerd and the riscv64-compatible luci-app-docker.
# Cloning alternate copies here would create duplicate package definitions.
