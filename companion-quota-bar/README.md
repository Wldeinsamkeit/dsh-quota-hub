# QuotaBar · AI 额度中心（macOS 菜单栏）

在 Mac 顶部状态栏放一只 DeepSeek 小鲸鱼，点开即可看到各 AI 提供商的**实时额度进度条**（5 小时窗口 / 每周额度 / 余额 / 日请求）。开机登录自动启动，无需打开任何 AI 应用。

## 组成

| 组件 | 说明 |
| --- | --- |
| `QuotaBar.app` | 原生 SwiftUI 菜单栏应用（swiftc 编译，零第三方依赖）。点状态栏小鲸鱼 → **正下方弹出透明毛玻璃面板**：每个模型一张卡片，卡片内是进度条 + 用量/上限 + 重置倒计时。再点一次收起。右键（或 ⌥点击）图标 → 刷新 / 配置 / 退出。 |
| `collector/collect.mjs` | 采集器（Node 18+ 无依赖）。读取 `config.json`，调用各官方接口 / 写入手工档，产出 `state.json`。每 5 分钟自动跑一次，也可手动刷新。 |
| `config/config.json` | 凭据与手工额度配置。 |
| `com.tianzhao.quotabar.plist` | LaunchAgent：Mac 登录自启。 |

安装位置：`~/Applications/QuotaBar.app`；配置/数据：`~/Library/Application Support/QuotaBar/`。

## 各家数据来源（诚实版）

| 提供商 | 有什么 | 数据来源 | 状态 |
| --- | --- | --- | --- |
| **Z.ai / 智谱 Coding Plan** | 5 小时额度 + 每周额度 | 官方配额端点 `open.bigmodel.cn/api/monitor/usage/quota/limit`（Coding Plan Key 直查，自动从 DSH 凭据库读取） | ✅ 自动 |
| **DeepSeek** | 预付余额（无 5h/周窗口） | 官方接口 `GET /user/balance`（Key 自动从 DSH 凭据库读取） | ✅ 自动 |
| **MiniMax** | 5 小时窗口 + 每周额度（百分比） | `mmx quota show`（已登录）或 `/v1/token_plan/remains` | ✅ 自动 |
| **Gemini · AI Pro** | CLI 1,500 请求/天（无公开额度 API） | 手工档（可在 config 里记 used/limit） | ✅ 手工 |
| **任意其他** | 自定义 | `config.manual` 数组，想加几条加几条 | ✅ 手工 |

> 说明：DSH/浏览器插件画不进 macOS 状态栏，所以菜单栏部分是**独立原生 App**；「实时」取决于采集器刷新周期（默认 5 分钟，面板里可手动刷新）。

## 使用

```sh
./build.sh          # 编译 + 安装 + 登录自启 + 启动
```

- 菜单栏出现小鲸鱼 → **点一下**，小鲸鱼正下方弹出毛玻璃面板（348×560，悬浮在所有窗口之上、不抢焦点）；
- 面板内：5 个模型全部展开，各自带 5 小时 / 每周 / 余额进度条与重置倒计时；
- 面板右上角：↻ 立即采集、📁 打开配置目录、✕ 收起；Esc 收起；可拖动；
- 右键（或 ⌥ 点击）小鲸鱼 → 刷新全部额度 / 打开配置目录 / 退出；
- **零配置**：Z.ai、DeepSeek、MiniMax 的 Key 自动从 DSH 凭据库 `~/.dsh/.credentials.yaml` 读取；Codex 自动读 `~/.codex/auth.json`；
- 只有 Gemini 需要手工：`config.json → gemini.manual.daily` 记录今日 CLI 请求数。

卸载：

```sh
launchctl bootout gui/$(id -u)/com.tianzhao.quotabar
rm -f ~/Library/LaunchAgents/com.tianzhao.quotabar.plist
rm -rf ~/Applications/QuotaBar.app
```

## 路线

- 🔜 Z.ai cookie 逆向网页端点 → 5h/周额度自动化；
- 🔜 AI Relay 网关计数（所有经调度台的请求自动累计，不依赖厂商接口）；
- 🔜 DSH 内嵌「额度中心」页面（富进度条 + 历史）。
