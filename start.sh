#!/bin/sh

# 1) Prepara a pasta /data na primeira execução
if [ ! -d /data/wp-content ]; then
    echo 'Preparando disco persistente /data...'
    mkdir -p /data/server
    cp -a /app/public/wp-content /data/
fi

# Define qual nome o Caddy vai usar para buscar as configurações
ARQUIVO_CADDY=${CADDYFILE_NAME:-Caddyfile}
CADDY_DEST="/data/server/$ARQUIVO_CADDY"

# 2) Sempre constrói um Caddyfile fresco a partir da imagem para garantir atualizações
cat /etc/caddy/Caddyfile > "$CADDY_DEST"
# Injeta as regras do WebDAV fisicamente dentro do arquivo final 
sed -i -e '/import \/etc\/caddy\/snippets\/webdav.caddy/r /etc/caddy/snippets/webdav.caddy' -e '/import \/etc\/caddy\/snippets\/webdav.caddy/d' "$CADDY_DEST"

# 3) Processa a Autenticação
if [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_HASH" ]; then
    echo "Injetando credenciais do WebDAV a partir do Magic Containers..."
    sed -i "s|placeholder_user|$WEBDAV_USER|g" "$CADDY_DEST"
    sed -i "s|pL4CeH0Ld3r-Ha5h-So-NaO-Usar|$WEBDAV_HASH|g" "$CADDY_DEST"
else
    echo "Aviso: Senhas ausentes. WebDAV permanecerá selado com credenciais de fábrica."
fi

# 4) Executa o servidor
exec frankenphp run --config "$CADDY_DEST"
