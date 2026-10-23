# 自动更新实机验证 — 2026-10-23

范围说明：本文件记录测试基线到 0.0.16 的补充安装检查，不作为正式发布版本间的升级验收。后续已完成[正式 0.0.16 → 远程正式 0.0.17 验证](REMOTE-AUTO-UPDATE-0.0.16-TO-0.0.17-20261023.md)，当前本机为 0.0.17 (18)。以下状态保留为当时的历史记录。

结论：**PASS。手动检查后的下载、验证、替换、重启，以及后台自动检查、自动下载、退出时安装，两条路径均通过。** 当前安装恢复为正式 KeyPin 0.0.16 (17)，两个自动更新开关恢复测试前的关闭状态。

## 测试边界和来源

- 环境：本机 macOS 27.0.1，Apple silicon；Sparkle 2.10.0。
- 更新目标：公开 [v0.0.16](https://github.com/mreasonyang/keypin/releases/tag/v0.0.16)，构建 17，固定生产 appcast 和真实 GitHub 下载 URL。
- 正式 ZIP：2,409,997 字节，SHA-256 `fdfe363910a90cedf8a0c1bafbb255f5db0c528b42d785ee0a3573bc45cfec3a`。
- 旧版测试基线：从该正式 ZIP 派生，将主应用和焦点 helper 的版本元数据改为 `0.0.15 (16)`，加入 `KeyPinUpdateTestFixture` 标记，再由 GitHub Actions 使用同一 Developer ID 证书重新签名、公证和附加票据。可执行代码来自 0.0.16；**它不是历史 0.0.15 产品实现，不能用于证明历史数据迁移兼容性。**
- [基线构建、公证与清理回执](https://github.com/mreasonyang/keypin/actions/runs/39900789252)，源提交 `c64de10698b810cd6b97db6dd508d194de9cb0c2`。测试 ZIP 的 SHA-256 为 `a850c5c9e3933ace7cb27de244da36f9df3ed2622fabf8f2d5536bf9e57138f2`。
- 基线的 bundle ID、公钥、正式 feed、解压前签名验证和签名 feed 要求均与正式版相同。安装前验证同一开发者 Team、Gatekeeper 和公证票据。签名操作仅在 Actions 临时钥匙串执行；没有导出或读取本机私钥，也没有使用 Sparkle 发布私钥。
- 测试基线只作为保留 3 天的 Actions artifact 提供，没有创建 Release、移动标签或改变正式更新源。原应用、配置和登录项先备份到本机忽略的 `dist/update-e2e-20261023/`。

## 实测结果

| 路径 | 实际操作和证据 | 结果 |
| --- | --- | --- |
| 手动检查、自更新并重启 | 从正常 Applications 路径、既有登录任务启动基线。关于页显示 0.0.15 (16)；点击检查，Sparkle 提示 0.0.16 可用；点击 Install Update，经历 Downloading update 和 Ready to Install，再点击 Install and Relaunch | PASS |
| 替换和自行重启 | 只读观察器先看到旧 PID 33506 退出，再看到文件版本变为 0.0.16 (17)、新 PID 33815 启动。观察器没有启动应用，确认是 Sparkle 自行重启 | PASS |
| 后台自动发现和下载 | 再装同一基线，开启自动检查和自动下载安装。按 Sparkle 文档清除唯一的 `SULastCheckTime` 以触发到期调度，使用正常登录任务启动。没有点击检查或安装按钮。新建的 Sparkle 缓存 ZIP 创建时间晚于本轮启动标记，大小和 SHA-256 与正式包一致 | PASS |
| 退出时自动安装 | 基线仍运行 0.0.15 (16) 时直接点击 Quit。只读观察器看到安装文件变为 0.0.16 (17)，没有点击安装按钮。按退出安装语义，完成后保持关闭；随后通过原登录任务启动成功 | PASS |
| 更新偏好保留 | 第二轮更新后，关于页两个选项仍为开启；核对后在 GUI 中依次恢复自动下载安装、自动检查为关闭 | PASS |
| 更新后再次检查 | 正式版显示 “You’re up to date! KeyPin 0.0.16 is currently the newest version available.”，没有重复提供同一版本 | PASS |

两轮更新完成后均验证：

- 测试基线标记消失，主应用及 helper 均恢复正式构建。
- **整个应用目录的所有普通文件内容和符号链接均与原正式包一致**，并通过 `codesign --verify --deep --strict`、Gatekeeper 和 staple 验证。
- 输入源目标、保持状态、界面语言和引导状态保留；登录 plist 逐字节不变；CLI 符号链接不变。
- 最终只有一个主进程，状态为 `keeping`，登录启动仍开启，自动检查和自动下载安装均恢复关闭。

## 回执和复测

机器回执：[AUTO-UPDATE-E2E-20261023.json](AUTO-UPDATE-E2E-20261023.json)。本机逐阶段 JSON、只读安装观察器、截图和原始应用备份位于 `dist/update-e2e-20261023/`，未提交用户本机备份。

截图包括 `manual-available.png`、`manual-ready.png`、`manual-updated.png`、`automatic-before-quit.png`、`automatic-updated-settings-preserved.png` 和 `final-up-to-date.png`。

可通过 `gh workflow run update-installation-fixture.yml --repo mreasonyang/keypin --ref main` 重建基线。该工作流固定源 ZIP 与目标版本；后续版本复测时，需显式更新源哈希、基线构建号和预期目标，再执行同样的两条路径。工作流只上传测试 artifact，权限为 contents:read。新增工具的 shell / YAML 解析、本机拒绝签名保护，以及 [CI](https://github.com/mreasonyang/keypin/actions/runs/39900768996) 均通过。

本次没有发现需要修改产品实现的问题。该结果覆盖本机和此版本组合的更新机制；未来真实产品版本的数据迁移、其他 macOS / 硬件环境仍需对应测试。已有 CI 中的临时密钥签名及篡改拒绝测试，与本次实际安装验证分别记录。

调度测试依据：[Sparkle SPUUpdater 的 lastUpdateCheckDate / SULastCheckTime 文档](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html)。
