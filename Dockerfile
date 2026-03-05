# ==========================================
# STAGE 1: Compilar FrankenPHP + WebDAV
# ==========================================
FROM dunglas/frankenphp:1.11.3-builder-php8.4 AS builder

COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy

ENV CGO_ENABLED=1 XCADDY_SETCAP=1 \
    XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx"

RUN export CGO_CFLAGS=$(php-config --includes) && \
    export CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" && \
    xcaddy build \
    --output /usr/local/bin/frankenphp \
    --with github.com/dunglas/frankenphp=./ \
    --with github.com/dunglas/frankenphp/caddy=./caddy/ \
    --with github.com/mholt/caddy-webdav

# ==========================================
# STAGE 2: Imagem Final (WordPress + SQLite + WebDAV)
# ==========================================
FROM dunglas/frankenphp:1.11.3-php8.4

RUN install-php-extensions gd intl zip opcache exif bcmath

RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 libsqlite3-dev wget unzip sudo less && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Instala o WordPress e configura Proxy e Pasta Dinâmica
RUN wget https://wordpress.org/latest.zip -O /tmp/wp.zip && \
    unzip /tmp/wp.zip -d /tmp/ && \
    cp -r /tmp/wordpress/* /app/public/ && \
    rm -rf /tmp/wp.zip /tmp/wordpress && \
    cp /app/public/wp-config-sample.php /app/public/wp-config.php && \
    sed -i "/That's all, stop editing!/i \
// Forçar HTTPS atrás de Proxy\n\
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos(\$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n\
// Mudar wp-content para o disco persistente\n\
define( 'WP_CONTENT_DIR', '/data/wp-content' );\n\
define( 'WP_CONTENT_URL', 'https://' . \$_SERVER['HTTP_HOST'] . '/wp-content' );\n" /app/public/wp-config.php

# Instala o driver do SQLite
RUN wget https://downloads.wordpress.org/plugin/sqlite-database-integration.zip -O /tmp/sqlite.zip && \
    unzip /tmp/sqlite.zip -d /app/public/wp-content/mu-plugins/ && \
    rm /tmp/sqlite.zip && \
    cp /app/public/wp-content/mu-plugins/sqlite-database-integration/db.copy /app/public/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/app\/public\/wp-content\/mu-plugins\/sqlite-database-integration/g' /app/public/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /app/public/wp-content/db.php

# Cria custom.ini COM A TRAVA DE SEGURANÇA (open_basedir)
RUN printf "upload_max_filesize = 500M\n\
post_max_size = 500M\n\
memory_limit = 512M\n\
max_execution_time = 300\n\
max_input_time = 300\n\
open_basedir = /app/public/:/data/:/tmp/\n\
opcache.enable = 1\n\
opcache.memory_consumption = 256\n\
opcache.interned_strings_buffer = 16\n\
opcache.max_accelerated_files = 10000\n\
opcache.revalidate_freq = 60\n\
opcache.save_comments = 1" > /usr/local/etc/php/conf.d/custom-php.ini

# Cria um Caddyfile Padrão (Agora ele aponta os estáticos para o /data/wp-content)
RUN printf "{\n\
    frankenphp\n\
    order php_server before file_server\n\
}\n\
:80 {\n\
    root * /app/public\n\
    encode zstd gzip\n\
    \n\
    # O Caddy precisa saber onde servir os estáticos (imagens/css) do WP agora\n\
    handle_path /wp-content/* {\n\
        root * /data/wp-content\n\
        file_server\n\
    }\n\
    \n\
    route /webdav/* {\n\
        basic_auth {\n\
            {\$WEBDAV_USER} {\$WEBDAV_HASH}\n\
        }\n\
        webdav {\n\
            root /data\n\
            prefix /webdav\n\
        }\n\
    }\n\
    \n\
    php_server\n\
    file_server\n\
}" > /etc/caddy/Caddyfile.default

# Script de Inicialização Simplificado (Sem Symlink)
RUN printf "#!/bin/sh\n\
# Estruturando o disco /data no primeiro boot\n\
if [ ! -d /data/wp-content ]; then\n\
    echo 'Preparando disco /data...'\n\
    mkdir -p /data/server\n\
    cp -a /app/public/wp-content /data/\n\
fi\n\
\n\
ARQUIVO_CADDY=\${CADDYFILE_NAME:-Caddyfile}\n\
if [ ! -f /data/server/\$ARQUIVO_CADDY ]; then\n\
    echo 'Criando Caddyfile...'\n\
    cp /etc/caddy/Caddyfile.default /data/server/\$ARQUIVO_CADDY\n\
fi\n\
\n\
exec frankenphp run --config /data/server/\$ARQUIVO_CADDY\n\
" > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

# Variáveis padrão
ENV WEBDAV_USER="wpfuse"
ENV WEBDAV_HASH="\$2a\$12\$eU7Q0R.6M7n3PqXqH.T2r.N5L5fT7rR0G5Y6W8mZ9nZ5gC1kO3vF2"
ENV CADDYFILE_NAME="Caddyfile"

RUN chown -R root:root /app/public /data && \
    chmod -R 777 /app/public

CMD ["/usr/local/bin/start.sh"]

WORKDIR /app/public
