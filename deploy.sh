#!/bin/bash

# --- 路径配置 ---
BASE_COMPOSE="./docker-compose.yml"
EXTRA_COMPOSE="./conf/default/docker-compose.yml"
EXTRA_ENV="./conf/default/docker.env"

# --- 参数收集 ---
PARAMS=()

# 1. 处理环境变量文件 (必须放在前面)
if [ -f "$EXTRA_ENV" ]; then
    PARAMS+=(--env-file "$EXTRA_ENV")
fi

# 2. 处理 Compose 文件合并
# 注意：一旦使用了 -f，就必须显式指定所有要用的 yml 文件，
# 因为 Docker Compose 不再会自动寻找当前目录下的 docker-compose.yml
if [ -f "$EXTRA_COMPOSE" ]; then
    PARAMS+=(-f "$BASE_COMPOSE" -f "$EXTRA_COMPOSE")
else
    # 如果没有额外的，也建议显式指定基础文件，避免歧义
    PARAMS+=(-f "$BASE_COMPOSE")
fi

# 3. 执行最终命令
# "$@" 透传自动化脚本传来的指令 (config, ps, pull, up 等)
exec docker compose "${PARAMS[@]}" "$@"