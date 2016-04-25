FROM ubuntu:trusty

# Required system packages
RUN apt-get update \
    && apt-get install -y \
        wget \
        unzip \
        ruby-dev \
        build-essential \
        perl \
        libreadline-dev \
        libncurses5-dev \
        libssl-dev \
        libpcre3-dev \
    && gem install fpm


ENV BUILD_DIR /build
RUN mkdir $BUILD_DIR $BUILD_DIR/root
WORKDIR $BUILD_DIR

ENV OPENRESTY_VERSION      1.9.7.4
ENV BUILD_NUM              1
ENV NGX_LUA_VERSION        0.10.2
ENV LUAJIT_VERSION_MAJ_MIN 2.1
ENV LUAJIT_VERSION         2.1.0-beta2
ENV LUAROCKS_VERSION       2.3.0

ENV ARCH amd64

# Download packages
RUN wget https://openresty.org/download/openresty-$OPENRESTY_VERSION.tar.gz \
    && tar xfz openresty-$OPENRESTY_VERSION.tar.gz \
    && wget https://github.com/openresty/lua-nginx-module/archive/v$NGX_LUA_VERSION.zip \
    && unzip v$NGX_LUA_VERSION.zip \
    && wget http://luajit.org/download/LuaJIT-$LUAJIT_VERSION.tar.gz \
    && tar xfz LuaJIT-$LUAJIT_VERSION.tar.gz \
    && wget https://keplerproject.github.io/luarocks/releases/luarocks-$LUAROCKS_VERSION.tar.gz \
    && tar xfz luarocks-$LUAROCKS_VERSION.tar.gz


# Compile and install openresty
RUN cd $BUILD_DIR/openresty-$OPENRESTY_VERSION \
    && rm -rf bundle/LuaJIT* \
    && mv $BUILD_DIR/LuaJIT-$LUAJIT_VERSION bundle/ \
    && ./configure \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-http_v2_module \
        #--with-debug \
        --with-pcre-jit \
        --with-cc-opt='-O2 -fstack-protector --param=ssp-buffer-size=4 -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2' \
        --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro' \
        --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --http-log-path=/var/log/nginx/access.log \
        --error-log-path=/var/log/nginx/error.log \
        --lock-path=/var/lock/nginx.lock \
        --pid-path=/run/nginx.pid \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --user=www-data \
        --group=www-data \
    && make -j4 \
    && make install DESTDIR=$BUILD_DIR/root


# Compile LuaRocks
RUN mkdir -p /usr/share/nginx && ln -s $BUILD_DIR/root/usr/share/nginx/luajit /usr/share/nginx/luajit \
    && cd $BUILD_DIR/luarocks-$LUAROCKS_VERSION \
    && ./configure \
        --prefix=/usr/share/nginx/luajit \
        --with-lua=/usr/share/nginx/luajit \
        --lua-suffix=jit-$LUAJIT_VERSION \
        --with-lua-include=/usr/share/nginx/luajit/include/luajit-$LUAJIT_VERSION_MAJ_MIN \
        --with-downloader=wget \
        --with-md5-checker=openssl \
    && make build \
    && make install DESTDIR=$BUILD_DIR/root \
    && rm -rf /usr/share/nginx

COPY scripts/* nginx-scripts/
COPY conf/* nginx-conf/


# Add extras to the build root
RUN cd $BUILD_DIR/root \
    && mkdir \
        etc/init.d \
        etc/logrotate.d \
        etc/nginx/sites-available \
        etc/nginx/sites-enabled \
        var/lib \
        var/lib/nginx \
    && mv usr/share/nginx/bin/resty usr/sbin/resty && rm -rf usr/share/nginx/bin \
    && mv usr/share/nginx/nginx/html usr/share/nginx/html && rm -rf usr/share/nginx/nginx \
    && rm etc/nginx/*.default \
    && cp $BUILD_DIR/nginx-scripts/init etc/init.d/nginx \
    && chmod +x etc/init.d/nginx \
    && cp $BUILD_DIR/nginx-conf/logrotate etc/logrotate.d/nginx \
    && cp $BUILD_DIR/nginx-conf/nginx.conf etc/nginx/nginx.conf \
    && cp $BUILD_DIR/nginx-conf/default etc/nginx/sites-available/default


# Build deb
RUN mkdir artifacts \
    && cd artifacts \
    && fpm -s dir -t deb \
    -n openresty \
    -v ${OPENRESTY_VERSION} \
    --iteration $BUILD_NUM \
    -C $BUILD_DIR/root \
    -p openresty_${OPENRESTY_VERSION}-${BUILD_NUM}_${ARCH}.deb \
    --description 'a high performance web server and a reverse proxy server' \
    --url 'http://openresty.org/' \
    --category httpd \
    --maintainer 'Greg Dallavalle <greg.dallavalle@ave81.com>' \
    # unzip/wget required for luarocks
    --depends wget \
    --depends unzip \
    --depends libncurses5 \
    --depends libreadline6 \
    --depends openssl \
    --deb-build-depends build-essential \
    --deb-build-depends perl \
    --deb-build-depends libreadline-dev \
    --deb-build-depends libncurses5-dev \
    --deb-build-depends libssl-dev \
    --deb-build-depends libpcre3-dev \
    --replaces 'nginx-full' \
    --provides 'nginx-full' \
    --conflicts 'nginx-full' \
    --conflicts 'nginx-common' \
    --replaces 'nginx-common' \
    --provides 'nginx-common' \
    --after-install $BUILD_DIR/nginx-scripts/postinstall \
    --before-install $BUILD_DIR/nginx-scripts/preinstall \
    --after-remove $BUILD_DIR/nginx-scripts/postremove \
    --before-remove $BUILD_DIR/nginx-scripts/preremove \
    etc run usr var
