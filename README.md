# BiliToPiliNara

一个只负责应用间跳转的 iOS rootless 插件。在官方哔哩哔哩的竖屏视频详情页右下方增加 **PiliNara ↗** 按钮，打开 PiliNara 中的同一视频、同一分 P。

## 安装与使用

1. 从 [Releases](https://github.com/Caun1112/BiliToPiliNara/releases) 下载 `com.caun.bilitopilinara_*_iphoneos-arm64.deb`，用 Sileo / Zebra 安装。
2. 确认已安装支持独立 `pilinara://` 的 PiliNara。你现有的 [2026-10-13「B站打开」版 2.1.5+6023](https://github.com/Caun1112/PiliNara/releases/tag/fork-2.1.5-bili-open-20261013) 已支持，无需重编。
3. 从后台彻底退出哔哩哔哩，再打开视频详情页，点击 **PiliNara ↗**。
4. 在 PiliNara 点击已有的 **B站打开**，可以跳回官方 App。

普通 AV/BV 视频按当前播放器的 `cid` 打开对应分 P。缺少当前视频信息、分 P 未就绪、或多个播放器无法区分时会提示重试，避免跳到错误视频。横屏时隐藏按钮。插件没有设置页。

## 兼容性与验证范围

- iOS 15+ rootless 越狱环境；DEB 架构 `iphoneos-arm64`，动态库同时包含 arm64 / arm64e。
- 仅注入官方主客户端 `tv.danmaku.bilianime`。需要启用该 App 的插件注入。
- 类和接口依据来自声明支持 **哔哩哔哩 8.76.0** 的 BiliClean 公开源码：`BBVDDetailVC`、`BBPlayerPlayback.setCurrentItem:`、`BBPlayerPlayItem.oid/cid`。其他版本需要实际验证，接口改变时可能不显示按钮或提示读取失败。
- 本次目标为用户提供的 **9.10.0**。尚未取得该版本二进制或真机运行证据，不能将旧版接口依据视为 9.10.0 已验证兼容；安装时动态检查类与方法签名，不使用版本固定地址。
- 已验证：路由和 ID 读取的自动测试、两种架构交叉编译、rootless 目录、Substrate 依赖与加载路径、签名段、DEB 元数据。**尚未在越狱真机安装和验证按钮及跳转落点。**
- 当前功能针对普通视频详情页。番剧/影视的 EP 路由、直播、播放进度同步不在本版支持范围内。

## 两端如何对应

```text
哔哩哔哩视频详情页
  → 当前详情页内的 BBPlayerPlayback
  → currentItem.oid + currentItem.cid
  → pilinara://video/170001?cid=279786
  → PiliNara /videoV，同一视频和分 P

PiliNara 的「B站打开」
  → 官方 Universal Link，失败时使用 bilibili://
  → 官方哔哩哔哩
```

跳转时重新读取当前播放器，不缓存全局的“最后一个视频”，也不遍历推荐列表。只有 `playback.view` 位于当前详情页并且可见的播放器才能作为目标；多个候选时优先唯一的 `isGetFocus` 播放器。

本地 `/Users/caun/code/PiliNara-merge-20260910` 是旧分支，仍注册 `bilibili://`；真正包含「B站打开」及独立入站协议的版本位于 `/Users/caun/code/PiliNara`，提交 [`22587a6bf`](https://github.com/Caun1112/PiliNara/commit/22587a6bf161403b3ff41c8dccc66da052d9ffd6)。本次无需修改任何 PiliNara 源码。

## 注入原理与参考

参考 [TouchFriend/BiliBiliTweak](https://github.com/TouchFriend/BiliBiliTweak/tree/9062479df537b4f6e94f7dd8e4b8aeb174d14a42)：越狱的插件加载器读取 `DynamicLibraries` 下的 plist，按 Bundle ID 将 dylib 加载到 B 站进程；动态库初始化后通过 Substrate `MSHookMessageEx` 在原方法执行后追加行为。原工程使用 MonkeyDev / Logos，原配置为 rootful，不能把它的原包直接当作 rootless 包安装。

本项目独立实现按钮，参考 [BiliClean 的播放器与详情页关联方式](https://github.com/ahaduoduoduo/BiliClean/blob/3f621183de194f68255cb0bd1162f44614046b7a/Download/BLCVideoDownloadHooks.m) 及 [播放器 ID 接口](https://github.com/ahaduoduoduo/BiliClean/blob/3f621183de194f68255cb0bd1162f44614046b7a/Tweak.x#L2452)。没有引入原项目的广告过滤、倍速、下载等功能。相关许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本包安装到 `/var/jb/Library/MobileSubstrate/DynamicLibraries/`，按 Theos 的 rootless 方式链接 Substrate，配置 `/var/jb` 及 `.jbroot` 加载路径。App 的 SDK 头文件无需导出；私有 getter 通过返回类型检查后调用。

## 构建

macOS 需要 Command Line Tools / Xcode、iPhoneOS SDK、Theos 的 rootless Substrate stub，以及 `ldid`、`dpkg`。仓库的 GitHub Actions 会完成构建并在标签发布时上传 DEB。

```sh
make test
THEOS="$HOME/theos" make package
# 或 SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" make package
make verify
```

`packages/` 包含 DEB、SHA256SUMS 和源码提交/源文件校验记录。删除插件后重启哔哩哔哩即可恢复。
