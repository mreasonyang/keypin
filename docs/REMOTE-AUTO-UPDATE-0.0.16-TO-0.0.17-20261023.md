# 正式版本远程自动更新验证：0.0.16 → 0.0.17

2026-10-23，结论：**PASS。本机原有正式 0.0.16 (17)，从远程正式发布的 0.0.17 (18) 完成后台发现、下载、签名验证和退出时自动安装。** 随后经原登录任务启动新版，配置和登录项保留，整个应用与 GitHub 新版发行包一致。

本报告是正式发布版本间的升级验收。此前的[测试基线安装检查](AUTO-UPDATE-E2E-20261023.md)仅作为补充，不替代本轮。

## 两端均为真实正式发布包

| 项目 | 正式旧版 | 远程正式新版 |
| --- | --- | --- |
| GitHub Release | [v0.0.16](https://github.com/mreasonyang/keypin/releases/tag/v0.0.16) | [v0.0.17](https://github.com/mreasonyang/keypin/releases/tag/v0.0.17) |
| 版本 / 构建 | 0.0.16 / 17 | 0.0.17 / 18 |
| 来源 | 本机原有 Applications 安装，测试前全部普通文件及符号链接与旧版公开 ZIP 一致 | [GitHub Actions](https://github.com/mreasonyang/keypin/actions/runs/39903337069) 构建、签名、公证、staple 和 Sparkle 签署后公开 |
| 源码 | `a4b752af3925dc2d319e2421f8cd411b27ec9309` | `8851c5c40dbc7f48d0fa708554e661abf3732d73` |
| ZIP SHA-256 | `fdfe363910a90cedf8a0c1bafbb255f5db0c528b42d785ee0a3573bc45cfec3a` | `96aee3ae3730d78d2f097e1fac295eab23eb6542cda6366b7c9210ededbd89f0` |
| 测试标记 | 无 | 无 |

0.0.17 是真实公开的 stable Release，构建号递增。两个标签间 `Sources/` 没有改动，产品变更为正式 bundle 版本 / 构建号递增；本次是维护发布。测试没有修改本机旧版的版本元数据、更新地址、公钥或验证策略，也没有把新版手动复制进 Applications。

## 时间线与结果

以下时间为 UTC；本机为 macOS 27.0.1、arm64。

1. 测试前备份正式 0.0.16 和本机配置、登录项，并验证它与公开发行包逐文件一致。GUI 临时开启自动检查、自动下载安装。
2. GitHub `main` 推送新版本，CI [39903150555](https://github.com/mreasonyang/keypin/actions/runs/39903150555) 通过，创建新标签 `v0.0.17`，由正式 Release 工作流签名、公证和签署 feed。
3. `05:02:27`：固定正式 URL `https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml` 仍返回 0.0.16 / 17，已保存发布前快照。
4. `05:04:53`：0.0.17 作为 latest stable 正式公开。4 个 Release 资产无登录下载后均与 Actions 文件逐字节一致。同一固定 feed 切换为 0.0.17 / 18。
5. 保留本机旧版，按 [Sparkle 文档](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html)清除唯一的 `SULastCheckTime`，让正常启动后的调度到期，避免等待默认检查周期。没有改变版本、更新源或签名设置。
6. 经原登录任务启动 0.0.16，**没有点击检查或安装按钮**。`05:06:03`：Sparkle 缓存出现 2,409,968 字节的新 ZIP，SHA-256 匹配远程 0.0.17；缓存创建时间晚于本轮启动和远程发布时间。新版已在 Sparkle 缓存解压并通过代码签名验证，本机安装仍是 0.0.16 / 17。
7. `05:07:15`：只读观察器看到旧版主进程 PID 41153 和构建 17。正常点击 Quit 后，`05:07:19` 观察到 Applications 中版本变为 0.0.17 / 18，主进程已退出。观察器只读取版本文件和进程元数据，没有启动应用或写入 bundle。
8. 自动安装完成后，应用按“退出时安装”语义保持关闭。随后通过**未修改的原登录任务**启动成功；关于页显示 0.0.17 (18)，两个更新偏好仍为开启。事后再单独点击检查，显示 “KeyPin 0.0.17 is currently the newest version available.”，没有重复提供旧更新。
9. 在 GUI 中将两个更新开关恢复为测试前的关闭状态，保留新版运行、保持开启和登录启动开启。

## 安装后核验

- 全部普通文件内容与符号链接均匹配 GitHub 正式 0.0.17 包，非仅比较版本号。
- `codesign --verify --deep --strict`、Gatekeeper、公证票据验证均通过。
- 输入源目标、保持状态、界面语言、引导状态保留；登录 plist 逐字节不变；CLI 符号链接不变。
- 最终仅一个主进程，状态 `keeping`；当前安装为 0.0.17 (18)，无测试基线标记。
- 官网同步到同一 0.0.17 ZIP。网站源码 `d60953785c6808e8ad24fbd001c8de37fd19714b`，Cloudflare 部署 `f48191c0-e56b-4103-ab81-5caef83ff021` 和 [网站 CI](https://github.com/mreasonyang/keypin-site/actions/runs/39903983735) 通过。自定义域名及 Pages 域名分别核验 19 个公开文件，三语言页面、版本信息、ZIP 和校验和一致。

## 证据

机器回执：[REMOTE-AUTO-UPDATE-0.0.16-TO-0.0.17-20261023.json](REMOTE-AUTO-UPDATE-0.0.16-TO-0.0.17-20261023.json)。本机时间快照、下载与安装观察记录、截图和旧版备份位于忽略目录 `dist/remote-update-0.0.16-to-0.0.17/`。

关键截图为 `official-old-version.png`、`official-new-version-settings-preserved.png`、`official-0.0.17-up-to-date.png` 和 `final-official-0.0.17.png`。本结果覆盖本机与这两个正式发布版本的升级。
