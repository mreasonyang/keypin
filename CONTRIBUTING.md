# 开发与贡献

[中文 README](README.md) · [English README](README.en.md)

## 构建与验证

需要带 macOS 26 SDK 的 Xcode / Swift。以下命令均在项目根目录运行。

```sh
KEYPIN_ARCH=universal ./scripts/ci.sh
```

`ci.sh` 与 GitHub CI 使用相同的测试、本地化、发布脚本检查和开发包构建流程。Universal 模式先执行本机架构测试，再用 x86_64 XCTest 驱动执行 Intel 测试，最后校验主程序、焦点辅助程序及嵌入代码均包含两个架构。Apple silicon 本机需要先安装 Rosetta；Actions 会显式安装。省略 `KEYPIN_ARCH` 时只构建本机架构，也可设置为 `arm64` 或 `x86_64`。SwiftPM 依赖通过 `Package.resolved` 固定；公开依赖下载禁用 Keychain/netrc 凭据读取。

当前应用输出到 `build/KeyPin.app`。打包先构建、嵌入 Sparkle、签名并校验，再替换当前应用；成功后清除暂存包。打包失败会恢复当前应用，不修改用户命令或登录项。请勿并发运行打包脚本。本地默认签名为 ad-hoc，未做 Developer ID 签名或公证；正式 GitHub Actions 发布流程见[发布指南](docs/releasing.md)。

代码在 [mreasonyang/keypin](https://github.com/mreasonyang/keypin) 的 `main` 分支管理。提交 PR 前运行上述检查；请勿提交构建产物、用户配置、证书或私钥。普通 CI 不读取发布凭据，正式发布只从明确的版本标签构建。

## 隔离预览

```sh
./scripts/preview.sh active zh-Hans light
./scripts/preview.sh paused en dark compact
./scripts/preview.sh secure zh-Hans light compact
./scripts/preview.sh switching en dark
./scripts/preview.sh waiting zh-Hans light
./scripts/preview.sh error en light
./scripts/preview.sh long-error en light short
./scripts/preview.sh many en light popover
./scripts/preview.sh about zh-Hans light
./scripts/preview.sh about-update-ready zh-Hans light
./scripts/preview.sh about-update-available en dark
./scripts/preview.sh about-update-failure ja light
./scripts/preview.sh first ja light
./scripts/preview.sh first-confirm ja light
./scripts/preview.sh settings ko reduced
./scripts/preview.sh many-200 en light
./scripts/preview.sh first-source-gone en light
./scripts/preview.sh first-save-retry en light
./scripts/preview.sh delayed-switch en light
```

调试预览使用内存服务，不访问用户配置、不切换输入法、不注册登录项。预览包使用独立身份，release 不含预览入口。状态还包括 `missing`、`empty`、`failure`、`first-many`、`first-save-error`、`first-login-error`。`first-confirm` 直接进入引导确认页，`long-error` 提供长错误提示和长列表。关于页预览不连接更新源。

边界预览包括 `first-empty`、`first-refresh`（刷新后出现输入法）、`first-source-gone`（确认前移除，返回刷新可恢复）、`first-save-retry` / `save-retry`（首次保存失败后重试）、`config-error`、`settings-config-error`、`settings-login-error`、`settings-busy-completes`、`retry-success`、`long-name`、`first-long-name`、`many-200` 与 `delayed-switch`。延迟切换与登录忙碌预览在启动对应操作后约 15 秒完成，便于测试中途停用与恢复；这些场景不模拟真实系统故障。

第四个参数可选 `compact`、`popover` 或 `short`：`compact` 在预览窗口中使用弹出面板布局，`popover` 打开真实菜单栏弹出面板，`short` 将高度上限设为 420 pt，便于检查小空间内的滚动与操作可达性。

本地化检查同时拒绝缺失键和未引用键。

源码测试、打包验证、已安装应用和真实跨 App 输入验收不能互相替代。

## 文档维护

- `README.md` 默认使用中文，`README.en.md` 为英文；保持章节、表格和链接对应，并在顶部提供语言切换。
- 使用方法放在 README；详细界面约定放在 [行为参考](docs/behavior.md)，命令参数与 JSON 协议放在 [CLI 参考](docs/cli.md)。
- 修改文档后检查相对链接、命令示例和两种语言的一致性；只有行为改变时才更新对应测试与验收记录。
