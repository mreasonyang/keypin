# 0.0.21 更新后静默重启验收

2026-10-28：**正式发布、安装与生产 Sparkle 升级 PASS**。KeyPin 0.0.21 (22) 修复更新安装并重启后意外弹出独立窗口的问题。GUI 在取得单实例锁后记录已启动的构建号；已完成配置的用户在构建变化或首次迁移时只恢复菜单栏常驻。首次配置、配置读取错误、显式 `gui` / `keypin open` 和主动重新打开窗口的行为保留。

## 发布与包核验

- 发行提交：`d3bba05944e1cd7a99cbba75095f483b166d9cfa`，标签 [v0.0.21](https://github.com/mreasonyang/keypin/releases/tag/v0.0.21)。
- [主线 CI](https://github.com/mreasonyang/keypin/actions/runs/40627001505) 全部通过，包括 macOS 15 Apple silicon 与 Intel 运行任务。本地原生和 Rosetta XCTest 各 165 项通过，其中新增 6 项启动策略回归测试。
- [Release Actions](https://github.com/mreasonyang/keypin/actions/runs/40627879928) 完成 Universal 应用和 DMG 的 Developer ID 签名、Apple 公证、staple、Gatekeeper 与 Sparkle ZIP/feed 签署。macOS 最低版本保持 13.0。
- ZIP：3,413,369 字节，SHA-256 `2ffc75c63ac1a468e366f94857bd9ff5278eddf05290a2dd10e1613c1d706090`。
- DMG：4,245,639 字节，SHA-256 `e6c95b41c70f953a0baf91ecd26f956d4dd3be5dc649b9ede9d880c6758ec244`。
- 本机重新核验签名、公证票据、Gatekeeper、全部 Universal 组件、arm64/Rosetta CLI、helper 拒绝普通 CLI、更新公钥与 feed 延续。挂载 DMG 中的应用全部文件、可执行位与链接和 ZIP 相同。
- 草稿安装验收通过后公开同一草稿。匿名 HTTPS 回读全部 6 个公开资产与本机已验收资产一致，生产 latest feed 与该版本 appcast 完全一致。原始构建回执与签署资产保持不变。

## 实际安装与升级

1. 先在 Applications 安装最终草稿包。原有用户无启动构建记录，首次桌面启动产生一个正常进程，独立可见窗口数为 **0**；主动重新打开后，主面板、设置页和关于页正常，显示 **0.0.21 (22)**。
2. 恢复未经修改的公开 0.0.20 (21) 基线，其二进制与公开 ZIP 一致。草稿测试产生的构建记录还原为测试前的不存在状态；旧版版本号、更新源、公钥和签名要求均未修改。
3. 从旧版关于页检查生产更新。Sparkle 明确显示“0.0.21 可用，当前为 0.0.20”，完成下载与验证后点击 **Install and Relaunch**。新版由 Sparkle 替换并启动，本步骤没有手工复制新版来代替更新。
4. 只读观察器记录旧 PID 53248 退出、安装版本变为 0.0.21 (22)，新 PID 53445 启动。新进程在 `03:51:11 UTC` 和 `03:51:18 UTC` 的独立可见窗口数均为 **0**。
5. 用户主动重新打开应用后，主面板、设置页和关于页可用，显示 0.0.21 (22)；关闭测试窗口后仍只有一个已安装主进程，可见窗口数为 **0**。
6. 安装后的全部应用文件和链接与正式 ZIP 相同，签名、票据和 Gatekeeper 再次通过。输入法配置、登录 plist 和 CLI 链接的大小、修改时间及链接目标保持，界面仍显示原输入法目标；自动检查和自动下载安装保持关闭。

窗口计数通过只读 Window Server 元数据按精确 PID 过滤，只输出窗口数量，不读取标题、进程参数、环境或屏幕内容。已用同一进程的开窗 / 关闭状态校准 1 / 0。原生自动化读取会重新打开已关闭窗口，不能用其超时或应用目录清单证明静默启动；本轮没有将这些结果作为窗口数证据。

## 证据边界

本轮证明手动发起的生产 Sparkle 升级及升级后无独立窗口，未新增无人值守调度验收。首次配置、显式打开、构建变化及无历史记录迁移由隔离回归测试覆盖；没有改动用户的输入法保持策略。

本机为 macOS 27.0.1、Apple silicon，x86_64 使用 Rosetta；CI 的 Intel/macOS 15 运行不替代 macOS 13/14 或个人 Intel 设备的交互验收。本轮未重新验收真实中文候选、持续跨 App 输入或睡眠唤醒。

机器回执：[QUIET-UPDATE-0.0.21-ACCEPTANCE-20261028.json](QUIET-UPDATE-0.0.21-ACCEPTANCE-20261028.json)。逐阶段本机证据与旧版备份保存在忽略目录 `dist/quiet-update-0.0.21/`。
