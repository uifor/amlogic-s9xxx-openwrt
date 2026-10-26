# Personal OpenWrt

这是基于 [ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt) 的独立定制项目，使用上游的 Amlogic/Rockchip/Allwinner 镜像打包器，默认面向斐讯 N1。

## 默认构建内容

- OpenWrt 官方源码，默认分支：`openwrt-25.12`
- OpenWrt APK 包管理器
- `firewall4` 和纯 nftables，不安装 iptables 兼容层
- LuCI 默认主题为 Bootstrap
- Lucky
- Nikki + Mihomo Meta
- OpenList
- vlmcsd KMS
- Podman + LuCI Podman 管理界面
- Podman 默认使用 rootful 模式、netavark 网络和 nftables 防火墙，首次启动会在 p4 挂载成功且 cgroup v2 可用时启用服务
- 固件启动时自动挂载 cgroup v2，并在 cgroup v2 不可用时不启动 Podman
- Podman 容器网络使用 Aardvark DNS，仅监听容器网络地址，不会抢占旁路由 `10.0.0.2` 的系统 DNS 端口
- 保留无线驱动和固件支持，包含 N1 的 BCM43455/AP6255 无线固件
- 固件首次启动默认关闭所有无线 radio，需要时可在 LuCI 中手动启用
- 默认旁路由模式，固定管理地址 `10.0.0.2`，上游网关/DNS 为 `10.0.0.1`
- 默认后台账号 `root`，密码 `password`

## GitHub Actions

打开 `Build Personal OpenWrt`，可以填写：

- `openwrt_branch`：源码分支，例如 `openwrt-25.12` 或未来的 `openwrt-26.x`
- `openwrt_board`：默认 `s905d`，多个机型用下划线连接
- `openwrt_kernel`：默认 `6.12.y_6.18.y`
- `network_mode`：默认 `bypass`，也可以选择普通 `router` 模式
- `openwrt_ip`：管理/旁路地址，默认 `10.0.0.2`
- `network_gateway`：旁路模式上游网关，默认 `10.0.0.1`
- `network_dns`：旁路模式上游 DNS，默认 `10.0.0.1`

工作流会先编译通用 `armsr/armv8` rootfs，再调用上游打包器生成目标机型镜像。

旁路模式会在首次启动时设置静态 LAN 地址、默认网关和 DNS，并关闭 LAN DHCP、IPv6 RA/DHCPv6/代理通告。客户端仍需将网关或 DNS 按需指向 N1，旁路模式不会修改主路由器的 DHCP 配置。

Podman 默认将镜像和容器数据存放在 `/mnt/mmcblk2p4/podman`，运行时数据位于 `/run/containers/storage`。固件会把 `/dev/mmcblk2p4` 挂载到 `/mnt/mmcblk2p4`；如果该分区未挂载，Podman 会保持停止，避免把容器数据误写入系统 overlay。通过晶晨宝盒安装到 eMMC 前，安装脚本会先停止 Podman 服务和运行中的容器，再卸载相关分区。

## 主要定制入口

- `config/openwrt/config`：OpenWrt 基础配置种子
- `config/openwrt/feeds.conf.default`：官方和第三方 feeds
- `config/openwrt/diy-part1.sh`：feeds 更新前的源码处理
- `config/openwrt/diy-part2.sh`：feeds 安装后的软件包选择和配置
- `make-openwrt/openwrt-files/`：镜像打包阶段的文件覆盖

第三方插件使用源码参与编译，最终由 OpenWrt 25.12 的构建系统生成 APK。后续切换到 OpenWrt 26 时，优先只修改 Actions 中的 `openwrt_branch`。
