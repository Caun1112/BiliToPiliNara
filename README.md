# BiliToPiliNara

一个只负责应用间跳转的 iOS rootless 插件。在官方哔哩哔哩的视频详情／全屏播放页增加圆形 **P↗** 按钮，在 PiliNara 下载同一视频、同一分 P 的 480P，完成后自动弹出分享／保存面板。按钮直径 44 点，整体不透明度为 50%。

## 安装与使用

1. 从 [Releases](https://github.com/Caun1112/BiliToPiliNara/releases) 下载 `com.caun.bilitopilinara_*_iphoneos-arm64.deb`，用 Sileo / Zebra 安装。
2. 先安装[配套的一键 480P 下载版 PiliNara](https://github.com/Caun1112/PiliNara/releases/tag/fork-2.1.6-auto480-20261018)，它支持 `action=download` 下载指令。
3. 从后台彻底退出哔哩哔哩，再打开视频详情页，点击圆形 **P↗**，会直接进入 PiliNara 下载页并启动当前分 P 的 480P 任务。
4. 下载完成后会弹出系统分享面板，可保存视频或分享给其他 App。PiliNara 视频页原有 **B站打开** 仍可跳回官方 App。

普通 AV/BV 视频按当前播放器的 `cid` 下载对应分 P。每次点击带有独立请求 ID，避免重复处理。缺少当前视频信息、分 P 未就绪、或多个播放器无法区分时会提示重试，避免跳到错误视频。插件没有设置页。

## 固定位置

- 普通详情页、评论列表、评论弹层和全屏播放统一使用同一个内容窗口按钮。
- 圆形按钮直径 44 点，整体不透明度 50%；位于窗口安全区右侧 12 点，中心固定为当前窗口自上而下 60%。横屏旋转后按横屏窗口尺寸计算相同的相对位置。
- 按钮直接挂在内容 `UIWindow` 上；页面滚动、点赞控件位置、弹层尺寸和键盘布局不参与定位。纵向安全区变化也不会把按钮向上推。
- 点击时从内容窗口重新读取当前可见播放器，评论弹层不再被误当成播放器所属页面。离开视频上下文或切到后台时隐藏按钮。


## 兼容性与验证范围

- iOS 15+ rootless 越狱环境；DEB 架构 `iphoneos-arm64`，动态库同时包含 arm64 / arm64e。
- 仅注入官方主客户端 `tv.danmaku.bilianime`。需要启用该 App 的插件注入。
- 类和接口依据来自声明支持 **哔哩哔哩 8.76.0** 的 BiliClean 公开源码：`BBVDDetailVC`、`BBPlayerPlayback.setCurrentItem:`、`BBPlayerPlayItem.oid/cid`。其他版本需要实际验证，接口改变时可能不显示按钮或提示读取失败。
- 本次目标为用户提供的 **9.10.0**。尚未取得该版本二进制或真机运行证据，不能将旧版接口依据视为 9.10.0 已验证兼容；安装时动态检查类与方法签名，不使用版本固定地址。
- 已验证：路由和 ID 读取、窗口固定位置／横竖屏／评论弹层／键盘安全区／坐标转换的自动检查、两种架构交叉编译、rootless 目录、Substrate 依赖与加载路径、签名段、DEB 元数据。**尚未在越狱真机安装和验证按钮及跳转落点。**
- 当前功能针对普通视频详情页。番剧/影视的 EP 路由、直播、播放进度同步不在本版支持范围内。

## 两端如何对应

```text
哔哩哔哩视频详情页
  → 当前详情页内的 BBPlayerPlayback
  → currentItem.oid + currentItem.cid
  → pilinara://video/170001?cid=279786&action=download&quality=32&share=1&request_id=UUID
  → PiliNara /download，同一视频和分 P 的严格 480P 下载
  → 完成后弹出系统分享／保存面板

PiliNara 的「B站打开」
  → 官方 Universal Link，失败时使用 bilibili://
  → 官方哔哩哔哩
```

跳转时重新读取当前播放器，不缓存全局的“最后一个视频”，也不读取推荐列表的数据。只有 `playback.view` 位于当前前台播放页、没有被父视图隐藏或裁剪到屏幕外的播放器才能作为目标；多个候选时优先唯一的 `isGetFocus` 播放器。

配套 PiliNara 会重新校验视频与 CID，并检查服务器返回的真实 480P 轨道。没有 480P 时明确提示；已完成或进行中的同画质任务可复用，暂停／失败／重启恢复的任务可继续；已有其他画质缓存会保留并提示处理。此次自动操作不修改手动下载的默认画质。

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
