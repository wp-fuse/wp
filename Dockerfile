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

# Instala as extensões essenciais
RUN install-php-extensions gd intl zip opcache exif bcmath

# Utilitários do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 libsqlite3-dev wget unzip sudo less && \
    rm -rf /var/lib/apt/lists/*

# Traz o binário compilado
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Instalação do WordPress
RUN wget https://wordpress.org/latest.zip -O /tmp/wp.zip && \
    unzip /tmp/wp.zip -d /tmp/ && \
    cp -r /tmp/wordpress/* /app/public/ && \
    rm -rf /tmp/wp.zip /tmp/wordpress
    
COPY wp-config.php /app/public/wp-config.php

# Instala o Database Integration do SQLite
RUN wget https://downloads.wordpress.org/plugin/sqlite-database-integration.zip -O /tmp/sqlite.zip && \
    unzip /tmp/sqlite.zip -d /app/public/wp-content/mu-plugins/ && \
    rm /tmp/sqlite.zip && \
    cp /app/public/wp-content/mu-plugins/sqlite-database-integration/db.copy /app/public/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/app\/public\/wp-content\/mu-plugins\/sqlite-database-integration/g' /app/public/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /app/public/wp-content/db.php

# ==========================================
# INFRAESTRUTURA & ARQUIVOS DE SISTEMA
# ==========================================

# Copia configurações
COPY php.ini /usr/local/etc/php/conf.d/php.ini.base
COPY Caddyfile /etc/caddy/Caddyfile
COPY webdav.caddy /etc/caddy/snippets/webdav.caddy
COPY start.sh /usr/local/bin/start.sh

# Torna o script executável e ajusta permissões
RUN chmod +x /usr/local/bin/start.sh && \
    chown -R root:root /app/public /data /etc/caddy && \
    chmod -R 777 /app/public

# Avisa o motor do PHP para ler configurações DEPOIS do boot no disco persistente
ENV PHP_INI_SCAN_DIR=":/data/server/"

# Fallback para o nome do arquivo Caddy
ENV CADDYFILE_NAME="Caddyfile"

CMD ["/usr/local/bin/start.sh"]

WORKDIR /app/public
