#!/bin/sh

# 1) Prepara o disco persistente /data na primeira execução
if [ ! -d /data/wp-content ]; then
    echo 'Preparando disco persistente /data...'
    mkdir -p /data/server
    cp -a /app/public/wp-content /data/
fi

# Copia o php.ini customizado para o disco
if [ ! -f /data/server/php.ini ]; then
    echo 'Criando php.ini no disco...'
    cp /usr/local/etc/php/conf.d/php.ini.base /data/server/php.ini
fi

# 2) Constroi o wp-config.php
if [ ! -f /data/server/wp-config.php ]; then
    echo 'Construindo o wp-config.php persistente...'
    curl -s https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/salts.txt
    cp /app/public/wp-config.base.php /data/server/wp-config.php
    sed -i -e '/REPLACE_WP_SALTS_HERE/r /tmp/salts.txt' -e '/REPLACE_WP_SALTS_HERE/d' /data/server/wp-config.php
    rm -f /tmp/salts.txt
fi

# Cria o Symlink
rm -f /app/public/wp-config.base.php
rm -f /app/public/wp-config.php
ln -sf /data/server/wp-config.php /app/public/wp-config.php

# 3) Processa a infraestrutura do Caddy
ARQUIVO_CADDY=${CADDYFILE_NAME:-Caddyfile}
CADDY_DEST="/data/server/$ARQUIVO_CADDY"

cat /etc/caddy/Caddyfile > "$CADDY_DEST"
sed -i -e '/import \/etc\/caddy\/snippets\/webdav.caddy/r /etc/caddy/snippets/webdav.caddy' -e '/import \/etc\/caddy\/snippets\/webdav.caddy/d' "$CADDY_DEST"

# 4) Processa a Autenticacao
if [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_HASH" ]; then
    echo "Injetando credenciais do WebDAV a partir das variáveis de ambiente"
    sed -i "s|placeholder_user|$WEBDAV_USER|g" "$CADDY_DEST"
    sed -i "s|placeholder_hash|$WEBDAV_HASH|g" "$CADDY_DEST"
else
    echo "Aviso: Senhas ausentes. Trancando WebDAV com chaves aleatórias únicas..."

    # Gera um usuário aleatório e uma senha aleatória de 32 caracteres via urandom do kernel
    RANDOM_USER=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    RANDOM_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
    RANDOM_HASH=$(frankenphp hash-password --plaintext "$RANDOM_PASS")

    # Injeta os valores gerados dinamicamente no arquivo
    sed -i "s|placeholder_user|$RANDOM_USER|g" "$CADDY_DEST"
    sed -i "s|placeholder_hash|$RANDOM_HASH|g" "$CADDY_DEST"
fi

# 5) Executa o servidor
exec frankenphp run --config "$CADDY_DEST"
