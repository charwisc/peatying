#!/bin/bash
# Despliega (o actualiza) la app en el servidor. Se puede ejecutar las veces que haga falta.
# Uso:  deploy.sh <endpoint-de-RDS> [etiqueta-de-la-imagen]
set -euo pipefail

DB_HOST="$1"
APP_TAG="${2:-latest}"
REGION=eu-west-1
# El número de cuenta lo pregunta el propio servidor (con su rol): así no está escrito en el repositorio.
REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com
cd /opt/ragpeat

# Lee un parámetro cifrado de Parameter Store. Puede hacerlo gracias al ROL del servidor:
# aquí no hay ninguna clave escrita, el servidor se identifica ante AWS por ser quien es.
param() {
  aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption --query Parameter.Value --output text
}

# .env con los secretos: solo legible por root (chmod 600) y nunca sale del servidor.
# sslmode=verify-full: la conexión con RDS va cifrada y la app comprueba que el certificado es de AWS y de ESE
# servidor (no solo "algún cifrado"): nadie puede hacerse pasar por la base de datos.
umask 077
cat > .env <<EOF
DB_URL=jdbc:postgresql://${DB_HOST}:5432/ragpeat?sslmode=verify-full&sslrootcert=/app/certs/rds-ca.pem
DB_PASSWORD=$(param /ragpeat/db-password)
ANTHROPIC_API_KEY=$(param /ragpeat/anthropic-api-key)
VOYAGE_API_KEY=$(param /ragpeat/voyage-api-key)
ADMIN_TOKEN=$(param /ragpeat/admin-token 2>/dev/null || true)
APP_TAG=${APP_TAG}
REGISTRY=${REGISTRY}
EOF
# APP_TAG también en .env: así cualquier "docker compose run ..." posterior (stats, index...) usa
# la versión desplegada y no la imagen "latest", que es antigua.

# Certificados de las autoridades de RDS (para verify-full). AWS los va renovando: se bajan en cada despliegue.
# Si falla la descarga, seguimos con los que hubiera; si no hay ninguno, la app no podría conectar: paramos aquí.
mkdir -p certs
if curl -fsS "https://truststore.pki.rds.amazonaws.com/${REGION}/${REGION}-bundle.pem" -o certs/rds-ca.pem.new \
    && grep -q 'BEGIN CERTIFICATE' certs/rds-ca.pem.new; then
  mv certs/rds-ca.pem.new certs/rds-ca.pem
else
  rm -f certs/rds-ca.pem.new
  [ -s certs/rds-ca.pem ] || { echo "Error: no se pudieron bajar los certificados de RDS"; exit 1; }
  echo "Aviso: no se pudieron renovar los certificados de RDS; se usan los anteriores"
fi
# umask 077 los dejaría solo para root: la app corre como otro usuario y tiene que poder leerlos (no son secretos).
chmod 755 certs
chmod 644 certs/rds-ca.pem

# Base de datos DB-IP Lite (país y ciudad de una IP; CC BY 4.0). Sale una nueva cada mes: la bajamos
# si no está o si tiene más de 35 días. Si falla la descarga, seguimos con la que hubiera (o sin ninguna).
GEO=data/geo/dbip-city-lite.mmdb
if [ ! -f "$GEO" ] || [ -n "$(find "$GEO" -mtime +35)" ]; then
  mkdir -p data/geo
  if curl -sfL "https://download.db-ip.com/free/dbip-city-lite-$(date -u +%Y-%m).mmdb.gz" | gunzip > "$GEO.new"; then
    mv "$GEO.new" "$GEO"
  else
    rm -f "$GEO.new"
    echo "Aviso: no se pudo descargar DB-IP Lite"
  fi
fi
# data/ es solo del usuario de la app (UID 10001, ver Dockerfile).
mkdir -p data
chown -R 10001:10001 data
chmod 750 data
# umask 077 la dejaría solo para root: la app tiene que poder leerla.
chmod 755 data/geo 2>/dev/null || true
chmod 644 "$GEO" 2>/dev/null || true

# Iniciar sesión en ECR (también con el rol) y arrancar la versión pedida.
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
export APP_TAG
docker compose pull
docker compose up -d --remove-orphans
# Si el Caddyfile cambió, Caddy no se entera solo: se lo recargamos (sin cortar las conexiones abiertas).
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
docker image prune -f      # borra imágenes viejas que ya no se usan, para no llenar el disco

docker compose ps
