---
name: image-grok
description: 根据用户提供的图片生成 API 地址、API key 和 model 调用生图接口，并适配 OpenClaw 与 Hermes 的产物目录。用户要求生成图片、AI 绘图、出图，或明确提供 url/key/model 在 OpenClaw/Hermes 中生图时使用此 skill；不要使用固定 model、固定 workspace 或固定 target。
---

# Image Grok

使用用户本次提供的 `url`、`key`、`model` 和提示词调用图片生成接口，并把生成的图片保存为 OpenClaw、Hermes 或本地环境可读取的文件。

## 触发与输入

当用户要求生图时，先确认本次请求具备以下信息：

- `url`：图片生成 API 的 base URL 或完整 `/images/generations` 地址。
- `key`：API key。不要写入 skill 文件或日志。
- `model`：本次要使用的模型名称。
- `prompt`：图片提示词。

如果缺少 `url`、`key` 或 `model`，先向用户索取缺失项；不要使用默认值、历史固定值或占位值。

## 平台模式

`generate.sh` 支持三种平台模式：

- `local`：本地调试，默认保存到 `./outputs/local/`。
- `openclaw`：OpenClaw 调用，优先使用 `OPENCLAW_WORKSPACE` 或 `--output-dir`；未提供时自动探测 OpenClaw workspace，最后回退到 `./outputs/openclaw/`。
- `hermes`：Hermes 调用，优先使用 `HERMES_OUTPUT_DIR`、`HERMES_ARTIFACT_DIR` 或 `--output-dir`；未提供时回退到 `./outputs/hermes/`。

不要在 skill 中固定 workspace 或 target。由 OpenClaw/Hermes 调用方传入 `--platform`、`--output-dir` 或 `--output`。

## URL 规范化

`generate.sh` 会自动规范化接口地址：

- `https://example.com` → `https://example.com/v1/images/generations`
- `https://example.com/v1` → `https://example.com/v1/images/generations`
- `https://example.com/v1/images/generations` → 原样使用

## OpenClaw 调用

推荐由 OpenClaw 注入 workspace，并用环境变量传递 key：

```bash
OPENCLAW_WORKSPACE="<openclaw-workspace>" \
IMAGE_API_URL="<url>" \
IMAGE_API_KEY="<key>" \
IMAGE_MODEL="<model>" \
IMAGE_PROMPT="<prompt>" \
bash generate.sh --platform openclaw
```

如果 OpenClaw 使用其他可发送目录，显式传入：

```bash
IMAGE_API_URL="<url>" \
IMAGE_API_KEY="<key>" \
IMAGE_MODEL="<model>" \
IMAGE_PROMPT="<prompt>" \
bash generate.sh --platform openclaw --output-dir "<openclaw-workspace>"
```

脚本成功后会输出图片本地路径。OpenClaw 后续如需发送图片，应使用平台自己的消息发送工具读取该路径。

## Hermes 调用

推荐由 Hermes 注入 artifact/output 目录：

```bash
HERMES_OUTPUT_DIR="<hermes-output-dir>" \
IMAGE_API_URL="<url>" \
IMAGE_API_KEY="<key>" \
IMAGE_MODEL="<model>" \
IMAGE_PROMPT="<prompt>" \
bash generate.sh --platform hermes
```

也可以显式传入输出目录：

```bash
IMAGE_API_URL="<url>" \
IMAGE_API_KEY="<key>" \
IMAGE_MODEL="<model>" \
IMAGE_PROMPT="<prompt>" \
bash generate.sh --platform hermes --output-dir "<hermes-output-dir>"
```

Hermes 应读取脚本输出的图片路径，并把该文件作为产物返回或继续传给后续流程。

## 本地调试

```bash
IMAGE_API_URL="<url>" \
IMAGE_API_KEY="<key>" \
IMAGE_MODEL="<model>" \
IMAGE_PROMPT="<prompt>" \
bash generate.sh --platform local
```

也可以直接指定完整输出文件：

```bash
bash generate.sh \
  --url "<url>" \
  --key "<key>" \
  --model "<model>" \
  --prompt "<prompt>" \
  --platform local \
  --output "./generated.jpg"
```

## 输出

脚本成功后：

- 标准输出只打印图片本地路径，方便 OpenClaw/Hermes 捕获。
- 同目录生成一个 JSON 元数据文件，包含 `platform`、`model`、`endpoint`、`output_path` 和远端图片 URL。
- 元数据不会包含 API key。

可用 `--metadata <path>` 自定义元数据文件路径。

## 响应处理

脚本支持 OpenAI 风格响应中的 `data[0].url`，也支持顶层 `url` 字段。脚本使用 Node.js 或 Python 构造与解析 JSON，会下载该 URL 指向的图片，并在成功后输出本地图片路径。

## 注意事项

- 不要把 API key 写入 `SKILL.md`、`config.md` 或其他持久文件。
- 不要复用旧的固定 model、workspace 或 target。
- 不要在 skill 内发送 Telegram 或其他消息；生图脚本只负责生成文件，发送动作交给 OpenClaw/Hermes 平台层。
- 如果平台要求特定可访问目录，使用 `--output-dir` 或 `--output` 显式传入。
