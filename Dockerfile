# ==========================================
# STAGE 1: Compilar FrankenPHP + WebDAV
# ==========================================
FROM dunglas/frankenphp:latest-builder-php8.4 AS builder

# Instala a extensão WebDAV de forma oficial
RUN xcaddy build \
    --output /usr/local/bin/frankenphp \
    --with github.com/dunglas/frankenphp=./ \
    --with github.com/dunglas/frankenphp/caddy=./caddy/ \
    --with github.com/mholt/caddy-webdav

# ==========================================
# STAGE 2: Imagem Final (WordPress + SQLite + WebDAV)
# ==========================================
FROM dunglas/frankenphp:latest-php8.4

# Instala as extensões PHP essenciais para o WordPress funcionar (GD, Zip, OPcache, etc)
RUN install-php-extensions \
    mysqli \
    pdo_mysql \
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

# Substitui o FrankenPHP pelo nosso compilado com WebDAV
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Baixa o WordPress oficial mais recente e joga na pasta correta
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

# Cria o php.ini com as regras de alta performance
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

# Cria o arquivo de configuração do WebDAV (Substitua daniel e o hash pela sua senha!)
RUN printf "route /webdav/* {\n\
    basic_auth {\n\
        daniel \$2a\$14\$JDJhJDE0JElab2ZPM25zdXpG\n\
    }\n\
    webdav {\n\
        root /app/public/wp-content\n\
        prefix /webdav\n\
    }\n\
}" > /etc/caddy/webdav.caddy

# Configura o Servidor Caddy
ENV SERVER_NAME=":80"
ENV CADDY_SERVER_EXTRA_DIRECTIVES="import /etc/caddy/webdav.caddy"

# Garante permissões do usuário interno do FrankenPHP (que não é o www-data padrão)
RUN chown -R root:root /app/public /etc/caddy/webdav.caddy && \
    chmod -R 777 /app/public

# O FrankenPHP usa a pasta /app/public em vez de /var/www/html
WORKDIR /app/public
