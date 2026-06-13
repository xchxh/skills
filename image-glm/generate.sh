#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '用法: %s --url URL --key API_KEY --model MODEL --prompt PROMPT [--platform local|openclaw|hermes] [--output OUTPUT_PATH] [--output-dir DIR] [--metadata METADATA_PATH]\n' "$0"
    printf '也可通过 IMAGE_API_URL、IMAGE_API_KEY、IMAGE_MODEL、IMAGE_PROMPT、IMAGE_PLATFORM、IMAGE_OUTPUT_PATH、IMAGE_OUTPUT_DIR、IMAGE_METADATA_PATH 环境变量传入。\n'
}

API_URL="${IMAGE_API_URL:-}"
API_KEY="${IMAGE_API_KEY:-}"
MODEL="${IMAGE_MODEL:-}"
PROMPT="${IMAGE_PROMPT:-}"
PLATFORM="${IMAGE_PLATFORM:-local}"
OUTPUT_PATH="${IMAGE_OUTPUT_PATH:-}"
OUTPUT_DIR="${IMAGE_OUTPUT_DIR:-}"
METADATA_PATH="${IMAGE_METADATA_PATH:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --url)
            API_URL="${2:-}"
            shift 2
            ;;
        --key)
            API_KEY="${2:-}"
            shift 2
            ;;
        --model)
            MODEL="${2:-}"
            shift 2
            ;;
        --prompt)
            PROMPT="${2:-}"
            shift 2
            ;;
        --platform)
            PLATFORM="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --metadata)
            METADATA_PATH="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '未知参数: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$API_URL" ] || [ -z "$API_KEY" ] || [ -z "$MODEL" ] || [ -z "$PROMPT" ]; then
    usage >&2
    exit 1
fi

case "$PLATFORM" in
    local|openclaw|hermes)
        ;;
    *)
        printf '错误: --platform 仅支持 local、openclaw 或 hermes。\n' >&2
        exit 1
        ;;
esac

if command -v node >/dev/null 2>&1; then
    JSON_RUNTIME="node"
elif command -v python3 >/dev/null 2>&1; then
    JSON_RUNTIME="python3"
elif command -v python >/dev/null 2>&1; then
    JSON_RUNTIME="python"
else
    printf '错误: 需要 node、python3 或 python 来构造和解析 JSON。\n' >&2
    exit 1
fi

normalize_endpoint() {
    local url="${1%/}"
    if [[ "$url" == */images/generations ]]; then
        printf '%s' "$url"
    elif [[ "$url" == */v1 ]]; then
        printf '%s/images/generations' "$url"
    else
        printf '%s/v1/images/generations' "$url"
    fi
}

select_output_dir() {
    if [ -n "$OUTPUT_DIR" ]; then
        printf '%s' "$OUTPUT_DIR"
        return
    fi

    case "$PLATFORM" in
        openclaw)
            if [ -n "${OPENCLAW_WORKSPACE:-}" ]; then
                printf '%s' "$OPENCLAW_WORKSPACE"
            else
                printf '%s' "./outputs/openclaw"
            fi
            ;;
        hermes)
            if [ -n "${HERMES_OUTPUT_DIR:-}" ]; then
                printf '%s' "$HERMES_OUTPUT_DIR"
            elif [ -n "${HERMES_ARTIFACT_DIR:-}" ]; then
                printf '%s' "$HERMES_ARTIFACT_DIR"
            else
                printf '%s' "./outputs/hermes"
            fi
            ;;
        *)
            printf '%s' "./outputs/local"
            ;;
    esac
}

ENDPOINT="$(normalize_endpoint "$API_URL")"
FILENAME="generated_$(date +%s).jpg"

if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="$(select_output_dir)/$FILENAME"
fi

if [ -z "$METADATA_PATH" ]; then
    METADATA_PATH="$(dirname "$OUTPUT_PATH")/$(basename "$OUTPUT_PATH" .jpg).json"
fi

export IMAGE_MODEL="$MODEL"
export IMAGE_PROMPT="$PROMPT"
if [ "$JSON_RUNTIME" = "node" ]; then
    REQUEST_BODY="$(node - <<'JS'
process.stdout.write(JSON.stringify({
    model: process.env.IMAGE_MODEL,
    prompt: process.env.IMAGE_PROMPT,
    n: 1,
    size: "1024x1024",
}));
JS
)"
else
    REQUEST_BODY="$($JSON_RUNTIME - <<'PY'
import json
import os

print(json.dumps({
    "model": os.environ["IMAGE_MODEL"],
    "prompt": os.environ["IMAGE_PROMPT"],
    "n": 1,
    "size": "1024x1024",
}, ensure_ascii=False))
PY
)"
fi

RESPONSE="$(curl -sS -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")"

export IMAGE_RESPONSE="$RESPONSE"
if [ "$JSON_RUNTIME" = "node" ]; then
    IMAGE_URL="$(node - <<'JS' || true
const data = JSON.parse(process.env.IMAGE_RESPONSE);
const item = Array.isArray(data.data) && data.data.length ? data.data[0] : data;
process.stdout.write(item.url || "");
JS
)"
else
    IMAGE_URL="$($JSON_RUNTIME - <<'PY' || true
import json
import os

data = json.loads(os.environ["IMAGE_RESPONSE"])
item = data["data"][0] if isinstance(data.get("data"), list) and data["data"] else data
print(item.get("url", ""))
PY
)"
fi

if [ -z "$IMAGE_URL" ]; then
    printf '错误: 响应中没有图片 URL。\n' >&2
    printf '%s\n' "$RESPONSE" >&2
    exit 1
fi

OUTPUT_DIRNAME="$(dirname "$OUTPUT_PATH")"
METADATA_DIRNAME="$(dirname "$METADATA_PATH")"
mkdir -p "$OUTPUT_DIRNAME" "$METADATA_DIRNAME"

curl -sS -L "$IMAGE_URL" -o "$OUTPUT_PATH"

if [ ! -s "$OUTPUT_PATH" ]; then
    printf '错误: 图片下载失败。\n' >&2
    exit 1
fi

export IMAGE_ENDPOINT="$ENDPOINT"
export IMAGE_OUTPUT_PATH="$OUTPUT_PATH"
export IMAGE_METADATA_PATH="$METADATA_PATH"
export IMAGE_PLATFORM_NAME="$PLATFORM"
export IMAGE_REMOTE_URL="$IMAGE_URL"
if [ "$JSON_RUNTIME" = "node" ]; then
    node - <<'JS' > "$METADATA_PATH"
process.stdout.write(JSON.stringify({
    platform: process.env.IMAGE_PLATFORM_NAME,
    model: process.env.IMAGE_MODEL,
    endpoint: process.env.IMAGE_ENDPOINT,
    output_path: process.env.IMAGE_OUTPUT_PATH,
    remote_url: process.env.IMAGE_REMOTE_URL,
}, null, 2));
JS
else
    $JSON_RUNTIME - <<'PY' > "$METADATA_PATH"
import json
import os

print(json.dumps({
    "platform": os.environ["IMAGE_PLATFORM_NAME"],
    "model": os.environ["IMAGE_MODEL"],
    "endpoint": os.environ["IMAGE_ENDPOINT"],
    "output_path": os.environ["IMAGE_OUTPUT_PATH"],
    "remote_url": os.environ["IMAGE_REMOTE_URL"],
}, ensure_ascii=False, indent=2))
PY
fi

printf '%s\n' "$OUTPUT_PATH"
