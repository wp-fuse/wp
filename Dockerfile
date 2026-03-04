# 1. Compilação do FrankenPHP com Módulos Extras
FROM dunglas/frankenphp:latest-builder-php8.3 AS builder

# Instala o git para podermos baixar o módulo de cache original
RUN apt-get update && apt-get install -y git

# Copia a ferramenta xcaddy
COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy

# Variáveis do FrankenPHP
ENV CGO_ENABLED=1 XCADDY_SETCAP=1 XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath'

# Clona o repositório do FrankenWP original e extrai apenas a pasta do Sidekick Cache
RUN git clone https://github.com/StephenMiracle/frankenwp.git /tmp/frankenwp && \
    cp -r /tmp/frankenwp/sidekick/middleware/cache ./cache

# Compila o binário com o Cache e o WebDAV
RUN xcaddy build \
    --output /usr/local/bin/frankenphp \
    --with github.com/dunglas/frankenphp=./ \
    --with github.com/dunglas/frankenphp/caddy=./caddy/ \
    --with github.com/dunglas/caddy-cbrotli \
    --with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=./cache \
    --with github.com/mholt/caddy-webdav

# 2. Imagem Final (baseada no FrankenWP do StephenMiracle)
FROM wpeverywhere/frankenwp:latest-php8.3

# Substitui o binário original pelo nosso compilado com WebDAV
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Instala ferramentas do SQLite (Como root)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 libsqlite3-dev wget unzip

# Instala o driver do SQLite
RUN wget https://downloads.wordpress.org/plugin/sqlite-database-integration.zip -O /tmp/sqlite.zip && \
    unzip /tmp/sqlite.zip -d /var/www/html/wp-content/mu-plugins/ && \
    rm /tmp/sqlite.zip

RUN cp /var/www/html/wp-content/mu-plugins/sqlite-database-integration/db.copy /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_IMPLEMENTATION_FOLDER_PATH}/\/var\/www\/html\/wp-content\/mu-plugins\/sqlite-database-integration/g' /var/www/html/wp-content/db.php && \
    sed -i 's/{SQLITE_PLUGIN}/WP_PLUGIN_DIR\/SQLITE_MAIN_FILE/g' /var/www/html/wp-content/db.php

# Cria o arquivo php.ini via echo direto no ambiente do contêiner
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

# Cria o arquivo do WebDAV via echo (com a senha de teste)
RUN printf "route /webdav/* {\n\
    basic_auth {\n\
        daniel \$2a\$14\$JDJhJDE0JElab2ZPM25zdXpG\n\
    }\n\
    webdav {\n\
        root /var/www/html/wp-content\n\
        prefix /webdav\n\
    }\n\
}" > /etc/caddy/webdav.caddy

# Manda o Caddy ler as regras do WebDAV
ENV CADDY_SERVER_EXTRA_DIRECTIVES="import /etc/caddy/webdav.caddy"

# Ignora cache no painel de admin, nos arquivos principais, e no WebDAV
ENV BYPASS_PATH_PREFIX="/wp-admin,/wp-includes,/wp-json,/webdav"
ENV CACHE_LOC="/var/www/html/wp-content/cache"

# Garante que as pastas que precisam de gravação do site tenham as permissões corretas
RUN mkdir -p /var/www/html/wp-content/cache && \
    chown -R www-www-data /var/www/html/wp-content

# Passa o controle para o usuário seguro do servidor final
USER www-data
