FROM alpine:3.14

MAINTAINER renkx <m@renkx.com>

ENV NGINX_VERSION 1.22.0
ENV PCRE_VERSION 8.45

RUN CONFIG="\
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --user=nginx \
        --group=nginx \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module \
        --with-http_v2_module \
        --with-pcre=/usr/src/pcre-$PCRE_VERSION \
        --add-module=/usr/src/ngx_healthcheck_module/ \
    " \
    && addgroup -g 1000 -S nginx \
    && adduser -S -D -H -u 1000 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    # --virtual .build-deps 临时 后续统一指令删除安装包
    && apk add --no-cache --virtual .build-deps \
    curl gcc g++ make \
    # nginx的http_gzip_module需要这个
    zlib-dev \
    # nginx ssl需要用
    openssl-dev \
    # 安装github项目用到
    git \
    # 打补丁用的
    patch \
    # 创建/usr/src目录
    && mkdir -p /usr/src \
    # 下载nginx安装包
    && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
    # 解压nginx到/usr/src
    && tar -zxC /usr/src -f nginx.tar.gz \
    # 删除原nginx压缩文件
    && rm nginx.tar.gz \
    # 下载正则表达式模块pcre Nginx URL重定向用到（原下载 https://ftp.pcre.org/pub/pcre/pcre-$PCRE_VERSION.tar.gz ）
    && curl -fSL https://udomain.dl.sourceforge.net/project/pcre/pcre/$PCRE_VERSION/pcre-$PCRE_VERSION.tar.gz -o pcre.tar.gz \
    && tar -zxC /usr/src -f pcre.tar.gz \
    && rm pcre.tar.gz \
    # 下载nginx主动监测模块
    && mkdir -p /usr/src/ngx_healthcheck_module/ \
    && git clone https://github.com/zhouchangxun/ngx_healthcheck_module.git /usr/src/ngx_healthcheck_module/ \
    # 进入待编译的nginx目录
    && cd /usr/src/nginx-$NGINX_VERSION \
    # 打补丁 nginx主动监测模块
    && patch -p1 < /usr/src/ngx_healthcheck_module/nginx_healthcheck_for_nginx_1.19+.patch \
    && ./configure $CONFIG \
    # getconf _NPROCESSORS_ONLN 表示内核数量是多少个 表示有多少个核数就运行多少个任务
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    # 删除默认html
    && rm -rf /etc/nginx/html/ \
    # 创建 nginx 配置目录
    && mkdir /etc/nginx/conf.d/ \
    # 创建html默认页面的目录
    && mkdir -p /usr/share/nginx/html/ \
    # install类似cp，install允许你控制目标文件的属性
    && install -m644 html/index.html /usr/share/nginx/html/ \
    && install -m644 html/50x.html /usr/share/nginx/html/ \
    # strip命令用于脱掉文件的衣服,文件会变小
    && strip /usr/sbin/nginx* \
    # && strip /usr/lib/nginx/modules/*.so \
    # 删除nginx安装文件
    && rm -rf /usr/src/nginx-$NGINX_VERSION \
    # 删除正则表达式模块pcre
    && rm -rf /usr/src/pcre-$PCRE_VERSION \
    # 删除nginx主动监测目录
    && rm -rf /usr/src/ngx_healthcheck_module \
    # 删除安装的工具
    && apk del .build-deps \
    # 安装并设置时区
    && apk --no-cache add tzdata \
    && cp "/usr/share/zoneinfo/Asia/Shanghai" /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
# create a docker-entrypoint.d directory
    && mkdir /docker-entrypoint.d

COPY docker-entrypoint.sh /
COPY 10-listen-on-ipv6-by-default.sh /docker-entrypoint.d
COPY 20-envsubst-on-templates.sh /docker-entrypoint.d
COPY 30-tune-worker-processes.sh /docker-entrypoint.d
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]