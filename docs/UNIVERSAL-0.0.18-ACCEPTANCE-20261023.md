# Universal 0.0.18 发布与真实自动升级验收

2026-10-23：**发布链路及本机升级 PASS**。KeyPin 0.0.18 (19) 已正式公开，macOS 26+ 使用同一 Universal ZIP，同时包含 arm64 和 x86_64。本机从真实正式 0.0.17 (18) 经生产 Sparkle feed 自动下载、验证并在退出时安装为 Universal 新版。

## 发行证据

- 源码与标签：`c704cc25ca390a359abc5b98689567f755cd9eee` / [v0.0.18](https://github.com/mreasonyang/keypin/releases/tag/v0.0.18)。
- [主线 CI](https://github.com/mreasonyang/keypin/actions/runs/39931339307) 与 [Release Actions](https://github.com/mreasonyang/keypin/actions/runs/39932163542) 均通过。两条工作流安装 Rosetta、执行原生和 Intel 测试、构建并检查 Universal 包。本地两组 XCTest 各 145 项，均无失败。
- 正式 ZIP：`KeyPin-0.0.18-universal.zip`，3,357,308 字节，SHA-256 `3ac1c7cc84f0ce86e8e71fe01b78bb70a45c0f8faf82783c32415250e1bf230b`。
- Developer ID、Hardened Runtime、安全时间戳、Apple 公证、staple、Gatekeeper、Sparkle ZIP/feed 签名通过。Apple submission `c6740cb4-2c25-4c4c-9b54-be68a9c76372` 状态 Accepted。公开下载的全部 4 个资产与核验过的草稿一致。
- 主程序、Focus Helper、Sparkle、Autoupdate、Updater、Downloader、Installer 共 7 个原生组件均包含两种架构。读取 ZIP 内真实 Mach-O 的架构检查防止仅有 arm64 的包或组件混入。
- 生产 URL 和旧版验证公钥保留。新版 feed 不含仅限 arm64 的 hardwareRequirements；本机使用旧版已安装应用的公钥独立验证公开 feed 和 ZIP 成功。

## 正式包运行与升级

本机为 macOS 27.0.1、Apple silicon。原生 arm64 与 Rosetta x86_64 都运行了同一份正式签名包：CLI 帮助、真实输入源枚举及 helper 正常拒绝非焦点调用通过。Intel GUI 关于页显示 0.0.18 (19) / Intel，读取生产更新源成功。原生 GUI 设置和关于页也正常启动。

升级基线为原有 `/Applications/KeyPin.app` 正式 0.0.17 (18)，全部普通文件与符号链接匹配公开旧包。测试没有改动旧版版本号、生产 feed、公钥或签名要求，也没有手动复制新版进 Applications。

1. 临时开启自动检查和自动下载安装，备份配置、登录项和旧版；正式包在独立路径完成运行检查后关闭。
2. `09:39:33 UTC`：公开已验证的同一 0.0.18 草稿，所有公开资产与草稿一致，latest feed 返回新版。
3. 仅清除 `SULastCheckTime` 让调度到期，经未修改的原登录任务启动正式旧版；没有点击检查或安装按钮。
4. `09:40:13 UTC`：Sparkle 缓存已有本轮创建、哈希与公开 ZIP 相同的新包，以及验证过代码签名的解压载荷；Applications 仍为 0.0.17 (18)。
5. `09:40:30 UTC`：正常点击 Quit 后，只读观察器看到 Applications 变为 0.0.18 (19)，旧主进程退出。观察器没有启动程序或写入 bundle。
6. 新版全部文件和符号链接匹配正式 Universal 包，签名、Gatekeeper 和票据再次通过。配置、登录 plist、CLI 链接均保留；经原登录任务再次启动成功。
7. 安装完成后单独检查更新，生产源提示 0.0.18 已是最新。两个自动更新偏好恢复为测试前关闭，最后只保留一个已安装新版主进程，验收副本均关闭。

官网三种语言改为同一 Universal 下载，显示 Apple silicon / Intel，手机兼容性说明可换行且不再使用 9px 字号。网站校验读取主程序及全部嵌入组件的 CPU slices；不会仅凭文件名宣称 Intel 支持。正式 ZIP 直接复制已核验的公开资产，未重新打包应用。

## 验收边界

本次 Intel 运行通过 Rosetta 完成，**未在 Intel 真机运行或执行 Intel 真机自动升级**。本机成功的正式旧版升级来自 arm64 0.0.17；它验证了旧用户迁移到 Universal 的生产更新链路。

官网浏览器实际下载也完成验收：三语言的 6 个顶部/首屏入口均单击下载相同正式 ZIP。浏览器下载及解压出的应用均带 quarantine；macOS 正常弹出首次打开确认，提示 Apple 未检测到恶意软件。点击标准 Open 后，应用经 App Translocation 正常启动，关于页为 0.0.18 (19)。验收副本退出后经原登录任务恢复 Applications 中的正式新版，未绕过系统保护。真实中文候选、跨 App 输入、睡眠唤醒及其他硬件/系统条件的既有未验收项没有因此自动转为通过。本轮主要改变构建、发布、版本和分发，没有改动产品业务代码。

机器回执：[UNIVERSAL-0.0.18-ACCEPTANCE-20261023.json](UNIVERSAL-0.0.18-ACCEPTANCE-20261023.json)。本机包、快照、观察记录与截图位于忽略目录 `dist/universal-0.0.18/`；私有配置快照不提交。正式 `verification.json` 是不可变构建回执，安装验收 pending 字段由本独立报告补充，不重写已签署/已核验的发行资产。
