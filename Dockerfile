# 1. Compilação do FrankenPHP com Módulos Extras
FROM dunglas/frankenphp:latest-builder-php8.3 as builder

COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy
ENV CGO_ENABLED=1 XCADDY_SETCAP=1 XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath'

RUN xcaddy build \
    --output /usr/local/bin/frankenphp \
    --with github.com/dunglas/frankenphp=./ \
    --with github.com/dunglas/frankenphp/caddy=./caddy/ \
    --with github.com/dunglas/caddy-cbrotli \
    --with github.com/mholt/caddy-webdav # <--- Módulo WebDAV adicionado

# 2. Imagem Final (baseada no FrankenWP do StephenMiracle)
FROM stephenmiracle/frankenwp:latest-php8.3

# Substitui o binário original pelo nosso compilado com WebDAV
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Instala ferramentas do SQLite 
USER root
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 libsqlite3-dev wget unzip

# Instala o driver do SQLite
RUN wget https://downloads.wordpress.org/plugin/sqlite-database-integration.zip -O /tmp/sqlite.zip && \
    unzip /tmp/sqlite.zip -d /var/www/html/wp-content/mu-plugins/ && \
    rm /tmp/sqlite.zip

RUN cp /var/www/html/wp-content/mu-plugins/sqlite-database-integration/db.copy /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/var\/www\/html\/wp-content\/mu-plugins\/sqlite-database-integration/g' /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /var/www/html/wp-content/db.php

# Garante que o Caddy consiga ler e escrever os arquivos
RUN chown -R www-www-data /var/www/html/wp-content

USER www-data
