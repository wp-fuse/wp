#!/bin/sh

# 1) Prepara /data na primeira execução
if [ ! -d /data/wp-content ]; then
    echo 'Preparando disco /data...'
    mkdir -p /data/server
    cp -a /app/public/wp-content /data/
fi

ARQUIVO_CADDY=${CADDYFILE_NAME:-Caddyfile}
CADDY_DEST="/data/server/$ARQUIVO_CADDY"

# 2) Sempre constrói um Caddyfile fresco unindo o base e os snippets
cat /etc/caddy/Caddyfile.base > "$CADDY_DEST"
# Resolve o "import" do Caddy concatenando o snippet de WebDAV diretamente no arquivo
sed -i -e '/import \/etc\/caddy\/snippets\/webdav.caddy/r /etc/caddy/snippets/webdav.caddy' -e '/import \/etc\/caddy\/snippets\/webdav.caddy/d' "$CADDY_DEST"

# 3) Se tiver env vars, sobrescreve o placeholder no arquivo final
if [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_HASH" ]; then
    echo "Injetando credenciais do WebDAV a partir das variáveis de ambiente..."
    sed -i "s|placeholder_user|$WEBDAV_USER|g" "$CADDY_DEST"
    sed -i "s|pL4CeH0Ld3r-Ha5h-So-NaO-Usar|$WEBDAV_HASH|g" "$CADDY_DEST"
else
    echo "Aviso: WEBDAV_USER/WEBDAV_HASH ausentes. WebDAV bloqueado com credenciais de fabrica."
fi

exec frankenphp run --config "$CADDY_DEST"
