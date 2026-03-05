#!/bin/sh

# 1) Prepara a pasta /data na primeira execução
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

# Define qual nome o Caddy vai usar para buscar as configurações
ARQUIVO_CADDY=${CADDYFILE_NAME:-Caddyfile}
CADDY_DEST="/data/server/$ARQUIVO_CADDY"

# 2) Sempre constrói um Caddyfile fresco a partir da imagem
cat /etc/caddy/Caddyfile > "$CADDY_DEST"
# Injeta as regras do WebDAV fisicamente dentro do arquivo final 
sed -i -e '/import \/etc\/caddy\/snippets\/webdav.caddy/r /etc/caddy/snippets/webdav.caddy' -e '/import \/etc\/caddy\/snippets\/webdav.caddy/d' "$CADDY_DEST"

# 3) Processa a Autenticação
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

# 4) Executa o servidor
exec frankenphp run --config "$CADDY_DEST"
