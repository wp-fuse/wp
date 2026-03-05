#!/bin/sh

# 1) Prepara o disco persistente /data na primeira execução
if [ ! -d /data/wp-content ]; then
    echo 'Preparando disco persistente /data...'
    mkdir -p /data/server
    cp -a /app/public/wp-content /data/
fi

# Copia o php.ini customizado para o disco se ele não existir
if [ ! -f /data/server/php.ini ]; then
    echo 'Criando php.ini editavel no disco...'
    cp /usr/local/etc/php/conf.d/php.ini.base /data/server/php.ini
fi

# 2) Move o wp-config.php para o disco persistente
if [ ! -e /data/server/wp-config.php ]; then
    echo 'Movendo wp-config.php para a pasta de configuracoes...'
    cp /app/public/wp-config.php /data/server/wp-config.php
fi

# 3) Garante que o arquivo público seja SEMPRE um symlink apontando para o disco
# Remove o que quer que esteja lá (seja arquivo original ou link quebrado) e recria o link
rm -f /app/public/wp-config.php
ln -sf /data/server/wp-config.php /app/public/wp-config.php

# 4) Processa a infraestrutura do Caddy
ARQUIVO_CADDY=${CADDYFILE_NAME:-Caddyfile}
CADDY_DEST="/data/server/$ARQUIVO_CADDY"

cat /etc/caddy/Caddyfile > "$CADDY_DEST"
sed -i -e '/import \/etc\/caddy\/snippets\/webdav.caddy/r /etc/caddy/snippets/webdav.caddy' -e '/import \/etc\/caddy\/snippets\/webdav.caddy/d' "$CADDY_DEST"

# 5) Processa a Autenticacao
if [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_HASH" ]; then
    echo "Injetando credenciais do WebDAV a partir das variáveis de ambiente"
    sed -i "s|placeholder_user|$WEBDAV_USER|g" "$CADDY_DEST"
    sed -i "s|pL4CeH0Ld3r-Ha5h-So-NaO-Usar|$WEBDAV_HASH|g" "$CADDY_DEST"
else
    echo "Aviso: Senhas ausentes. Trancando WebDAV com chaves aleatórias únicas..."

    # Gera um usuário aleatório e uma senha aleatória de 32 caracteres via urandom do kernel
    RANDOM_USER=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    RANDOM_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
    RANDOM_HASH=$(frankenphp hash-password --plaintext "$RANDOM_PASS")

    # Injeta os valores gerados dinamicamente no arquivo
    sed -i "s|placeholder_user|$RANDOM_USER|g" "$CADDY_DEST"
    sed -i "s|pL4CeH0Ld3r-Ha5h-So-NaO-Usar|$RANDOM_HASH|g" "$CADDY_DEST"
fi

# 6) Executa o servidor
exec frankenphp run --config "$CADDY_DEST"
