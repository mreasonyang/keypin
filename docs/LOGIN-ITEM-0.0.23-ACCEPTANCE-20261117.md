# 0.0.23 登录项名称发布验收

2026-11-17：KeyPin **0.0.23（24）正式发布、最终包安装及生产 Sparkle 升级通过**。

旧版独立 LaunchAgent 缺少 `AssociatedBundleIdentifiers`，macOS 因而显示签名开发者 `YANHUA YU`。新版创建登录项时关联 `app.keypin`；GUI 取得单实例锁后，也会为指向当前应用、尚无关联信息的旧登录项补全该字段。

## 构建与分发

- 发行提交：`ecc93bb39fe164d7884ffc668c68f85774b5a750`；[正式版本 v0.0.23](https://github.com/mreasonyang/keypin/releases/tag/v0.0.23)。
- [CI](https://github.com/mreasonyang/keypin/actions/runs/44001216344) 的原生及 Intel 两组各 195 项测试、Universal 打包、macOS 15 Apple silicon/Intel 运行检查全部通过。本机原生 195 项测试及 Universal 包检查通过；本机未安装 Rosetta，Intel 运行证据来自云端。
- [Release Actions](https://github.com/mreasonyang/keypin/actions/runs/44002289258) 完成应用与 DMG 的 Developer ID 签名、Apple 公证、票据、Gatekeeper 和 Sparkle ZIP/feed 签署。
- DMG：4,587,102 字节，SHA-256 `877eff51f546ad5295d07f37c1c137bd6657839698a2ae862684ddbe5a9ffe74`。
- ZIP：3,715,234 字节，SHA-256 `248bb6c31135d5405384426058e94d99c70de81f59bf1e7aff59a9ae37f25816`。
- 下载草稿重验全部 manifest 哈希、Universal 组件、签名、票据及 Gatekeeper；挂载 DMG 内的应用与 ZIP 文件、链接、可执行位一致。更新公钥及生产 feed 保持原值。公开后匿名 HTTPS 回读资产与验收字节一致，生产 latest feed 与本版本 appcast 一致。

## 旧配置与正式安装

1. 本机旧配置和系统设置均复现开发者名。使用同一份已提交迁移代码，仅补全应用关联后，系统设置立即显示 **KeyPin**；原后台 PID、自启动启用状态和输入法配置不变。
2. 恢复缺少关联字段的旧登录配置，从已验收 DMG 安装正式应用。新版首次 GUI 启动自动补全关联，系统设置显示 KeyPin，关于页显示 0.0.23（24）。配置、CLI 和更新偏好保留。
3. 迁移测试覆盖已禁用但仍加载的任务、未安装状态、已有自定义关联、另一安装路径、符号链接及损坏配置。迁移保留其他字段和原 plist 格式，不启用或重载任务，不创建 CLI 链接；重复执行不改写已有归属。

## 生产更新

恢复与公开 ZIP 完全一致的 0.0.22（23）及原始旧登录配置，通过其关于页检查生产 feed。Sparkle 显示 0.0.23，随后通过 Install Update、Install and Relaunch 完成真实下载、验证、安装与重启。新版自动迁移登录项，系统设置再次显示 KeyPin，关于页显示 0.0.23（24）。

升级后的应用与公开 ZIP 的全部文件、链接和可执行位一致，签名、票据及 Gatekeeper 再验通过。输入法配置、CLI、自启动禁用覆盖状态及自动更新偏好保留。只运行一个原生 GUI 进程。

## 证据边界

没有登出或重启用户会话；登录状态与迁移的禁用状态由实际配置检查及隔离测试核验。本轮未新增 macOS 13/14 实机、实体 Intel、无人值守更新、真实中文候选/组合输入或长时间跨 App 输入验收。原始用户配置、偏好和诊断日志未上传。

机器回执：[LOGIN-ITEM-0.0.23-ACCEPTANCE-20261117.json](LOGIN-ITEM-0.0.23-ACCEPTANCE-20261117.json)。本机逐阶段产物位于忽略目录 `dist/login-item-release-0.0.23/`。
