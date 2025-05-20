  GNU nano 7.2                                                        clean.bash                                                                  
#!/bin/bash
set -e

INSTANCE_ID=$1
ENV_FILE=".env-${INSTANCE_ID}"
DOCKER_COMPOSE_FILE="docker-compose-${INSTANCE_ID}.yml"
VOLUMES_DIR="volumes-${INSTANCE_ID}"

echo "Parando contêineres..."
docker-compose -f "${DOCKER_COMPOSE_FILE}" --env-file "${ENV_FILE}" down --volumes --remove-orphans || true

echo "Removendo arquivos..."
sudo rm -f "${ENV_FILE}" || true
sudo rm -f "${DOCKER_COMPOSE_FILE}" || true

echo "Removendo volumes..."
sudo rm -rf "${VOLUMES_DIR}" || true

echo "Limpeza concluída."
