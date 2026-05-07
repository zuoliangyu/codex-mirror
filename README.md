# codex-mirror

每日同步 [OpenAI Codex CLI](https://github.com/openai/codex) 官方 Release 到本仓库 GitHub Release，便于国内用户加速下载。

被 [`ai-cli-installer`](https://github.com/zuoliangyu/ai-cli-installer-dist) 桌面应用作为后端镜像源使用。

## 镜像了什么

每个版本的 GH Release 包含：

| 文件 | 说明 |
|--|--|
| `manifest.json` | 版本元信息 + 6 平台 SHA256 |
| `SHA256SUMS` | 平铺 SHA256 列表 |
| `darwin-arm64-codex-aarch64-apple-darwin.zst` | macOS Apple Silicon |
| `darwin-x64-codex-x86_64-apple-darwin.zst` | macOS Intel |
| `linux-arm64-codex-aarch64-unknown-linux-musl.zst` | Linux ARM64 (musl) |
| `linux-x64-codex-x86_64-unknown-linux-musl.zst` | Linux x64 (musl) |
| `win32-arm64-codex-aarch64-pc-windows-msvc.exe.zst` | Windows ARM64 |
| `win32-x64-codex-x86_64-pc-windows-msvc.exe.zst` | Windows x64 |

资产名格式 `{platform}-{upstream-asset-name}`，因为 GH Release 不支持子目录。

每个 `.zst` 是单二进制（zstd 压缩，比 `.tar.gz` 省 30%）。下载后 zstd 解压即得 `codex` / `codex.exe`，**不需要额外解压步骤**（不是 tarball）。

## manifest.json 结构

```json
{
  "version": "0.128.0",
  "upstream_tag": "rust-v0.128.0",
  "buildDate": "2026-05-07T12:00:00Z",
  "platforms": {
    "linux-x64": {
      "asset": "linux-x64-codex-x86_64-unknown-linux-musl.zst",
      "binary": "codex",
      "checksum": "<sha256>",
      "size": 63346566
    }
  }
}
```

跟 [claude-code-mirror](https://github.com/zuoliangyu/claude-code-mirror) 的 manifest 结构一致（多了 `asset` 字段，因为 Codex 资产名跟 binary 名不同）。

## 与 Codex 上游的差异

| 项 | 上游 | 本镜像 |
|--|--|--|
| Hash | blake3 + sigstore | SHA256（我们算） |
| 格式 | .zst / .tar.gz / .zip / .dmg / 原始 .exe 等多种 | 仅 .zst |
| Linux 变体 | 仅 musl（无 glibc） | 同 |
| 平台 | 6 个 | 同 |
| 自举 | 走 `~/.codex/packages/standalone/` 多层目录 | 简化：直接 `~/.local/bin/codex(.exe)` |

## 通道指针

- `channels/latest.txt` — 最新版本号（每次同步成功后更新）

应用通过 `https://raw.githubusercontent.com/zuoliangyu/codex-mirror/main/channels/latest.txt` 读取（也可走 GH 加速代理）。

## 同步机制

`.github/workflows/sync.yml`：

- 每天 UTC 18:15（北京 02:15，错峰避开 claude-code-mirror 的 02:00）
- 也可手动触发，可指定 upstream tag（默认拉 `latest`）
- 流程：
  1. 调 `api.github.com/repos/openai/codex/releases/latest` 拿 tag
  2. 已有同 tag 的镜像则只更新通道指针
  3. 否则跑 `sync/sync.sh` 下 6 平台 .zst + sha256 + 生成 manifest
  4. `gh release create --latest=true` 上传
  5. 提交 `channels/latest.txt` 到 main
- 自动清理：保留最近 3 个 release（每个 ~371 MB，比 Claude 小，不需要保留太多）

## 法律说明

本仓库仅做透明镜像，所有 `.zst` 均原封不动地从 `github.com/openai/codex/releases/` 同步，SHA256 校验匹配 OpenAI 官方提供的 `.sigstore` 数据。

不修改、不重新打包、不绑定其他内容。Codex CLI 的版权与许可归 OpenAI。
