#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${SOURCE_DIR:-$repo_root/upstream/immortalwrt}"
config="$source_dir/.config"
mihomo_makefile="$repo_root/feeds/nikki/mihomo-meta/Makefile"

# shellcheck disable=SC1091
source "$repo_root/versions.env"

require_line() {
	local line="$1"
	if ! grep -Fqx -- "$line" "$config"; then
		echo "Required configuration is missing: $line" >&2
		exit 1
	fi
}

required_y=(
	CONFIG_TARGET_starfive
	CONFIG_TARGET_starfive_generic
	CONFIG_TARGET_starfive_generic_DEVICE_visionfive2-v1.3b
	CONFIG_TARGET_ROOTFS_EXT4FS
	CONFIG_TARGET_IMAGES_GZIP
	CONFIG_LUCI_LANG_zh_Hans
	CONFIG_PACKAGE_luci
	CONFIG_PACKAGE_luci-i18n-base-zh-cn
	CONFIG_PACKAGE_nikki
	CONFIG_PACKAGE_luci-app-nikki
	CONFIG_PACKAGE_luci-i18n-nikki-zh-cn
	CONFIG_PACKAGE_mihomo-meta
	CONFIG_PACKAGE_kmod-wireguard
	CONFIG_PACKAGE_wireguard-tools
	CONFIG_PACKAGE_luci-proto-wireguard
	CONFIG_PACKAGE_luci-theme-argon
	CONFIG_PACKAGE_luci-app-argon-config
	CONFIG_PACKAGE_vlmcsd
	CONFIG_PACKAGE_luci-app-vlmcsd
	CONFIG_PACKAGE_docker
	CONFIG_PACKAGE_dockerd
	CONFIG_PACKAGE_luci-app-docker
	CONFIG_PACKAGE_ttyd
	CONFIG_PACKAGE_luci-app-ttyd
	CONFIG_PACKAGE_curl
	CONFIG_PACKAGE_wget-ssl
	CONFIG_PACKAGE_bash
	CONFIG_PACKAGE_nano
	CONFIG_PACKAGE_htop
	CONFIG_PACKAGE_tmux
	CONFIG_PACKAGE_git
	CONFIG_PACKAGE_rsync
	CONFIG_PACKAGE_iperf3
	CONFIG_PACKAGE_tcpdump
	CONFIG_PACKAGE_ethtool
	CONFIG_PACKAGE_block-mount
	CONFIG_PACKAGE_e2fsprogs
	CONFIG_PACKAGE_parted
	CONFIG_PACKAGE_smartmontools
)

for symbol in "${required_y[@]}"; do
	require_line "$symbol=y"
done

require_line 'CONFIG_STARFIVE_SD_BOOT_PARTSIZE=128'
require_line 'CONFIG_TARGET_ROOTFS_PARTSIZE=512'
require_line 'CONFIG_ARCH="riscv64"'
require_line '# CONFIG_TARGET_ROOTFS_SQUASHFS is not set'
require_line 'CONFIG_DOCKER_CGROUP_OPTIONS=y'
require_line 'CONFIG_DOCKER_NET_MACVLAN=y'
require_line 'CONFIG_DOCKER_STO_EXT4=y'

check_custom_revision() {
	local path="$1"
	local expected="$2"
	local label="$3"
	local actual

	actual="$(git -C "$path" rev-parse HEAD)"
	if [[ "$actual" != "$expected" ]]; then
		echo "$label revision mismatch: expected $expected, got $actual" >&2
		exit 1
	fi
}

check_custom_revision \
	"$source_dir/package/custom/luci-theme-argon" \
	"$ARGON_THEME_COMMIT" 'Argon theme'
check_custom_revision \
	"$source_dir/package/custom/luci-app-argon-config" \
	"$ARGON_CONFIG_COMMIT" 'Argon configuration app'

grep -Fqx 'PKG_SOURCE_PROTO:=git' "$mihomo_makefile"
grep -Fqx 'PKG_SOURCE_URL:=https://github.com/MetaCubeX/mihomo.git' "$mihomo_makefile"
grep -Fqx 'GO_PKG:=github.com/metacubex/mihomo' "$mihomo_makefile"
grep -Fqx '$(eval $(call GoBinPackage,mihomo-meta))' "$mihomo_makefile"

if find "$repo_root/feeds/nikki/mihomo-meta" -type f \
	\( -name '*.ipk' -o -name '*.apk' -o -name 'mihomo' \) -print -quit | grep -q .; then
	echo 'A prebuilt Mihomo artifact was found in the source feed.' >&2
	exit 1
fi

grep -Fq "ucidef_set_interfaces_lan_wan \"eth0\" \"eth1\"" \
	"$source_dir/target/linux/starfive/base-files/etc/board.d/02_network"

echo 'Configuration checks passed.'
