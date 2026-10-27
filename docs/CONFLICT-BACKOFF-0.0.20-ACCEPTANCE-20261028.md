# 0.0.20 冲突退让发布与应用内升级验收

2026-10-28：**正式发布、安装与生产 Sparkle 升级 PASS**。KeyPin 0.0.20 (21) 已公开，安装包保持 macOS 13+、Universal arm64 / x86_64。此版本限制同一 App 内短时间的反复自动切回，并在面板说明暂缓原因及提供重试。

## 发布证据

- 发行提交：`c2d3a185ea40e460974e9ed2f395818725f4feac`，标签 [v0.0.20](https://github.com/mreasonyang/keypin/releases/tag/v0.0.20)。
- [主线 CI](https://github.com/mreasonyang/keypin/actions/runs/40560640994) 通过，包括原生/Rosetta 检查和 macOS 15 Apple silicon、Intel 运行任务。本地对发行提交运行 159 项 XCTest，零失败。
- [Release Actions](https://github.com/mreasonyang/keypin/actions/runs/40562196676) 完成应用与 DMG 的 Developer ID 签名、Apple 公证、staple、Gatekeeper；应用和 feed 的 Sparkle 签名验证通过。
- ZIP：`KeyPin-0.0.20-universal.zip`，3,408,556 字节，SHA-256 `03cd4d9ab3a7005181bc4b652393f3560c593731e4a68a8b26110f408bebb0be`。
- DMG：`KeyPin-0.0.20-universal.dmg`，4,240,822 字节，SHA-256 `a3c4391a9a7634fa84752886fc7391950ded8eb8b66657082245a81c412cd0fc`。
- 已下载并核对草稿资产，公开后匿名 HTTPS 重新下载六个资产并比较字节；生产 latest feed 为 build 21。独立 DMG checksum 由已验证的官方 DMG 生成，与原始 SHA256SUMS 一致。

## 安装与更新

1. 挂载最终 DMG，核对 Applications 快捷方式、Finder 背景及应用全部文件/链接/可执行位与 ZIP 一致。应用及 DMG 的签名、票据、Gatekeeper 在本机再次验证；同一正式包的 arm64 和 Rosetta CLI，以及 helper 拒绝普通 CLI 调用均通过。
2. 正式草稿包在 Applications 安装后，原生设置页与关于页正常，显示 0.0.20 (21)，输入法设置、登录项与 CLI 符号链接的元数据保留。
3. 使用公开 0.0.19 ZIP（原 SHA-256 `debed27184c7c8c72fec80be4c5d9be8a30910d0d418ab96b73a96b1acf046fd`）恢复真实旧版基线，核对可执行文件与公开旧包一致。未修改旧版版本号、feed、公钥或签名要求。
4. 从旧版关于页检查生产更新，Sparkle 显示“0.0.20 可用，你当前为 0.0.19”；点击安装更新，下载与验证后显示 Ready to Install。
5. 点击 Install and Relaunch，由 Sparkle 退出旧进程、替换应用并重启。只读观察器确认版本从 0.0.19 (20) 变为 0.0.20 (21)，安装后主程序与正式 ZIP 相同，新进程及原生关于页验证通过。测试没有手工将新版复制进 Applications 来代替这一步。
6. 最终应用签名、票据与 Gatekeeper 通过；保持配置、登录 plist 和 CLI 链接的大小/修改时间/链接目标与测试前一致。登录启动保持开启，自动检查及自动下载安装保持关闭，只保留一个已安装主进程。

## 证据边界

反复争抢、通知回声、helper 冷却/失败、逐级退让、App/目标切换及手动恢复由确定性测试覆盖。本次没有重新诱发并归因用户此前遇到的真实争抢，也没有新增人工真实中文候选、长时间连续跨 App 输入或睡眠唤醒验收。

本机为 Apple silicon，x86_64 运行使用 Rosetta；CI 的 Intel 运行不能替代个人 Intel 电脑的交互验收。macOS 13/14 实际系统交互仍未验收。本次为手动检查并启动安装的生产 Sparkle 升级，未新增无人值守自动调度验收，也未改变自动更新偏好。

官方不可变 `verification.json` 仍保留构建时的 installationAcceptance 字段；本独立验收补充最终安装与升级结果，不覆盖已签署的 feed、ZIP 或官方构建回执。

机器回执：[CONFLICT-BACKOFF-0.0.20-ACCEPTANCE-20261028.json](CONFLICT-BACKOFF-0.0.20-ACCEPTANCE-20261028.json)。
