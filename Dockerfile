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

# Instala SOMENTE as extensões PHP essenciais (sem o MySQL)
RUN install-php-extensions \
    gd \
    intl \
    zip \
    opcache \
    exif \
    bcmath

# Instala SQLite e utilitários
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 libsqlite3-dev wget unzip sudo less && \
    rm -rf /var/lib/apt/lists/*

# Copia o binário com WebDAV
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Instala o WordPress e injeta a correção de Proxy (Mixed Content)
RUN wget https://wordpress.org/latest.zip -O /tmp/wp.zip && \
    unzip /tmp/wp.zip -d /tmp/ && \
    cp -r /tmp/wordpress/* /app/public/ && \
    rm -rf /tmp/wp.zip /tmp/wordpress && \
    # Cria o wp-config usando o wp-config-sample como base
    cp /app/public/wp-config-sample.php /app/public/wp-config.php && \
    # Injeta a regra do proxy logo antes de "That's all, stop editing!"
    sed -i "/That's all, stop editing!/i \
// Forçar HTTPS caso esteja atrás de um Reverse Proxy \n\
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos(\$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
}\n" /app/public/wp-config.php


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
open_basedir = /app/public/:/data/wp-content/:/tmp/\n\
opcache.enable = 1\n\
opcache.memory_consumption = 256\n\
opcache.interned_strings_buffer = 16\n\
opcache.max_accelerated_files = 10000\n\
opcache.revalidate_freq = 60\n\
opcache.save_comments = 1" > /usr/local/etc/php/conf.d/custom-php.ini

# Cria um Caddyfile Padrão
RUN printf "{\n\
    frankenphp\n\
    order php_server before file_server\n\
}\n\
:80 {\n\
    root * /app/public\n\
    encode zstd gzip\n\
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

# Script de Inicialização Compartimentado
RUN printf "#!/bin/sh\n\
# Se for o primeiro boot, a pasta /data estará vazia. Vamos estruturá-la!\n\
if [ ! -d /data/wp-content ]; then\n\
    echo 'Primeiro boot: Estruturando o disco /data...'\n\
    mkdir -p /data/server\n\
    cp -a /app/public/wp-content /data/\n\
fi\n\
\n\
# Deleta o wp-content efêmero e cria um atalho apontando pro disco persistente\n\
rm -rf /app/public/wp-content\n\
ln -s /data/wp-content /app/public/wp-content\n\
\n\
# Lida com o Caddyfile na pasta 'server' (que o PHP não tem permissão de ler)\n\
ARQUIVO_CADDY=\${CADDYFILE_NAME:-Caddyfile}\n\
if [ ! -f /data/server/\$ARQUIVO_CADDY ]; then\n\
    echo 'Criando \$ARQUIVO_CADDY protegido...'\n\
    cp /etc/caddy/Caddyfile.default /data/server/\$ARQUIVO_CADDY\n\
fi\n\
\n\
exec frankenphp run --config /data/server/\$ARQUIVO_CADDY\n\
" > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

# Variáveis padrão
ENV WEBDAV_USER="wpfuse"
ENV WEBDAV_HASH="\$2a\$14\$JDJhJDE0JElab2ZPM25zdXpG"
ENV CADDYFILE_NAME="Caddyfile"

RUN chown -R root:root /app/public && \
    chmod -R 777 /app/public

CMD ["/usr/local/bin/start.sh"]

WORKDIR /app/public


WORKDIR /app/public
