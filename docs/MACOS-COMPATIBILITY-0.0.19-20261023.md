# macOS 13 兼容与 0.0.19 发布验收

2026-10-23：KeyPin **0.0.19 (20)** 已正式发布，安装与编译下限从 macOS 26 降至 **macOS 13.0**。Universal ZIP 同时包含 Apple silicon 与 Intel。发布、macOS 15 CI 运行、本机应用内升级和官网分发均通过；macOS 13/14 实际系统运行验收仍待完成。

## 兼容实现

- macOS 26+ 保留 Liquid Glass；旧系统使用现有普通表面和原生 bordered / borderedProminent 按钮。
- 为 macOS 14 的窗口激活、状态图标动画、snappy 动画及 onChange API 添加兼容路径；为 macOS 15 的颜色混合和 macOS 13.3 的安全区域配置提供保护。
- 主程序与 Focus Helper 的两种 Mach-O 架构都以 13.0 为最低系统版本；Sparkle 的五个原生组件均为 12.0。较新的 Symbols 框架在两种架构中均为弱链接。
- 打包与网站校验读取每个 Mach-O slice 的部署版本，拒绝高于应用声明的组件。辅助程序 Info.plist 继承主程序要求；生产 appcast 为 13.0。官网三语言的首屏、下载区与 FAQ 从正式 ZIP 的 Info.plist 生成最低版本说明。

## 构建与运行证据

源码和标签：`ae9be589d435ca46ccef252b72e40257f385d2a4` / [v0.0.19](https://github.com/mreasonyang/keypin/releases/tag/v0.0.19)。

[CI 39941198881](https://github.com/mreasonyang/keypin/actions/runs/39941198881) 全部通过：

| 环境 | 已完成检查 |
| --- | --- |
| macOS 26 构建 runner | 原生与 x86_64 XCTest 各 145 项；Universal 打包、发布脚本、本地化、Sparkle 验证 |
| macOS 15.7.9 arm64 runner | 运行同一份 macOS 26 构建的应用；CLI、辅助程序拒绝错误入口；五语言明暗模式共 20 个隔离窗口渲染 |
| macOS 15.7.9 x86_64 runner | 同上，使用原生 Intel runner 执行 |
| 本机 macOS 27.0.1 / Apple silicon | 两组测试各 145 项；20 个兼容样式窗口渲染；手动完成引导与主面板检查；正式包原生 / Rosetta CLI 和辅助程序检查；正式 GUI 关于页 |

CI 中的窗口检查使用 debug 预览和内存服务，检查窗口创建、尺寸与绘制，不操作真实输入法或登录项。预览等待应用启动完成后才进入确认页，避免启动时序导致错误验收。

## 正式发行

[Release Actions 39942036974](https://github.com/mreasonyang/keypin/actions/runs/39942036974) 再次通过全套检查，并完成 Developer ID、Hardened Runtime、安全时间戳、Apple 公证、staple、Gatekeeper 和 Sparkle ZIP/feed 签名。

- Apple submission：`11cc353f-129f-4ba1-9033-d764058873a5`，Accepted。
- 正式文件：`KeyPin-0.0.19-universal.zip`，3,391,606 字节。
- SHA-256：`debed27184c7c8c72fec80be4c5d9be8a30910d0d418ab96b73a96b1acf046fd`。
- 公开时间：`2026-10-23T11:03:01Z`。四个公开资产逐字节匹配已验证草稿，latest feed 返回 0.0.19 / macOS 13.0。
- 本机正式包签名、Gatekeeper 和 stapled ticket 验证通过；关于页显示 0.0.19 (20) / macOS 13.0。旧版更新 URL 与验证公钥保持一致。

## 真实升级与官网

以 `/Applications/KeyPin.app` 中未经修改的正式 0.0.18 为基线，使用「Check for Updates → Install Update → Install and Relaunch」通过生产 Sparkle 更新源安装 0.0.19。没有把新版手工复制进 Applications。升级后全部普通文件和符号链接与正式包一致，配置、登录 plist、CLI 链接均保留。自动检查和自动安装仍为原先关闭状态。已安装新版正常重启，签名与 Gatekeeper 再次通过。

官网源码为 `e87de926c9c97e159274c22e5f3ae10e36bd98f8`，[网站 CI](https://github.com/mreasonyang/keypin-site/actions/runs/39943700115) 与 Cloudflare Pages 部署 `7bc8f618-ce1b-4410-af26-b275cdf4e4c2` 均成功。线上 23 个公开文件验证通过，HTML 仅有已记录的 Cloudflare Analytics 插入，其余内容匹配本地发布清单。内置 Browser 分别点击三种语言的首屏下载按钮，三份 ZIP 均为上述正式哈希，并带有系统 quarantine 属性。

[官网](https://keypin.kyun.si/) 已显示 macOS 13+，下载、版本号、最低系统要求和正式包一致。

## 证据边界

**macOS 13/14 尚未在实际系统上运行验收。** 编译可用性检查、最低部署版本、macOS 15 运行成功，不替代这两个版本的实际运行证据。Intel runner 运行也不等同于个人 Intel Mac 的完整使用验收。真实中文候选、组合输入、跨 App 连续输入、Secure Input 和睡眠唤醒等完整实机回归仍未在本轮完成。

正式 verification.json 保留构建阶段的 installationAcceptance=pending；后续安装证据由本报告补充，不改写不可变发行资产。

机器回执：[MACOS-COMPATIBILITY-0.0.19-20261023.json](MACOS-COMPATIBILITY-0.0.19-20261023.json)。本机包、截图和私有配置快照位于忽略目录 `dist/macos-compatibility-0.0.19/`；网站回执与截图位于相邻网站仓库的 `dist/`，私有配置不提交。
