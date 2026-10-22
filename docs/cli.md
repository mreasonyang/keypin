# 命令行与配置参考

[返回中文 README](../README.md) · [English README](../README.en.md)

## 命令入口

以下命令在项目根目录运行。先用应用包内的可执行文件列出本机输入源，无需安装命令入口：

```sh
"./build/KeyPin.app/Contents/MacOS/keypin" list
"./build/KeyPin.app/Contents/MacOS/keypin" status --json
```

如果应用已移到其他位置，请相应修改路径。只有需要同时启用保持、登录启动和终端入口时，才使用 `install`。例如，确认 `list` 中存在 ABC 后：

```sh
"./build/KeyPin.app/Contents/MacOS/keypin" install com.apple.keylayout.ABC
"$HOME/.local/bin/keypin" status
```

请先把应用放到准备长期使用的位置，再从该位置执行 `install`；登录项和命令链接会记录它的路径。如果 `~/.local/bin` 已在 `PATH` 中，可直接使用 `keypin`。下面的示例使用这个短名称；未安装入口时继续使用应用包内的完整路径。`<input-source-id>` 需要替换为 `list` 返回的真实 ID。

```sh
keypin status
keypin list
keypin pause
keypin resume
keypin toggle
keypin set <input-source-id>
keypin apply
keypin open
keypin install <input-source-id>
keypin uninstall
keypin help
```

不带参数等同于 `status`。`pause`、`resume`、`toggle` 只修改保存的保持意图，保留目标、语言和配置完成状态；`toggle` 在同一配置事务内完成读取和修改。启用前校验目标，目标缺失或不可用时拒绝修改。`pause` 不执行输入法切换。

这三个命令不会启动 GUI。已有应用通过配置通知响应；如果应用未运行，`resume` 仍可成功保存 `enabled=true`，但返回 `running=false`、`state=stopped`。需要启动时显式执行 `keypin open`，或使用登录启动。

`set` 保存目标并切换一次，完成配置引导，同时保留原有 `enabled` 值；命令行单次选择不会像主面板选择那样自动启用保持。`apply` 再切换一次；安全输入、目标缺失或系统拒绝切换时返回失败。`install <id>` 开启保持、完成配置引导、注册并启动登录项，同时建立 `~/.local/bin/keypin`。命令路径被其他文件或不同目标的链接占用时拒绝覆盖。`set` 和 `install` 先保存选择，再切换或注册登录项；后续操作失败不会回滚已保存的选择。

`uninstall` 取消登录启动并停止已注册的后台实例，保留配置和 CLI 链接。界面的登录开关只管理登录启动，关闭时不退出当前应用。

### JSON 输出

除 `help` 外，上述每个命令都支持一次 `--json`，可放在命令前或后。未知命令、重复选项和多余参数都会被拒绝。

```sh
keypin status --json
keypin list --json
keypin pause --json
keypin resume --json
keypin toggle --json
keypin set <input-source-id> --json
keypin apply --json
keypin open --json
keypin install <input-source-id> --json
keypin uninstall --json
```

成功退出码为 `0`，失败为 `1`。JSON 模式将单个 JSON 对象写入标准输出，包括失败结果；普通文本模式将错误写入标准错误。脚本应判断 `ok` 和 `error.code`，不要匹配本地化提示。

状态及操作成功结果示例：

```json
{
  "schemaVersion": 1,
  "ok": true,
  "command": "resume",
  "status": {
    "enabled": true,
    "running": false,
    "state": "stopped",
    "current": { "id": "com.apple.keylayout.ABC", "name": "ABC" },
    "target": { "id": "com.apple.keylayout.ABC", "name": "ABC", "available": true },
    "loginEnabled": false,
    "onboardingCompleted": true
  }
}
```

`enabled` 是保存的保持意图；`running` 来自 GUI 实例锁的只读探测，登录项已登记或辅助进程存在都不代表 GUI 正在运行。`state` 是配置、系统输入法、安全输入和进程存活状态的即时快照，**没有通过 IPC 读取 GUI 的瞬时切换任务或最近错误**：例如尚未切回时返回 `waiting`，不能据此区分 GUI 正在重试还是刚发生失败。配置无法读取时返回错误对象，而非成功状态。

未选择目标时省略 `target`；目标不可用时 `available=false` 并省略其 `name`。`list --json` 返回 `sources` 数组，元素为 `{ "id": "…", "name": "…" }`，不返回 `status`。名称可随系统语言变化，状态和错误代码是固定英文值。

失败结果示例：

```json
{
  "schemaVersion": 1,
  "ok": false,
  "command": "resume",
  "error": {
    "code": "no_target",
    "message": "No input source is selected. Use keypin set <source-id> first."
  }
}
```

常见错误代码包括 `invalid_arguments`、`invalid_config`、`no_target`、`missing_source`、`runtime_unavailable`、`config_write_failed`；一次性切换还可能返回 `secure_input`、`busy`、`switch_failed`，打开或安装相关操作使用 `not_app_bundle`、`open_failed`、`install_failed`、`uninstall_failed`。命令成功表示本次请求已完成，是否正在保持应同时检查返回状态。`open` 成功表示系统已接受打开请求，紧接着的快照不承诺应用已经启动完成。

### 本机路径

- 应用与 LaunchAgent：`app.keypin`
- 配置：`~/Library/Application Support/KeyPin/config.json`
- 登录项：`~/Library/LaunchAgents/app.keypin.plist`
- 命令：`~/.local/bin/keypin`

配置包含可选 `sourceID`、`enabled`、可选 `language` 和必需的 `onboardingCompleted`。不存在配置时使用全新状态；损坏或不完整的配置会报错并保留原文件。配置更新采用跨进程文件锁和原子写入。
