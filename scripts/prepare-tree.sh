#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/upstream/immortalwrt"

rsync --archive --delete "$repo_root/files/" "$source_dir/files/"
cp "$repo_root/configs/visionfive2.config" "$source_dir/.config"
