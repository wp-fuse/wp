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

# Instala o WordPress
RUN wget https://wordpress.org/latest.zip -O /tmp/wp.zip && \
    unzip /tmp/wp.zip -d /tmp/ && \
    cp -r /tmp/wordpress/* /app/public/ && \
    rm -rf /tmp/wp.zip /tmp/wordpress

# Instala o driver do SQLite
RUN wget https://downloads.wordpress.org/plugin/sqlite-database-integration.zip -O /tmp/sqlite.zip && \
    unzip /tmp/sqlite.zip -d /app/public/wp-content/mu-plugins/ && \
    rm /tmp/sqlite.zip && \
    cp /app/public/wp-content/mu-plugins/sqlite-database-integration/db.copy /app/public/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/app\/public\/wp-content\/mu-plugins\/sqlite-database-integration/g' /app/public/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /app/public/wp-content/db.php

# Cria um Caddyfile Padrão (Fica salvo no sistema apenas como backup/molde)
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
            root /app/public/wp-content\n\
            prefix /webdav\n\
        }\n\
    }\n\
    \n\
    php_server\n\
    file_server\n\
}" > /etc/caddy/Caddyfile.default

# Script de Inicialização (1 Único Volume)
RUN printf "#!/bin/sh\n\
# A pasta wp-content já será persistente, criamos a subpasta config nela\n\
mkdir -p /app/public/wp-content/caddy\n\
\n\
ARQUIVO_CADDY=\${CADDYFILE_NAME:-Caddyfile}\n\
\n\
if [ ! -f /app/public/wp-content/caddy/\$ARQUIVO_CADDY ]; then\n\
    echo 'Criando \$ARQUIVO_CADDY no disco persistente wp-content...'\n\
    cp /etc/caddy/Caddyfile.default /app/public/wp-content/caddy/\$ARQUIVO_CADDY\n\
fi\n\
\n\
# Inicia lendo dentro do único volume do wp-content\n\
exec frankenphp run --config /app/public/wp-content/caddy/\$ARQUIVO_CADDY\n\
" > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

# Variáveis padrão de Fallback
ENV WEBDAV_USER="daniel"
ENV WEBDAV_HASH="\$2a\$14\$JDJhJDE0JElab2ZPM25zdXpG"
ENV CADDYFILE_NAME="Caddyfile"

RUN chown -R root:root /app/public && \
    chmod -R 777 /app/public

CMD ["/usr/local/bin/start.sh"]

WORKDIR /app/public
