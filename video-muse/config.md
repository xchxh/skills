# Video Agnes 配置说明

本 skill 不保存固定配置。每次视频生成都由调用方提供：

- url
- key
- model
- prompt
- platform：`local`、`openclaw` 或 `hermes`
- output/output-dir：由 OpenClaw 或 Hermes 传入的可访问产物目录

不要把 API key 写入此文件。
