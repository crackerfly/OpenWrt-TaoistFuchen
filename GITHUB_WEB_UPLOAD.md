# 通过 GitHub 网页上传并编译

本项目可以直接通过 GitHub 网页上传到 repository，再由 GitHub Actions 编译，无需在本机
安装 OpenWrt SDK。

## 1. 解压源码包

先在电脑上解压交付的源码 ZIP，然后进入解压得到的外层目录。需要上传的是该目录**内部
的全部内容**，不要把 ZIP 文件本身作为一个文件上传，也不要把外层目录再套进仓库。

## 2. 上传到仓库根目录

在 GitHub repository 页面选择 **Add file → Upload files**，上传解压目录内部的所有文件
和文件夹。`.github` 是隐藏目录，必须确认它也出现在待上传列表中。

提交前检查以下路径直接位于仓库根目录：

```text
.github/workflows/build.yml
luci-app-taoistfuchen/
README.md
```

错误结构示例：

```text
OpenWrt-TaoistFuchen-v2.1.0/.github/workflows/build.yml
```

如果 `.github/workflows/build.yml` 多套了一层目录，GitHub 不会识别该 workflow。

## 3. 启动 Actions

上传提交到 `main` 或 `master` 后，`Build OpenWrt Package` 会自动运行。也可以进入
**Actions → Build OpenWrt Package → Run workflow** 手动启动。

workflow 会：

1. 恢复 GitHub 网页上传丢失的可执行权限；
2. 校验第三方二进制来源与项目回归测试；
3. 下载并校验固定 SHA-256 的 OpenWrt 25.12.5 `mediatek/mt7622` 官方 SDK；
4. 只选择本插件及当前 SDK 必须的构建闭包；
5. 编译并核验 APK 架构、版本、维护者、URL 与精确依赖元数据；
6. 上传恰好一个主 APK，不上传 SDK 内部临时生成的依赖 APK。

## 4. 下载和安装

在成功的 Actions run 页面底部下载 artifact：

```text
luci-app-taoistfuchen-25.12.5-mediatek-mt7622
```

artifact 中用于安装的文件只有：

```text
luci-app-taoistfuchen-2.1.0-r2.apk
```

其他许可证、来源说明和 `FakeHTTP`/`FakeSIP` 源码归档用于 GPL 合规，不需要安装。

把主 APK 复制到路由器 `/tmp` 后执行：

```sh
apk update
apk add --allow-untrusted /tmp/luci-app-taoistfuchen-*.apk
```

只安装主 APK 即可。OpenWrt 25.12.5 的 `apk` 会根据 APK 元数据自动下载 `luci-base`、
`cgi-io`、`nftables`、`kmod-nft-queue`、`coreutils-stat`、`coreutils-od`、
`libnetfilter-queue1` 及递归依赖（例如 `kmod-nft-core`、`libnfnetlink0`、`libmnl0`）。
不要从 Actions artifact 手工安装一组依赖 APK。

自动下载的前提是路由器软件源可用，并且目标固件的架构、OpenWrt 版本和内核 ABI 与官方
25.12.5 `mediatek/mt7622` 匹配。自编译内核可能使用不同的 kernel hash，届时官方 kmod
会被拒绝，需要改用与该固件完全匹配的软件源或在固件中内置模块。
