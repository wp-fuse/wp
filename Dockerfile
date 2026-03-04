# Usa a imagem base que JÁ TEM o FrankenPHP, Caddy e o cache do Sidekick pré-compilados
FROM wpeverywhere/frankenwp:latest-php8.3

# Instala ferramentas essenciais do SQLite e o WebDAV do Caddy via pacote
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 \
    libsqlite3-dev \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Baixa e injeta a extensão WebDAV diretamente através do utilitário oficial do Caddy
# Isso burla o xcaddy e o Go Module local!
RUN caddy add-package github.com/mholt/caddy-webdav

# Instala o driver do SQLite do WordPress
RUN wget https://downloads.wordpress.org/plugin/sqlite-database-integration.zip -O /tmp/sqlite.zip && \
    unzip /tmp/sqlite.zip -d /var/www/html/wp-content/mu-plugins/ && \
    rm /tmp/sqlite.zip

RUN cp /var/www/html/wp-content/mu-plugins/sqlite-database-integration/db.copy /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/var\/www\/html\/wp-content\/mu-plugins\/sqlite-database-integration/g' /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /var/www/html/wp-content/db.php

# Cria o php.ini customizado com as regras do OPcache
RUN printf "upload_max_filesize = 500M\n\
post_max_size = 500M\n\
memory_limit = 512M\n\
max_execution_time = 300\n\
max_input_time = 300\n\
opcache.enable = 1\n\
opcache.memory_consumption = 256\n\
opcache.interned_strings_buffer = 16\n\
opcache.max_accelerated_files = 10000\n\
opcache.revalidate_freq = 60\n\
opcache.save_comments = 1" > /usr/local/etc/php/conf.d/custom-php.ini

# Cria o arquivo de configuração do WebDAV
RUN printf "route /webdav/* {\n\
    basic_auth {\n\
        daniel \$2a\$14\$JDJhJDE0JElab2ZPM25zdXpG\n\
    }\n\
    webdav {\n\
        root /var/www/html/wp-content\n\
        prefix /webdav\n\
    }\n\
}" > /etc/caddy/webdav.caddy

# Configura as variáveis para ignorar o cache no painel e importar o WebDAV
ENV BYPASS_PATH_PREFIXES="/wp-admin,/wp-includes,/wp-json,/webdav"
ENV CACHE_LOC="/var/www/html/wp-content/cache"
ENV CADDY_SERVER_EXTRA_DIRECTIVES="import /etc/caddy/webdav.caddy"

# Ajusta permissões
RUN mkdir -p /var/www/html/wp-content/cache && \
    chown -R www-www-data /var/www/html/wp-content /etc/caddy/webdav.caddy

USER www-data
