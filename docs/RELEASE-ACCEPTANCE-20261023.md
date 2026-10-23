# KeyPin 0.0.16 (17) 发布前验证

日期：2026-10-23，Asia/Shanghai。结论：**发行签名与本机安装链路通过，整体发布验收仍为 PARTIAL。Release 保持 Draft。**

## 固定候选

| 项目 | 证据 |
| --- | --- |
| 源码 | `a4b752af3925dc2d319e2421f8cd411b27ec9309`，标签 `v0.0.16` |
| 版本 / 构建 | `0.0.16` / `17`，macOS 26+，arm64 |
| CI | [39838045534](https://github.com/mreasonyang/keypin/actions/runs/39838045534)，通过 |
| Release 流程 | [39838479254](https://github.com/mreasonyang/keypin/actions/runs/39838479254)，签名、公证及草稿上传后重新下载验证均通过 |
| 候选 ZIP | `KeyPin-0.0.16-arm64.zip`，2,409,997 字节 |
| SHA-256 | `fdfe363910a90cedf8a0c1bafbb255f5db0c528b42d785ee0a3573bc45cfec3a` |
| Apple 公证 | `Accepted`，提交 ID `2cffbbb6-c650-4f9d-a60b-351de7e603d4` |
| 本机环境 | macOS `27.0.1`，arm64。GitHub 构建和测试使用 `macos-26`；未在本机 macOS 26 做 GUI 验收 |

`verification.json` 随草稿分发，只记录公开构建信息和已经通过的发行工具检查，`installationAcceptance` 明确为 `pending`。它不是完整实机验收回执。

## 已完成

- CI：145 项 Swift 单测、30 项发布预检和 bundle 模式检查、15 个隔离打包场景、5 种语言各 127 个键，以及 Sparkle 官方工具签名和篡改拒绝检查通过。合成测试使用临时密钥，不代表实机升级。
- 真实发布凭据：Developer ID 证书可用于签名，Apple 公证凭据可用，Sparkle 私钥与公钥匹配。签名包含 Hardened Runtime 和安全时间戳；票据附加、解压后票据及 Gatekeeper 检查通过。
- 本机下载复核：通过 GitHub CLI 下载草稿，校验 ZIP、appcast 和验证回执的 SHA-256。另用应用中包含的公钥和 CryptoKit 验证下载的 ZIP 与 appcast，并确认内存中的篡改副本被拒绝，未读取私钥或本机钥匙串。
- Brave 真实下载：登录维护者账号访问草稿，保存 ZIP 到 Downloads；文件大小和 SHA-256 与 Actions 产物一致，存在 Brave 的下载隔离标记。这不是匿名用户访问公开 Release 的验证。
- 首启：保留下载隔离信息的解压副本通过 Gatekeeper。macOS 出现正常的“从互联网下载”确认，明确显示 Apple 检查未发现恶意软件；确认后应用运行并显示真实主窗口。首次运行曾进入 App Translocation，连接实际运行路径后可访问窗口。
- 系统默认 ZIP 应用是 MacZip。Finder 打开 ZIP 会进入预览，点击 Extract All 后得到应用；该解压器输出的应用没有 quarantine 属性。它与保留 quarantine 的 `ditto --qtn` 首启测试分别记录，不能混称为 Archive Utility 解压。
- 安装：将浏览器下载并经 MacZip 解压的同一候选安装至 `/Applications/KeyPin.app`。签名、公证、版本和架构再次验证通过。关于页显示 `0.0.16 (17)`，两个自动更新选项默认关闭。
- 登录项：GUI 关闭登录启动时当前应用仍运行；恢复后 plist 指向 `/Applications/KeyPin.app/Contents/MacOS/keypin background`。退出 GUI 后通过 `launchctl kickstart` 启动该登录任务，确认真实进程运行并恢复 `keeping`。这不是注销、登录或重启测试。
- CLI 入口已迁移到 Applications 中的已安装应用。输入法目标、保持开关、语言和引导标记与测试前一致。
- 真实 Secure Input：聚焦 Brave 本地测试页的空白密码字段后，CLI 状态为 `secure_input`，`apply --json` 返回同名错误；移开焦点后恢复 `keeping`。测试未输入密码。
- 真实面板选择：ABC 和 Squirrel 之间切换后，面板及系统输入源 ID 一致；从 ABC 回到 Squirrel 时签名焦点 helper 正常完成。此证据只确认输入源切换，不证明中文候选和组合输入正常。
- 中文输入对照探针：对最终安装包保持开启与暂停两种状态，均在新建 TextEdit 文稿中通过电脑交互工具逐键发送 `n`、`i`；两组都只得到 ASCII `ni` 和系统英文建议，没有触发中文候选。测试后已恢复保持开启，Squirrel 目标和登录项不变。该对照说明当前自动化路径不能提供中文输入验收证据；它既不是中文输入通过的证据，也不足以认定是 KeyPin 缺陷。对照文稿保存于本机忽略的 `dist/release-acceptance-20261023/input-probe-control-20261023.rtf`。
- 原生更新入口可启动 Sparkle。由于没有公开 stable Release，固定 latest feed 尚不可用，界面显示可取消的更新获取错误；取消后关于页恢复。这不是成功获取 feed、更新安装或升级验收。

## 仍需验收

| 项目 | 当前状态 / 完成标准 |
| --- | --- |
| 中文候选与组合输入 | 未通过。TextEdit 键盘探针仅得到 ASCII 文本，没有形成真实候选；现有证据不足以区分工具、输入法内部模式和产品因素。需在最终安装包下，用物理键盘分别在 TextEdit、常用终端、编辑器和 Brave 输入中文，核对候选、提交、退格及组合输入期间切换应用不丢字、不抢焦点 |
| 系统快捷键与跨 App 恢复 | 未完整验收。此机“上一个输入源”使用自定义 Function 修饰键配置；Ctrl+Space 探针未构成有效系统快捷键测试。需使用本机实际快捷键，分别验证保持开启、跟随系统、再次恢复，并检查焦点和正在输入的文本 |
| 睡眠唤醒 | 未执行真实睡眠 / 唤醒，需确认状态和输入功能恢复 |
| 真实登录 | launchd 任务启动通过；注销再登录和重启未执行 |
| macOS 26 GUI | 云端 macOS 26 构建测试通过，本机 GUI 为 macOS 27.0.1；最低系统的 GUI 尚未验收 |
| 版本间升级 | 未完成。需要两个正式签名版本，以及真实下载、替换、重启和配置 / 登录项保留；不能用单测、签名校验或当前 feed 获取错误替代 |
| 公开分发与官网 | Release 为 Draft，官网生产站点仍提供 1.13 (14)。三语言新版和同一 ZIP 已推送至 `keypin-site` 的 `release/keypin-0.0.16` 分支，提交 `e7c8805e63d3cd4479e24418669332092c37eb3f`。[GitHub 云端构建、检查和打包](https://github.com/mreasonyang/keypin-site/actions/runs/39890369224)通过，Cloudflare 预览部署成功；[新版预览](https://3aa0d6cb.keypin-site.pages.dev)的 17 个公开文件匿名核验全部通过，包含真实 ZIP 与校验和。尚未合入生产 `main` |

## 本轮修复与后续动作

首次 `v0.0.15` 构建在 `codesign` 报 `no identity found` 后停止，未创建 Release、未提交 Apple 公证。临时钥匙串缺少用户搜索列表配置；按 [GitHub 官方流程](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications) 加入搜索列表后，`v0.0.16` 全流程通过。旧标签未移动。

Release 工作流现在先保存并核验 Draft，保留最终 ZIP 不变，待核心输入、焦点和物理系统验收后再公开同一草稿。然后复核匿名公开下载、固定 appcast URL，并将已准备的官网分支合入生产 `main`，完成线上 SHA-256 与页面版本一致性检查。任何产品代码修复都需要递增构建号并创建新标签，不覆盖当前候选。

本机详细回执和历史开发包备份在仓库忽略的 `dist/release-acceptance-20261023/`。正式签名 ZIP 仍以 Actions / Release 草稿中记录的哈希为准。
