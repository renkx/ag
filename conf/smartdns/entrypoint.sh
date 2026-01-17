#!/bin/sh

# 路径定义
INTERNAL_DIR="/etc/smartdns"
EXTERNAL_DIR="/conf/smartdns"
EXTRA_CONFS_DIR="$EXTERNAL_DIR/conf.d"
# 官方默认配置文件路径
FINAL_CONF="$INTERNAL_DIR/smartdns.conf"
# 脚本保底生成的内部模板
INTERNAL_TEMPLATE="$INTERNAL_DIR/smartdns-internal.conf"

# 创建内部目录
mkdir -p "$INTERNAL_DIR"

# --- 1. 处理 DDNS/分流规则 (ddns-rules.conf) ---
if [ -f "$EXTERNAL_DIR/ddns-rules.conf" ]; then
    echo "Using custom DDNS rules from $EXTERNAL_DIR/ddns-rules.conf"
    DDNS_CONF="$EXTERNAL_DIR/ddns-rules.conf"
else
    echo "Generating default DDNS rules..."
    DDNS_CONF="$INTERNAL_DIR/ddns-rules-default.conf"
    cat > "$DDNS_CONF" <<EOF
# DDNS 域名：关闭测速，降低 TTL，绑定到 ddns 组
domain-rules /20300808.xyz/ -no-cache -no-serve-expired -speed-check-mode none -rr-ttl 60 -nameserver ddns
domain-rules /20250618.xyz/ -no-cache -no-serve-expired -speed-check-mode none -rr-ttl 60 -nameserver ddns
domain-rules /rens.cc/ -no-cache -no-serve-expired -speed-check-mode none -rr-ttl 60 -nameserver ddns
domain-rules /jobuse.cn/ -no-cache -no-serve-expired -speed-check-mode none -rr-ttl 60 -nameserver ddns
EOF
fi

# --- 2. 处理上游配置 ---
# 优先寻找通用的外部上游配置 upstream.conf
if [ -f "$EXTERNAL_DIR/upstream.conf" ]; then
    echo "Using custom upstream config: $EXTERNAL_DIR/upstream.conf"
    UPSTREAM_FINAL="$EXTERNAL_DIR/upstream.conf"
else
    # 进入保底生成逻辑
    if [ "$SERVER_REGION" = "CN" ]; then
        UPSTREAM_FINAL="$INTERNAL_DIR/upstream-internal.conf"
        cat > "$UPSTREAM_FINAL" <<EOF
server-tls 223.5.5.5 -group china -group ddns
server-tls 120.53.53.53 -group china
EOF
    else
        UPSTREAM_FINAL="$INTERNAL_DIR/upstream-internal.conf"
        cat > "$UPSTREAM_FINAL" <<EOF
server-tls 8.8.8.8 -group foreign
server-tls 1.1.1.1 -group foreign -group ddns
EOF
    fi
    echo "No custom upstream found. Generated internal $SERVER_REGION defaults."
fi

# 根据地域决定默认测速模式 国内ping优先，国外tcp
[ "$SERVER_REGION" = "CN" ] && SPEED_MODE="ping,tcp:443,tcp:80" || SPEED_MODE="tcp:443,tcp:80,ping"

# --- 3. 确定并刷新主配置 smartdns.conf ---
if [ -f "$EXTERNAL_DIR/smartdns.conf" ]; then
    echo "Refreshing $FINAL_CONF from custom $EXTERNAL_DIR/smartdns.conf"
    cp "$EXTERNAL_DIR/smartdns.conf" "$FINAL_CONF"
else

    echo "Generating internal template and refreshing $FINAL_CONF..."
    # 始终生成/更新一个内部保底模板供参考
    cat > "$INTERNAL_TEMPLATE" <<EOF
# UDP
bind 127.0.0.1:53
# TCP
bind-tcp 127.0.0.1:53

# 日志级别 fatal,error,warn,notice,info,debug 默认error
log-level warn

# 缓存持久化
cache-persist yes
# 允许的最小TTL值
rr-ttl-min 600
# 开启过期缓存
serve-expired yes
# 三天失效
serve-expired-ttl 259200
# 此时间表示当缓存中域名TTL超时时，返回给客户端的TTL时间，让客户端在下列TTL时间后再次查询。
serve-expired-reply-ttl 3
# 开启域名预取
prefetch-domain yes
# 过期缓存在多长时间未访问，主动进行预先获取
serve-expired-prefetch-time 21600
# 周期保存 cache 文件时间
cache-checkpoint-time 86400

# 测速选项顺序 (基于地域变量)
speed-check-mode $SPEED_MODE

# 双栈 IP 优选
dualstack-ip-selection no
EOF
    cp "$INTERNAL_TEMPLATE" "$FINAL_CONF"
fi

# --- 4. 有序汇编配置 ---
{
    echo ""
    echo "# --- Start of Automatically Appended Modules ---"
    echo "conf-file $UPSTREAM_FINAL"
    echo "conf-file $DDNS_CONF"

    # 只有当宿主机挂载的 conf.d 目录存在时才进行扫描
    if [ -d "$EXTRA_CONFS_DIR" ]; then
        echo "Scanning extra configurations in $EXTRA_CONFS_DIR..." >&2
        # -maxdepth 1: 不递归子目录; -type f: 只匹配文件; -name "*.conf": 匹配后缀
        find "$EXTRA_CONFS_DIR" -maxdepth 1 -type f -name "*.conf" | sort | while read -r f; do
            echo "conf-file $f"
        done
    else
        echo "Notice: Extra config directory $EXTRA_CONFS_DIR not found, skipping." >&2
    fi

    echo "# --- End of Automatically Appended Modules ---"
} >> "$FINAL_CONF"

# --- 启动前打印最终配置 ---
echo "========================================"
echo "   FINAL SMARTDNS CONFIGURATION        "
echo "========================================"
cat "$FINAL_CONF"
echo "========================================"

# --- 5. 启动 ---
echo "SmartDNS starting with $SERVER_REGION mode..."
exec /usr/sbin/smartdns -f -x -c "$FINAL_CONF"