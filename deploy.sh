#!/bin/bash

# --- 路径配置 ---
BASE_ENV="./.env"
EXTRA_ENV="./conf/default/docker.env"
BASE_COMPOSE="./docker-compose.yml"
EXTRA_COMPOSE="./conf/default/docker-compose.yml"

PARAMS=()

# --- 1. 处理环境变量文件 (注意顺序：后加载的覆盖先加载的) ---
# 先加载根目录默认 .env
#if [ -f "$BASE_ENV" ]; then
#    PARAMS+=(--env-file "$BASE_ENV")
#fi

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

# --- 3. 执行 ---
log_msg="Executing: docker compose ${PARAMS[*]} $*"
# 最终生成的参数
echo "$log_msg"

exec docker compose "${PARAMS[@]}" "$@"