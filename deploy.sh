#!/bin/bash

# 获取脚本真实的物理路径，并进入该目录
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# --- 路径配置 ---
BASE_ENV="./default.env"
EXTRA_ENV="./conf/default/docker.env"
BASE_COMPOSE="./docker-compose.yml"
EXTRA_COMPOSE="./conf/default/docker-compose.yml"

PARAMS=()

# --- 1. 处理环境变量文件 (注意顺序：后加载的覆盖先加载的) ---
# 先加载根目录默认 .env
if [ -f "$BASE_ENV" ]; then
    PARAMS+=(--env-file "$BASE_ENV")
fi

# 再加载自定义环境 .env (如果有的话，它会覆盖 BASE_ENV 中的同名变量)
if [ -f "$EXTRA_ENV" ]; then
    PARAMS+=(--env-file "$EXTRA_ENV")
fi

# --- 2. 处理 Compose 文件合并 ---
if [ -f "$EXTRA_COMPOSE" ]; then
    PARAMS+=(-f "$BASE_COMPOSE" -f "$EXTRA_COMPOSE")
else
    PARAMS+=(-f "$BASE_COMPOSE")
fi

# 最终生成的参数，日志重定向到 stderr (标准错误流)，否则会被外部调用获取到错误信息
echo "Executing: docker compose ${PARAMS[*]} $*" >&2

# --- 3. 执行 ---
exec docker compose "${PARAMS[@]}" "$@"