# GitHub 发布与自动更新

仓库：[mreasonyang/keypin](https://github.com/mreasonyang/keypin)。发行范围是 macOS 26+、Apple silicon 与 Intel，使用同一个 Universal ZIP。代码、版本标签、Actions 和 Release 均在这个仓库管理。

## 更新机制

应用使用固定版本的 [Sparkle 2](https://sparkle-project.org/documentation/) 标准更新器，完成检查、下载、签名验证、替换应用和重启。Universal 更新同时包含 arm64 与 x86_64；appcast 不附加仅限 arm64 的硬件限制，旧 arm64 版本可使用原公钥升级。发布校验读取 ZIP 中的真实 Mach-O 架构，拒绝架构与硬件限制不一致的 feed。GitHub Releases 托管 ZIP 与 `appcast.xml`；应用固定读取：

```text
https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml
```

更新包与 appcast 都使用 Sparkle Ed25519 签名。应用启用 `SUVerifyUpdateBeforeExtraction` 和 `SURequireSignedFeed`，关闭系统信息统计。Apple Developer ID / 公证负责 macOS 分发身份，Sparkle 密钥负责更新真实性，两者不能互相替代。公钥编入应用，私钥只供受信任的发布任务使用。

自动检查和自动下载安装默认关闭，用户在关于页开启。CLI、焦点 helper、预览不启动 updater。旧版 0.0.14 及以前没有安装更新能力，首次迁移必须手动下载并替换应用；以后保留同一安装位置更新。`CFBundleVersion` 是单调增加的更新顺序，不能因为营销版本号变小而复用或减少构建号。

## 两条 Actions 流程

- **CI**：`main` 推送及 PR 运行测试、本地化、发布工具检查和开发包构建；产物标注 development，无 Apple 公证，未配置公钥时禁用更新。它不读取发布私钥。
- **Release**：版本标签 `v*` 或手动选择已有版本标签，核对标签与 `Info.plist`，测试后构建、签名、公证、附加票据、验证 Gatekeeper、制作 ZIP、签署 appcast，最后保存为 Draft Release。完成最终包安装验收后，公开同一草稿。凭据缺失或任一检查失败就停止，不能退回未签名正式发布。

Actions 使用 `macos-26`，显式安装 Rosetta 并执行原生与 Intel 两组测试。本地可通过 `KEYPIN_ARCH=universal ./scripts/ci.sh` 运行同一开发验证流程；正式发布由 GitHub 执行，不依赖维护者本机的钥匙串。Rosetta 运行结果与 Intel 真机验收分别记录。

## 维护者一次性配置

在 [Actions Secrets 设置](https://github.com/mreasonyang/keypin/settings/secrets/actions) 添加以下 repository secrets。私钥、证书密码和公证密码不要写入源码、日志、Issue 或聊天。

| Secret | 值 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | 包含 Developer ID Application 证书及私钥的 `.p12` 文件的 Base64 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `AC_APPLE_ID` | 所属 Apple Developer 账号的 Apple ID |
| `AC_TEAM_ID` | 该 Developer ID 证书的 Team ID |
| `AC_PASSWORD` | 为公证生成的 Apple ID App-specific Password |
| `SPARKLE_PRIVATE_KEY` | Sparkle `generate_keys -x` 导出的私钥文本 |

在 [Actions Variables 设置](https://github.com/mreasonyang/keypin/settings/variables/actions) 添加 **repository variable** `SPARKLE_PUBLIC_KEY`。它是 Sparkle 生成的 Base64 公钥，可以公开；不要把私钥填到这里。

### Apple 证书与公证

1. 打开 macOS「钥匙串访问」，选择左侧「登录」钥匙串，再选择「我的证书」。找到有效的 **Developer ID Application: 姓名或组织 (Team ID)**；Apple Development 证书不能用于这里的正式分发。
2. 展开该证书左侧的小三角，确认下面有私钥。选中证书，使用「文件 > 导出项目…」，格式选择「个人信息交换 (.p12)」。如果只能导出 `.cer`，通常是没有选中含私钥的身份，或这台 Mac 没有该私钥；不要用 `.cer` 继续。
3. 将文件保存到自己指定的临时路径，设置一个导出密码并妥善保存。macOS 可能要求输入本机登录密码以授权导出；这是钥匙串授权，与导出密码、Apple ID 密码不同。
4. 在自己的终端中上传 `.p12`，将下面的路径替换为实际保存位置。命令将内容直接传给 GitHub，不打印证书内容：

   ```sh
   base64 -i /path/to/DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo mreasonyang/keypin
   ```

5. 打开上面的 Actions Secrets 设置链接，逐项点击 **New repository secret**，填写名称和值并保存：`MACOS_CERTIFICATE_PASSWORD` 填第 3 步的导出密码；`AC_APPLE_ID` 填开发者账号邮箱；`AC_TEAM_ID` 填证书名称括号内的 Team ID。
6. 登录 [Apple 账号](https://account.apple.com/)，在「登录和安全 > App 专用密码」中生成一个用于 KeyPin 公证的密码。将它保存为 `AC_PASSWORD`；不要填写 Apple ID 登录密码。
7. 导出的 `.p12` 保存在安全备份中，或在成功配置后删除临时导出文件。工作流将证书导入 runner 的临时钥匙串，并在结束时清理。

参考：[Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[GitHub Secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)。

### Sparkle 更新密钥

以下命令由维护者亲自在本机终端执行。它们会创建/访问本机钥匙串中的 KeyPin 更新签名密钥，并将导出私钥直接上传至 GitHub Secret；不要把终端中的私钥文本发给别人。

先在仓库根目录下载固定版本的公开依赖：

```sh
swift package --disable-keychain --disable-netrc resolve
```

然后执行：

```sh
(
  set -eu
  umask 077
  keypin_keys_tool=".build/artifacts/sparkle/Sparkle/bin/generate_keys"
  "$keypin_keys_tool" --account keypin
  "$keypin_keys_tool" --account keypin -p | gh variable set SPARKLE_PUBLIC_KEY --repo mreasonyang/keypin
  keypin_key_dir="$(mktemp -d)"
  trap 'rm -rf "$keypin_key_dir"' EXIT
  "$keypin_keys_tool" --account keypin -x "$keypin_key_dir/sparkle.private-key"
  gh secret set SPARKLE_PRIVATE_KEY --repo mreasonyang/keypin < "$keypin_key_dir/sparkle.private-key"
)
```

首次生成会请求钥匙串访问授权。使用独立的 `keypin` account，重复运行复用该密钥，不应每次发布重新生成。妥善备份更新签名密钥；密钥轮换必须按 [Sparkle 密钥轮换说明](https://sparkle-project.org/documentation/#rotating-signing-keys) 规划，不能随意替换已发行应用信任的公钥。当前使用 ZIP 且要求解压前验证签名，丢失 Ed25519 私钥后不能直接换新密钥继续发布 ZIP；恢复更新信任需要另行设计符合 Sparkle 要求的、Developer ID 签名的 DMG 迁移。

仅检查名称是否齐全，可运行：

```sh
gh secret list --repo mreasonyang/keypin
gh variable list --repo mreasonyang/keypin
```

## 每次发布

1. 在 `packaging/Info.plist` 更新 `CFBundleShortVersionString`，并递增 `CFBundleVersion`。提交到 `main`，等待 CI 通过。
2. 对这个确定的提交创建匹配标签，如 `v0.0.15`，推送标签触发 Release。不要复用已发布标签或用相同构建号替换安装包。
3. 检查 Actions 的签名、公证、staple、Gatekeeper 和 appcast 验证结果。Draft Release 应包含 `KeyPin-<version>-universal.zip`、`SHA256SUMS`、`appcast.xml` 和仅含公开验证结果的 `verification.json`。工作流建立草稿后重新下载已上传文件核对哈希，验收前保留草稿状态；版本号和构建号都必须高于上一正式版。如果上传或核验失败，草稿会保留，重跑不会覆盖它；检查并删除该失败草稿后，再对同一标签重试。
4. 使用 `gh release download v<version> --repo mreasonyang/keypin --dir <empty-directory>` 下载草稿，验证校验和、隔离属性下首次启动、登录自启、真实中文候选和跨 App 焦点。存在上一支持更新版本时，还要验证实际升级与配置保留。开发包、单测或签名结果不替代这一步。首个版本尚无公开更新源，检查更新返回无可用 feed 不能算作双版本升级验收。
5. 安装验收通过后，用 `gh release edit v<version> --repo mreasonyang/keypin --draft=false --latest` 公开已验证的同一草稿。重新从公开 URL 下载核对 SHA-256，再更新官网的下载和版本信息。官网展示与实际 ZIP 的版本、架构和校验和必须一致。

正式版本间自动更新已完成[0.0.16 → 远程正式 0.0.17 的实机验证](REMOTE-AUTO-UPDATE-0.0.16-TO-0.0.17-20261023.md)：本机保留真实正式旧版，远程由 Actions 构建、签名、公证并公开新版，再通过同一生产 feed 自动发现、下载和退出安装；配置、登录项和 CLI 均保留。

发布升级验收应使用真实公开的旧、新版本。修改本地版本元数据生成的测试基线仅可作为补充安装检查，不能代替正式远程升级验收。后续产品数据迁移及其他系统环境仍需对应验证；核心输入法、中文候选和跨 App 焦点验收按产品自身要求执行。
