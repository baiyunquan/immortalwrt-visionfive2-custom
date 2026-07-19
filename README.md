# ImmortalWrt for StarFive VisionFive 2 v1.3B

本仓库从固定版本的 ImmortalWrt 源码构建适用于 StarFive VisionFive 2 v1.3B 的自定义镜像。输出为 EXT4 根文件系统的紧凑型 `sdcard.img.gz`，分配 64 MiB 启动分区和 512 MiB 根分区。可以直接刷写，也可以在刷写前自动扩展成与目标 SD 卡容量匹配的镜像。

## 预装内容

- LuCI、简体中文、Nikki、LuCI Nikki、从源码交叉编译的 Mihomo Meta
- WireGuard 内核模块、工具和 LuCI 协议支持
- ttyd 及其 LuCI 页面
- curl、GNU wget（`wget-ssl`）、bash、nano、htop、tmux、git、rsync
- iperf3、tcpdump、ethtool、block-mount、e2fsprogs、parted、smartmontools

Nikki 和 UPnP 默认关闭。镜像不包含代理订阅、API Token、预设 WireGuard 密钥或预设登录密码；首次登录后必须立即设置 root 密码。

## 固定源码

ImmortalWrt 与 OpenWrt-nikki 以 Git submodule 固定到明确 commit，SHA 同时记录在 [`versions.env`](versions.env)。Mihomo 由 Nikki feed 的 OpenWrt Go 构建规则针对目标 `riscv64` 从源码交叉编译，不下载其他架构的可执行文件。

P3TERX/Actions-OpenWrt 与 wukongdaily/ImmortalWrt-ImageBuilder 仅用于参考 Actions 编排、依赖清单和镜像收集方式；它们不是构建输入，也没有复制其中的其他设备配置。参考时使用的 commit 同样记录在 `versions.env`。

克隆并初始化子模块：

```bash
git clone --recurse-submodules https://github.com/baiyunquan/immortalwrt-visionfive2-custom.git
cd immortalwrt-visionfive2-custom
git submodule update --init --recursive
```

已有普通 clone 可直接运行第二条 submodule 命令。

## 运行 GitHub Actions

在 GitHub 仓库页面打开 **Actions**，选择 **Build VisionFive 2 ImmortalWrt**，点击 **Run workflow**。也可以使用 GitHub CLI：

```bash
gh workflow run build.yml
gh run list --workflow build.yml --limit 1
```

工作流更新并安装 feeds，执行 `make defconfig` 和 `scripts/diffconfig.sh` 一致性检查，下载源码、编译、校验 gzip 与 GPT 分区表，最后上传以下文件：

- `*visionfive2*v1.3b*sdcard.img.gz`
- `*.manifest`
- `.config`
- `sha256sums`
- `expand-image.sh` 与 `image-functions.sh`

收集 artifact 时会补齐 StarFive 上游镜像缺少的备用 GPT 区域，重建备用 GPT，再执行 `gzip -t`、`sgdisk -v` 和 `parted print`。解压后的 `.img` 仅作为稀疏临时文件存在，验证结束即删除，不会上传。

## 按 SD 卡容量扩展镜像

Linux 下需要 `gzip`、`gdisk`、`parted`、`util-linux` 和 `e2fsprogs`。脚本会保留 loader 与 boot 分区，根据目标磁盘的最后可用 GPT 扇区计算 rootfs 的结束位置，然后扩展 EXT4 文件系统。

生成适合标称 16 GB SD 卡的十进制容量镜像：

```bash
./scripts/expand-image.sh input-sdcard.img.gz 16GB output-16GB.img.gz
```

`16GB` 表示 16,000,000,000 字节；如果需要 16 GiB，可使用 `16GiB`。也可以插入 SD 卡并让脚本只读取设备的精确容量，设备本身不会被此命令写入：

```bash
./scripts/expand-image.sh input-sdcard.img.gz /dev/sdX output-exact.img.gz
```

创建 loop 设备和扩展文件系统时脚本会通过 `sudo` 请求权限。若只下载了 Actions artifact，请把 `expand-image.sh` 与 `image-functions.sh` 放在同一目录后运行。为避免不同厂商“16 GB”卡的实际扇区数差异，优先使用块设备容量模式。

## 刷写 SD 卡

Linux 下先确定 SD 卡设备名。下面的 `/dev/sdX` 必须替换成整张 SD 卡，选错设备会覆盖数据：

```bash
gzip -dc immortalwrt-*-visionfive2-v1.3b-*-sdcard.img.gz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Windows 可使用 Rufus 或 balenaEtcher，直接选择下载的 `.img.gz`（若工具版本不支持 gzip，则先解压再写入）。基础镜像可写入更大的 SD 卡；若未提前扩展，rootfs 仍保持 512 MiB。面向 16 GB 及以上 SD 卡使用时，建议先在 Linux 或 WSL2 中生成与卡容量匹配的版本。

## 首次启动

保持上游 VisionFive 2 v1.3B 的网口分配不变：

- `eth0`：LAN
- `eth1`：WAN

默认主机名为 `ImmortalWrt-VF2`，时区区域为 `Asia/Shanghai`。通过 LAN 首次登录后，立即在 LuCI 的系统管理页面设置密码，或通过终端运行：

```sh
passwd
```

WireGuard 没有预置私钥、公钥或 peer；请在设备上自行生成。Nikki 没有订阅和 API secret，需手动配置后再启用。

## 本地配置检查

完整编译需要 Linux 主机和 ImmortalWrt 构建依赖。配置准备过程为：

```bash
./scripts/prepare-feeds.sh
./scripts/prepare-tree.sh
make -C upstream/immortalwrt defconfig
(cd upstream/immortalwrt && ./scripts/diffconfig.sh)
./scripts/check-config.sh
```

仓库没有重新移植 DTS，直接使用 ImmortalWrt 的 `target/linux/starfive` 与 `visionfive2-v1.3b` 设备定义。

## 仍需硬件验证

CI 只能验证可构建性、压缩流、GPT 分区表和一次 768 MiB 自动扩展。首次发布后仍需在真实 VisionFive 2 v1.3B 上验证：U-Boot/SD 启动、两网口实际映射与吞吐、按实际卡容量扩展后的 EXT4 挂载、LuCI/ttyd、Nikki/Mihomo 运行、WireGuard 隧道、重启与断电恢复，以及不同品牌 16 GB SD 卡的实际容量兼容性。
