# KeyPin 0.0.16 (17) 发布与验证

日期：2026-10-23，Asia/Shanghai。结论：**0.0.16 已正式发布，官网已同步同一签名、公证安装包。公开下载、固定更新源、手动自更新与后台自动下载安装均通过实机验证。** 未完成的实机项目保留为后续验证，详见下表。

## 固定发行包

| 项目 | 证据 |
| --- | --- |
| 源码 | `a4b752af3925dc2d319e2421f8cd411b27ec9309`，标签 `v0.0.16` |
| 版本 / 构建 | `0.0.16` / `17`，macOS 26+，arm64 |
| CI | [39838045534](https://github.com/mreasonyang/keypin/actions/runs/39838045534)，通过 |
| Release 流程 | [39838479254](https://github.com/mreasonyang/keypin/actions/runs/39838479254)，签名、公证及草稿上传后重新下载验证均通过 |
| 发布 ZIP | `KeyPin-0.0.16-arm64.zip`，2,409,997 字节 |
| SHA-256 | `fdfe363910a90cedf8a0c1bafbb255f5db0c528b42d785ee0a3573bc45cfec3a` |
| Apple 公证 | `Accepted`，提交 ID `2cffbbb6-c650-4f9d-a60b-351de7e603d4` |
| 本机环境 | macOS `27.0.1`，arm64。GitHub 构建和测试使用 `macos-26`；未在本机 macOS 26 做 GUI 验收 |

`verification.json` 随发行包分发，只记录公开构建信息和已经通过的发行工具检查，`installationAcceptance` 保留构建时的 `pending`。它不是完整实机验收回执，公开后没有修改已验证的发行文件。

## 已完成

- CI：145 项 Swift 单测、30 项发布预检和 bundle 模式检查、15 个隔离打包场景、5 种语言各 127 个键，以及 Sparkle 官方工具签名和篡改拒绝检查通过。合成测试使用临时密钥，不代表实机升级。
- 真实发布凭据：Developer ID 证书可用于签名，Apple 公证凭据可用，Sparkle 私钥与公钥匹配。签名包含 Hardened Runtime 和安全时间戳；票据附加、解压后票据及 Gatekeeper 检查通过。
- 本机下载复核：通过 GitHub CLI 下载草稿，校验 ZIP、appcast 和验证回执的 SHA-256。另用应用中包含的公钥和 CryptoKit 验证下载的 ZIP 与 appcast，并确认内存中的篡改副本被拒绝，未读取私钥或本机钥匙串。
- Brave 真实下载：登录维护者账号访问草稿，保存 ZIP 到 Downloads；文件大小和 SHA-256 与 Actions 产物一致，存在 Brave 的下载隔离标记。这不是匿名用户访问公开 Release 的验证。
- 首启：保留下载隔离信息的解压副本通过 Gatekeeper。macOS 出现正常的“从互联网下载”确认，明确显示 Apple 检查未发现恶意软件；确认后应用运行并显示真实主窗口。首次运行曾进入 App Translocation，连接实际运行路径后可访问窗口。
- 系统默认 ZIP 应用是 MacZip。Finder 打开 ZIP 会进入预览，点击 Extract All 后得到应用；该解压器输出的应用没有 quarantine 属性。它与保留 quarantine 的 `ditto --qtn` 首启测试分别记录，不能混称为 Archive Utility 解压。
- 安装：将浏览器下载并经 MacZip 解压的同一安装包安装至 `/Applications/KeyPin.app`。签名、公证、版本和架构再次验证通过。关于页显示 `0.0.16 (17)`，两个自动更新选项默认关闭。
- 登录项：GUI 关闭登录启动时当前应用仍运行；恢复后 plist 指向 `/Applications/KeyPin.app/Contents/MacOS/keypin background`。退出 GUI 后通过 `launchctl kickstart` 启动该登录任务，确认真实进程运行并恢复 `keeping`。这不是注销、登录或重启测试。
- CLI 入口已迁移到 Applications 中的已安装应用。输入法目标、保持开关、语言和引导标记与测试前一致。
- 真实 Secure Input：聚焦 Brave 本地测试页的空白密码字段后，CLI 状态为 `secure_input`，`apply --json` 返回同名错误；移开焦点后恢复 `keeping`。测试未输入密码。
- 真实面板选择：ABC 和 Squirrel 之间切换后，面板及系统输入源 ID 一致；从 ABC 回到 Squirrel 时签名焦点 helper 正常完成。此证据只确认输入源切换，不证明中文候选和组合输入正常。
- 中文输入对照探针：对最终安装包保持开启与暂停两种状态，均在新建 TextEdit 文稿中通过电脑交互工具逐键发送 `n`、`i`；两组都只得到 ASCII `ni` 和系统英文建议，没有触发中文候选。测试后已恢复保持开启，Squirrel 目标和登录项不变。该对照说明当前自动化路径不能提供中文输入验收证据；它既不是中文输入通过的证据，也不足以认定是 KeyPin 缺陷。对照文稿保存于本机忽略的 `dist/release-acceptance-20261023/input-probe-control-20261023.rtf`。
- 原生更新入口可启动 Sparkle。发布前没有公开 stable Release，固定 latest feed 曾返回获取错误。发布后检查已显示最新版本，并完成[两条完整更新安装路径](AUTO-UPDATE-E2E-20261023.md)：签名旧版测试基线 0.0.15 (16) 经手动检查、下载、验证、替换并自行重启到正式 0.0.16 (17)；另一轮不点击检查 / 安装按钮，后台自动下载并在正常退出时安装。两轮更新后整个应用目录匹配正式包，配置、登录项和 CLI 保留，最终两个自动更新选项恢复关闭。基线来自相同可执行代码，不代表历史产品数据迁移验收。

## 正式发布

- [GitHub Release v0.0.16](https://github.com/mreasonyang/keypin/releases/tag/v0.0.16) 已于 `2026-10-23T03:47:35Z` 公开，`draft=false`、`prerelease=false`，并设为 latest stable。ZIP、appcast、校验和和构建验证回执 4 个资产全部通过无登录下载核验，与签名构建产物逐字节一致。
- 固定更新源 `https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml` 返回 HTTP 200，版本 `0.0.16` / 构建 `17`，签名 feed 和包哈希保持不变。
- [官网](https://keypin.kyun.si/) 已通过原生 GitHub 集成部署。网站生产源码为 `e12beae40fdfc12e44219645409b463333f0fc55`，Cloudflare 部署 `22920432-f850-440b-b7bb-7f3cf723ee53` 成功，[GitHub 云端验证](https://github.com/mreasonyang/keypin-site/actions/runs/39897018451)通过。
- 官网自定义域名与 `https://keypin-site.pages.dev` 均通过 17 个公开文件的匿名核验，包含三语言页面、`release.json`、真实 ZIP 和校验和。官网与 GitHub 的下载 SHA-256 均为本记录中的 `fdfe3639…cfec3a`。
- 公开分发回执：[RELEASE-PUBLICATION-20261023.json](RELEASE-PUBLICATION-20261023.json)。后续实机项目不记录为通过，也不改变本次已执行的正式发布。

## 后续实机验证

| 项目 | 当前状态 / 完成标准 |
| --- | --- |
| 中文候选与组合输入 | 尚未完成。TextEdit 键盘探针仅得到 ASCII 文本，没有形成真实候选；现有证据不足以区分工具、输入法内部模式和产品因素。需在最终安装包下，用物理键盘分别在 TextEdit、常用终端、编辑器和 Brave 输入中文，核对候选、提交、退格及组合输入期间切换应用不丢字、不抢焦点 |
| 系统快捷键与跨 App 恢复 | 未完整验收。此机“上一个输入源”使用自定义 Function 修饰键配置；Ctrl+Space 探针未构成有效系统快捷键测试。需使用本机实际快捷键，分别验证保持开启、跟随系统、再次恢复，并检查焦点和正在输入的文本 |
| 睡眠唤醒 | 未执行真实睡眠 / 唤醒，需确认状态和输入功能恢复 |
| 真实登录 | launchd 任务启动通过；注销再登录和重启未执行 |
| macOS 26 GUI | 云端 macOS 26 构建测试通过，本机 GUI 为 macOS 27.0.1；最低系统的 GUI 尚未验收 |

## 本轮修复与后续动作

首次 `v0.0.15` 构建在 `codesign` 报 `no identity found` 后停止，未创建 Release、未提交 Apple 公证。临时钥匙串缺少用户搜索列表配置；按 [GitHub 官方流程](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications) 加入搜索列表后，`v0.0.16` 全流程通过。旧标签未移动。

Release 工作流先保存并核验 Draft，本次已公开同一发行包，将网站更新合入生产 `main`，并完成匿名公开下载、固定 appcast URL、应用内更新检查及官网 SHA-256 与页面版本一致性核验。任何产品代码修复都需要递增构建号并创建新标签，不覆盖当前发行包。

本机详细回执、更新结果截图和历史开发包备份在仓库忽略的 `dist/release-acceptance-20261023/`。正式签名 ZIP 以 Actions / 公开 Release 中记录的哈希为准。
