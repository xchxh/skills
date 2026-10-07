#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '用法: %s --url URL --key API_KEY --model MODEL --prompt PROMPT [--platform local|openclaw|hermes] [--output OUTPUT_PATH] [--output-dir DIR] [--metadata METADATA_PATH]\n' "$0"
    printf '也可通过 VIDEO_API_URL、VIDEO_API_KEY、VIDEO_MODEL、VIDEO_PROMPT、VIDEO_PLATFORM、VIDEO_OUTPUT_PATH、VIDEO_OUTPUT_DIR、VIDEO_METADATA_PATH 环境变量传入。\n'
}

API_URL="${VIDEO_API_URL:-}"
API_KEY="${VIDEO_API_KEY:-}"
MODEL="${VIDEO_MODEL:-}"
PROMPT="${VIDEO_PROMPT:-}"
PLATFORM="${VIDEO_PLATFORM:-local}"
OUTPUT_PATH="${VIDEO_OUTPUT_PATH:-}"
OUTPUT_DIR="${VIDEO_OUTPUT_DIR:-}"
METADATA_PATH="${VIDEO_METADATA_PATH:-}"

# 视频特有参数，可通过环境变量进行覆盖
VIDEO_HEIGHT="${VIDEO_HEIGHT:-768}"
VIDEO_WIDTH="${VIDEO_WIDTH:-1152}"
VIDEO_NUM_FRAMES="${VIDEO_NUM_FRAMES:-121}"
VIDEO_FRAME_RATE="${VIDEO_FRAME_RATE:-24}"

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
    if [[ "$url" == */v1/videos ]]; then
        printf '%s' "$url"
    elif [[ "$url" == */v1 ]]; then
        printf '%s/videos' "$url"
    else
        printf '%s/v1/videos' "$url"
    fi
}

get_query_url() {
    local base_url="$1"
    local video_id="$2"
    local task_id="$3"
    local model="$4"
    
    if [[ "$base_url" == *agnes-ai.com* ]]; then
        local domain
        if [[ "$base_url" =~ ^(https?://[^/]+) ]]; then
            domain="${BASH_REMATCH[1]}"
        else
            domain="https://apihub.agnes-ai.com"
        fi
        printf '%s/agnesapi?video_id=%s&model_name=%s' "$domain" "$video_id" "$model"
    else
        if [[ "$base_url" == */v1/videos ]]; then
            printf '%s/%s' "$base_url" "$task_id"
        elif [[ "$base_url" == */v1 ]]; then
            printf '%s/videos/%s' "$base_url" "$task_id"
        else
            printf '%s/v1/videos/%s' "$base_url" "$task_id"
        fi
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
FILENAME="generated_$(date +%s).mp4"

if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="$(select_output_dir)/$FILENAME"
fi

if [ -z "$METADATA_PATH" ]; then
    METADATA_PATH="$(dirname "$OUTPUT_PATH")/$(basename "$OUTPUT_PATH" .mp4).json"
fi

export VIDEO_MODEL="$MODEL"
export VIDEO_PROMPT="$PROMPT"
export VIDEO_HEIGHT="$VIDEO_HEIGHT"
export VIDEO_WIDTH="$VIDEO_WIDTH"
export VIDEO_NUM_FRAMES="$VIDEO_NUM_FRAMES"
export VIDEO_FRAME_RATE="$VIDEO_FRAME_RATE"

if [ "$JSON_RUNTIME" = "node" ]; then
    REQUEST_BODY="$(node - <<'JS'
process.stdout.write(JSON.stringify({
    model: process.env.VIDEO_MODEL,
    prompt: process.env.VIDEO_PROMPT,
    height: parseInt(process.env.VIDEO_HEIGHT || "768", 10),
    width: parseInt(process.env.VIDEO_WIDTH || "1152", 10),
    num_frames: parseInt(process.env.VIDEO_NUM_FRAMES || "121", 10),
    frame_rate: parseInt(process.env.VIDEO_FRAME_RATE || "24", 10),
}));
JS
)"
else
    REQUEST_BODY="$($JSON_RUNTIME - <<'PY'
import json
import os

print(json.dumps({
    "model": os.environ["VIDEO_MODEL"],
    "prompt": os.environ["VIDEO_PROMPT"],
    "height": int(os.environ.get("VIDEO_HEIGHT", "768")),
    "width": int(os.environ.get("VIDEO_WIDTH", "1152")),
    "num_frames": int(os.environ.get("VIDEO_NUM_FRAMES", "121")),
    "frame_rate": int(os.environ.get("VIDEO_FRAME_RATE", "24")),
}, ensure_ascii=False))
PY
)"
fi

printf '向接口发送请求创建视频生成任务... Endpoint: %s\n' "$ENDPOINT" >&2
RESPONSE="$(curl -sS -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")"

export VIDEO_RESPONSE="$RESPONSE"
if [ "$JSON_RUNTIME" = "node" ]; then
    IDS="$(node - <<'JS' || true
try {
    const data = JSON.parse(process.env.VIDEO_RESPONSE);
    const videoId = data.video_id || data.id || "";
    const taskId = data.task_id || data.id || "";
    process.stdout.write(`${videoId}|${taskId}`);
} catch (e) {
    process.stdout.write("|");
}
JS
)"
else
    IDS="$($JSON_RUNTIME - <<'PY' || true
import json
import os

try:
    data = json.loads(os.environ["VIDEO_RESPONSE"])
    video_id = data.get("video_id") or data.get("id") or ""
    task_id = data.get("task_id") or data.get("id") or ""
    print(f"{video_id}|{task_id}")
except Exception:
    print("|")
PY
)"
fi

# 使用 IFS 分离 video_id 和 task_id
IFS='|' read -r VIDEO_ID TASK_ID <<< "$IDS"

if [ -z "$VIDEO_ID" ] && [ -z "$TASK_ID" ]; then
    printf '错误: 创建任务失败或未能从响应中解析出 ID。\n' >&2
    printf '原始响应: %s\n' "$RESPONSE" >&2
    exit 1
fi

printf '任务创建成功. Video ID: %s, Task ID: %s\n' "${VIDEO_ID:-无}" "${TASK_ID:-无}" >&2

QUERY_URL="$(get_query_url "$API_URL" "$VIDEO_ID" "$TASK_ID" "$MODEL")"
MAX_ATTEMPTS=120
ATTEMPT=0
FINAL_VIDEO_URL=""

printf '开始轮询任务状态, Query URL: %s\n' "$QUERY_URL" >&2

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    
    # 稍微等一下再查
    sleep 5
    
    QUERY_RESPONSE="$(curl -sS -X GET "$QUERY_URL" -H "Authorization: Bearer $API_KEY" || true)"
    
    if [ -z "$QUERY_RESPONSE" ]; then
        printf '[尝试 %d/%d] 请求查询接口失败，5秒后重试...\n' "$ATTEMPT" "$MAX_ATTEMPTS" >&2
        continue
    fi
    
    export VIDEO_QUERY_RESPONSE="$QUERY_RESPONSE"
    if [ "$JSON_RUNTIME" = "node" ]; then
        PARSED_STATUS="$(node - <<'JS' || true
try {
    const data = JSON.parse(process.env.VIDEO_QUERY_RESPONSE);
    const status = data.status || "";
    const videoUrl = data.video_url || data.url || (typeof data.remixed_from_video_id === 'string' && data.remixed_from_video_id.startsWith('http') ? data.remixed_from_video_id : "") || "";
    const errorMsg = data.error ? (typeof data.error === 'string' ? data.error : JSON.stringify(data.error)) : "";
    process.stdout.write(`${status}|${videoUrl}|${errorMsg}`);
} catch (e) {
    process.stdout.write(`parse_error||${e.message}`);
}
JS
)"
    else
        PARSED_STATUS="$($JSON_RUNTIME - <<'PY' || true
import json
import os

try:
    data = json.loads(os.environ["VIDEO_QUERY_RESPONSE"])
    status = data.get("status", "")
    video_url = data.get("video_url") or data.get("url") or ""
    if not video_url and isinstance(data.get("remixed_from_video_id"), str) and data["remixed_from_video_id"].startswith("http"):
        video_url = data["remixed_from_video_id"]
    error_obj = data.get("error")
    error_msg = ""
    if error_obj:
        error_msg = error_obj if isinstance(error_obj, str) else json.dumps(error_obj)
    print(f"{status}|{video_url}|{error_msg}")
except Exception as e:
    print(f"parse_error||{str(e)}")
PY
)"
    fi
    
    IFS='|' read -r STATUS REMOTE_URL ERROR_MSG <<< "$PARSED_STATUS"
    
    if [ "$STATUS" = "completed" ] || [ "$STATUS" = "succeeded" ]; then
        if [ -n "$REMOTE_URL" ]; then
            FINAL_VIDEO_URL="$REMOTE_URL"
            printf '[尝试 %d/%d] 视频生成成功! 视频地址: %s\n' "$ATTEMPT" "$MAX_ATTEMPTS" "$FINAL_VIDEO_URL" >&2
            break
        else
            printf '[尝试 %d/%d] 状态已完成，但未能提取到视频 URL。\n' "$ATTEMPT" "$MAX_ATTEMPTS" >&2
            printf '原始响应: %s\n' "$QUERY_RESPONSE" >&2
            exit 1
        fi
    elif [ "$STATUS" = "failed" ]; then
        printf '错误: 视频生成失败。错误信息: %s\n' "${ERROR_MSG:-无}" >&2
        printf '原始响应: %s\n' "$QUERY_RESPONSE" >&2
        exit 1
    elif [ "$STATUS" = "parse_error" ]; then
        printf '[尝试 %d/%d] 响应解析失败: %s. 5秒后重试...\n' "$ATTEMPT" "$MAX_ATTEMPTS" "$ERROR_MSG" >&2
    else
        printf '[尝试 %d/%d] 任务处理中, 状态: %s. 5秒后重试...\n' "$ATTEMPT" "$MAX_ATTEMPTS" "$STATUS" >&2
    fi
done

if [ -z "$FINAL_VIDEO_URL" ]; then
    printf '错误: 视频生成超时（已重试 %d 次）。\n' "$MAX_ATTEMPTS" >&2
    exit 1
fi

OUTPUT_DIRNAME="$(dirname "$OUTPUT_PATH")"
METADATA_DIRNAME="$(dirname "$METADATA_PATH")"
mkdir -p "$OUTPUT_DIRNAME" "$METADATA_DIRNAME"

printf '开始下载视频到: %s\n' "$OUTPUT_PATH" >&2
curl -sS -L "$FINAL_VIDEO_URL" -o "$OUTPUT_PATH"

if [ ! -s "$OUTPUT_PATH" ]; then
    printf '错误: 视频下载失败或文件为空。\n' >&2
    exit 1
fi

export VIDEO_ENDPOINT="$ENDPOINT"
export VIDEO_OUTPUT_PATH="$OUTPUT_PATH"
export VIDEO_METADATA_PATH="$METADATA_PATH"
export VIDEO_PLATFORM_NAME="$PLATFORM"
export VIDEO_REMOTE_URL="$FINAL_VIDEO_URL"

if [ "$JSON_RUNTIME" = "node" ]; then
    node - <<'JS' > "$METADATA_PATH"
process.stdout.write(JSON.stringify({
    platform: process.env.VIDEO_PLATFORM_NAME,
    model: process.env.VIDEO_MODEL,
    endpoint: process.env.VIDEO_ENDPOINT,
    output_path: process.env.VIDEO_OUTPUT_PATH,
    remote_url: process.env.VIDEO_REMOTE_URL,
}, null, 2));
JS
else
    $JSON_RUNTIME - <<'PY' > "$METADATA_PATH"
import json
import os

print(json.dumps({
    "platform": os.environ["VIDEO_PLATFORM_NAME"],
    "model": os.environ["VIDEO_MODEL"],
    "endpoint": os.environ["VIDEO_ENDPOINT"],
    "output_path": os.environ["VIDEO_OUTPUT_PATH"],
    "remote_url": os.environ["VIDEO_REMOTE_URL"],
}, ensure_ascii=False, indent=2))
PY
fi

printf '%s\n' "$OUTPUT_PATH"
