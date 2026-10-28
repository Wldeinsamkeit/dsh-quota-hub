# dsh-quota-hub · 额度中心

[English](#english) | [中文](#中文)

<a id="中文"></a>
## 中文

在 DeepSeek Harness 侧边栏实时查看所有 AI 提供商的额度：**半圆形彩虹拱**总览（每道弧一个 AI，按剩余额度填充，全满 = 完整彩虹），可点击在 **5 小时额度 / 每周额度** 之间切换，带**加满动画**；鼠标**悬浮**任意弧显示该家详细信息（双窗口剩余、用量、重置时间）。展开详情是每个提供商一张卡片，每条额度（5 小时 / 每周 / 余额 / 日请求）独立一条分档色进度条（90+ 绿 / 70-90 黄 / 30-70 蓝 / <30 红）。

数据 10 秒自动刷新，也可手动立即采集。零配置：密钥自动从 DeepSeek Harness 凭据库（`~/.dsh/.credentials.yaml`）、`~/.codex/auth.json`（Codex/ChatGPT）与已登录的 `mmx`（MiniMax）读取，任何密钥都不上传。

### 数据来源

| 提供商 | 指标 | 方式 |
| --- | --- | --- |
| Z.ai / 智谱 Coding Plan | 5 小时 + 每周 credits | 官方配额端点（Coding Plan Key） |
| MiniMax | 5 小时 + 每周（百分比） | `mmx quota show` / 官方接口 |
| Codex · ChatGPT | 5 小时窗口 + 每周窗口 | 官方用量端点（OAuth） |
| DeepSeek | 预付余额 | 官方 balance 接口 |
| Gemini · AI Pro | CLI 日请求 | 手工记录（官方无额度 API） |

### 安装

- **插件市场**（收录后）：Plugins → Plugin Market 搜索 `quota` 一键安装
- **命令行**：`dsh plugin --profile <profile> add https://github.com/Wldeinsamkeit/dsh-quota-hub`
- **手动**：克隆本仓库后在 Harness 的插件管理里 `install_bundle` 指向本目录

### 配套：macOS 菜单栏 QuotaBar

`companion-quota-bar/` 内是同一套数据的 macOS 菜单栏版（小彩虹图标 + 半圆彩虹弹窗），两者共用同一份 `state.json`，见 [companion-quota-bar/README.md](companion-quota-bar/README.md)。

<a id="english"></a>
## English

Live AI quota dashboard for the DeepSeek Harness sidebar: a **semicircle rainbow gauge** where each arc is one provider, filled by remaining quota (full rainbow = everything full). Click to switch between **5-hour windows and weekly quotas** — with a fill-up animation on open and on switch. **Hover** any arc for that provider's details (both windows, usage, reset time). Expanded view shows one card per provider with a separate level-colored progress bar per quota (90+ green / 70-90 yellow / 30-70 blue / <30 red).

Auto-refreshes every 10 seconds; manual refresh runs the collector on demand. **Zero configuration**: keys are read locally from the DeepSeek Harness credential store, `~/.codex/auth.json` (Codex/ChatGPT) and a logged-in `mmx` (MiniMax). Nothing ever leaves the machine.

### Install

- **Plugin Market** (once curated): Plugins → Plugin Market, search `quota`
- **CLI**: `dsh plugin --profile <profile> add https://github.com/Wldeinsamkeit/dsh-quota-hub`
- **Manual**: clone and run `install_bundle` pointing at this directory

## License

MIT
