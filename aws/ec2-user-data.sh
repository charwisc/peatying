#!/bin/bash
# Script que el servidor EC2 ejecuta UNA vez, al arrancar por primera vez ("user data").
# Prepara la máquina: instala Docker y Docker Compose y crea las carpetas de la app.
# El despliegue de la app en sí lo hace aws/deploy.sh, que se puede repetir cuantas veces haga falta.
set -euo pipefail   # parar al primer error, y no usar variables sin definir

dnf update -y
dnf install -y docker
systemctl enable --now docker            # arranca Docker ahora y cada vez que se encienda la máquina

# Docker Compose como plugin ("docker compose ..."). Versión fija, para que no cambie sin querer, y con su huella
# SHA-256 (la de la página de la versión): si el archivo bajado no es exactamente ese, no se instala ni se ejecuta.
COMPOSE_VERSION=v5.5.1
COMPOSE_SHA256=732e3a84c1a0f67256ce80bc2598a24546b10ca05f9faa97efceb1171ece2ef7
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-aarch64" \
     -o /tmp/docker-compose
echo "${COMPOSE_SHA256}  /tmp/docker-compose" | sha256sum -c -
install -m 755 /tmp/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
rm -f /tmp/docker-compose

# Carpetas de la app. data/ la usa el contenedor (usuario sin privilegios, UID 10001: ver Dockerfile).
mkdir -p /opt/ragpeat/data
chown 10001:10001 /opt/ragpeat/data
chmod 750 /opt/ragpeat/data

echo "user-data terminado" > /opt/ragpeat/READY
