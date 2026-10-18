# ChatGPT PDF2zh Bridge

在 Windows 上将 Zotero PDF2zh 与 Sign in with ChatGPT DevKit 连接，生成中文 PDF 和中英对照 PDF。

本仓库发布的是本地桥接服务、启动器以及 SDK 补丁，不包含 PDF2zh 引擎、Zotero 插件或独立 EXE。需要先安装可用的 Zotero PDF2zh 后端。ChatGPT 登录授权、模型目录和可用额度取决于账号。

## 功能

- 本地网页登录、选择模型和推理强度，设置自动保存。
- 将文本 Chat Completions 请求转换为 SDK Responses 请求。
- 最多 4 路翻译并发，记录服务返回的 token 用量。
- 凭据使用 Windows 当前用户 DPAPI 加密，服务仅监听 127.0.0.1。
- 复用 PDF2zh 的整篇翻译、双语排版和 Zotero 附件回填。

## 安装

需要 Windows、Git、Node.js >= 22.12（含 npm），以及已经安装好的 Zotero PDF2zh 后端与 Python/Conda 环境。已测试 Zotero 10、PDF2zh 插件 4.1.7、后端 4.0.4，翻译引擎为 pdf2zh_next。其他版本兼容性未验证。

```powershell
git clone https://github.com/Jiang-Long-lab/chatgpt-pdf2zh-bridge.git
cd chatgpt-pdf2zh-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
Copy-Item .\config.example.ps1 .\config.local.ps1
notepad .\config.local.ps1
```

在配置文件中填写 Node、后端 Python 和包含 `server.py` 的后端目录。Python 必须是后端已配置好的环境，且包含 Flask。后端自身的翻译环境也需要可用。本项目不会自动安装或更新 PDF2zh。

`setup.ps1` 下载固定版本 SDK、应用本项目补丁并构建。已有 vendor 目录时脚本会停止，避免覆盖本地修改；安装失败后请先检查错误和目录内容再决定是否重建。

## 使用

1. 双击 `启动ChatGPT翻译.vbs`，或执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\start.ps1`。打开 <http://127.0.0.1:8766/>。
2. 点击 Continue with ChatGPT，在官方页面完成授权，回到本机页面选择账号实际可用的模型与推理强度。测试按钮会发送一次真实请求并消耗额度。
3. 在 Zotero PDF2zh 设置中填写下表。首次启动会自动生成本机连接密钥，请在本机 PowerShell 中读取后粘贴到插件，不要发到公开网页或 issue：

```powershell
(Get-Content "$env:LOCALAPPDATA\ZoteroChatGPTBridge\bridge.json" -Raw | ConvertFrom-Json).apiKey
```

| 配置项 | 值 |
| --- | --- |
| Python 服务器 | `http://127.0.0.1:8767` |
| 翻译引擎 | `pdf2zh_next` |
| 服务 | OpenAI / `openai` |
| 模型 | `chatgpt-auto` |
| API URL | `http://127.0.0.1:8766/v1` |
| API Key | 上述本机连接密钥（不是 OpenAI Platform API Key） |
| Worker / QPS | `4` / `2` |
| JSON mode | 关闭 |
| 输出 | 勾选 mono 和 dual；按需选择左右对照 |

4. 在 Zotero 中右键 PDF，使用 PDF2zh 翻译。关闭网页不会停止后台服务，电脑重启后需再次启动。VBS 隐藏运行；若启动失败，用 PowerShell 执行 start.ps1 查看错误。

## 用量与限制

- 数据保存在 `%LOCALAPPDATA%\ZoteroChatGPTBridge`。`account` 为加密凭据，`bridge.json` 包含本机密钥，`usage.jsonl` 记录数值用量。
- `/status` 的统计从本次启动起累计。token 数不等同于订阅额度百分比；账号额度还可能被其他会话消耗。用量与授权可在 <https://chatgpt.com/settings/usage> 管理。
- 默认首次配置是 GPT-6.1 Sol / 默认强度；可在网页中改为账号可用的其他模型。账号没有该模型时请选择目录中的模型。设置只影响后续请求，翻译期间请勿切换。
- `chatgpt-auto` 是固定别名：切换实际模型或强度后，PDF2zh 可能复用旧缓存。严格对比时需要在后端启用 `ignore_cache`；正常使用后可恢复缓存。
- 主翻译与回退任务可能同时触发本机 4 路上限，返回 429 后由翻译器重试。
- 排版由 PDF2zh 处理，复杂图注、表头、参考文献可能出现断字或重叠。此桥接器不修复排版。
- 仅支持非流式的文本 Chat Completions 输入，不是通用 OpenAI API 代理。SDK 在上游仍使用流式响应。

## 离线测试

完成安装后运行以下命令。测试使用模拟响应，不发送真实翻译请求：

```powershell
node --test adapter.test.mjs vendor/sign-in-with-chatgpt-devkit/packages/local/test/responses.test.mjs
```

2026-10-18 发布验证：固定 SDK 下载、补丁应用、构建及 18 项离线测试通过。`npm audit --omit=dev` 为 0 项；完整开发依赖检查发现 `source-map-js` 的 1 项 high 提示。此版本保留上游锁文件以便复现，未自动升级开发依赖；安装时可重新运行 audit 查看最新结果。

## 上游与许可

SDK 来源：<https://github.com/openai/sign-in-with-chatgpt-devkit>，固定提交 `0a36fefeb913055c8c7a1a29b63d82b96b2e841a`。

SDK 补丁保留 `response.completed` 的 usage 数据，并添加 reasoning effort 参数及对应测试。修改文件内包含变更声明。SDK 及这些修改受 [Sign-in with ChatGPT DevKit Noncommercial License](patches/SDK-LICENSE.txt) 约束，仅限该许可定义的非商业用途；不能将整套项目当作不受限制的 MIT 软件。上游依赖的许可见其仓库。本仓库独立桥接代码暂未另行授予开源许可证。

Zotero PDF2zh 上游：<https://github.com/guaguastandup/zotero-pdf2zh>。后端与翻译引擎不在本仓库分发，使用时应遵守各自许可。
