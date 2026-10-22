# GitHub 发布与自动更新

仓库：[mreasonyang/keypin](https://github.com/mreasonyang/keypin)。发行范围是 macOS 26+、Apple silicon。代码、版本标签、Actions 和 Release 均在这个仓库管理。

## 更新机制

应用使用固定版本的 [Sparkle 2](https://sparkle-project.org/documentation/) 标准更新器，完成检查、下载、签名验证、替换应用和重启。GitHub Releases 托管 ZIP 与 `appcast.xml`；应用固定读取：

```text
https://github.com/mreasonyang/keypin/releases/latest/download/appcast.xml
```

更新包与 appcast 都使用 Sparkle Ed25519 签名。应用启用 `SUVerifyUpdateBeforeExtraction` 和 `SURequireSignedFeed`，关闭系统信息统计。Apple Developer ID / 公证负责 macOS 分发身份，Sparkle 密钥负责更新真实性，两者不能互相替代。公钥编入应用，私钥只供受信任的发布任务使用。

自动检查和自动下载安装默认关闭，用户在关于页开启。CLI、焦点 helper、预览不启动 updater。旧版 0.0.14 及以前没有安装更新能力，首次迁移必须手动下载并替换应用；以后保留同一安装位置更新。`CFBundleVersion` 是单调增加的更新顺序，不能因为营销版本号变小而复用或减少构建号。

## 两条 Actions 流程

- **CI**：`main` 推送及 PR 运行测试、本地化、发布工具检查和开发包构建；产物标注 development，无 Apple 公证，未配置公钥时禁用更新。它不读取发布私钥。
- **Release**：版本标签 `v*` 或手动选择已有版本标签，核对标签与 `Info.plist`，测试后构建、签名、公证、附加票据、验证 Gatekeeper、制作 ZIP、签署 appcast，最后发布 Release。凭据缺失或任一检查失败就停止，不能退回未签名正式发布。

Actions 使用 `macos-26`。本地可通过 `./scripts/ci.sh` 运行同一开发验证流程；正式发布由 GitHub 执行，不依赖维护者本机的钥匙串。

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

1. 在「钥匙串访问 > 我的证书」中找到有效的 **Developer ID Application** 证书，展开并确认含私钥。导出该身份为 `.p12`，设置导出密码。Apple Development 证书不能用于这里的正式分发。
2. 由维护者在自己的终端中上传 `.p12`，不要打印内容。例如：

   ```sh
   base64 -i /path/to/DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo mreasonyang/keypin
   ```

3. 通过 GitHub Secrets 页面输入其余四项 Apple 凭据。App-specific Password 在 [Apple 账号](https://account.apple.com/) 中生成，不使用 Apple ID 登录密码。
4. 导出的 `.p12` 保存在安全备份中，或在成功配置后删除临时导出文件。工作流将证书导入 runner 的临时钥匙串，并在结束时清理。

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

首次生成会请求钥匙串访问授权。使用独立的 `keypin` account，重复运行复用该密钥，不应每次发布重新生成。妥善备份更新签名密钥；密钥轮换必须按 [Sparkle 密钥轮换说明](https://sparkle-project.org/documentation/#changing-eddsa-keys) 规划，不能随意替换已发行应用信任的公钥。

仅检查名称是否齐全，可运行：

```sh
gh secret list --repo mreasonyang/keypin
gh variable list --repo mreasonyang/keypin
```

## 每次发布

1. 在 `packaging/Info.plist` 更新 `CFBundleShortVersionString`，并递增 `CFBundleVersion`。提交到 `main`，等待 CI 通过。
2. 对这个确定的提交创建匹配标签，如 `v0.0.15`，推送标签触发 Release。不要复用已发布标签或用相同构建号替换安装包。
3. 检查 Actions 的签名、公证、staple、Gatekeeper 和 appcast 验证结果。Release 应包含 `KeyPin-<version>-arm64.zip`、`SHA256SUMS` 和 `appcast.xml`；只有全部准备好后才作为最新正式版公开。
4. 从公开 Release 实际下载，验证校验和、首次启动、登录自启以及从上一版进行更新后的配置保留。开发包、单测或签名结果不替代这一步。
5. 更新官网的下载和版本信息。官网展示与实际 ZIP 的版本、架构和校验和必须一致。

在首次签名 Release 和两个版本间的实际升级验证完成前，不应宣称自动更新已通过生产验收。核心输入法、中文候选和跨 App 焦点验收仍按产品自身要求执行。
