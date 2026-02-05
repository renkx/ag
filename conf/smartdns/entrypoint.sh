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
server-tcp 180.184.1.1 -bootstrap-dns
server-tcp 101.226.4.6 -bootstrap-dns
server-tcp 2400:3200::1 -bootstrap-dns
server-tcp 2400:3200:baba::1 -bootstrap-dns

server-tls dot.360.cn -fallback
server-quic dns.alidns.com -fallback
server-https https://doh.360.cn/dns-query -fallback

server-tls dns.alidns.com -group ddns
server-tls dot.pub
server-https https://dns.alidns.com/dns-query
server-https https://doh.pub/dns-query
EOF
    else
        UPSTREAM_FINAL="$INTERNAL_DIR/upstream-internal.conf"
        cat > "$UPSTREAM_FINAL" <<EOF
server-tcp 1.1.1.1 -bootstrap-dns
server-tcp 8.8.8.8 -bootstrap-dns
server-tcp 2001:4860:4860::8888 -bootstrap-dns
server-tcp 2001:4860:4860::8844 -bootstrap-dns

server-tls one.one.one.one -fallback
server-tls dns.quad9.net -fallback
server-https https://1.1.1.1/dns-query -fallback

server-tls dns.cloudflare.com -group ddns
server-tls dns.google
server-https https://dns.cloudflare.com/dns-query -group ddns
server-https https://dns.google/dns-query
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

# 3.2万条缓存
cache-size 32768
# 允许返回给客户的最大IP数量
max-reply-ip-num 16

# 开启域名预取
prefetch-domain yes

# 开启过期缓存
serve-expired yes
# 过期缓存最长只保留 600 秒
# 超过秒数没更新的数据直接丢弃，强制重新查询，确保 IP 不会太旧
serve-expired-ttl 600
# 此时间表示当缓存中域名TTL超时时，返回给客户端的TTL时间，让客户端在下列TTL时间后再次查询。
serve-expired-reply-ttl 3
# 过期缓存在 300 秒 未访问时，才停止预取
# 或者理解为：只要这个记录在 300 秒 内被访问过，SmartDNS 就会尝试去更新它
serve-expired-prefetch-time 300

# 不锁定最小TTL值，否则会好心办坏事
# rr-ttl-min 1
# 返回的最大值不成超过这个秒数
rr-ttl-max 3600
# 这样即使 CDN 节点发生偏移，设备最多 1 分钟就会回过神来重查
rr-ttl-reply-max 60

# 缓存持久化
cache-persist yes
# 缓存持久化文件路径
cache-file /var/cache/smartdns.cache
# 运行期间每隔一小时保存一次（防止意外断电丢失）
cache-checkpoint-time 3600

# 测速选项顺序 (基于地域变量)
speed-check-mode $SPEED_MODE
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