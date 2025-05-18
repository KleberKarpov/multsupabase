#!/bin/bash
set -e # Sai imediatamente se um comando falhar
# set -x # Descomente para depuração

# --- Processamento de Argumentos ---
if [ -z "$1" ]; then
  echo "ERRO: Forneça o nome da instância Supabase que você deseja remover."
  echo "Uso: $0 <nome_da_instancia>"
  echo "Exemplo: $0 meuprojeto"
  exit 1
fi

INSTANCE_ID=$1
ENV_FILE=".env-${INSTANCE_ID}"
DOCKER_COMPOSE_FILE="docker-compose-${INSTANCE_ID}.yml"
VOLUMES_DIR="volumes-${INSTANCE_ID}"

echo "===================================================================="
echo "AVISO: Este script irá PARAR e REMOVER PERMANENTEMENTE"
echo "a instância Supabase '${INSTANCE_ID}', incluindo:"
echo "  - Contêineres Docker"
echo "  - Volumes de dados associados (DADOS SERÃO PERDIDOS!)"
echo "  - Arquivos de configuração (.env e docker-compose.yml)"
echo "  - Diretórios de volumes no host"
echo "===================================================================="
echo
read -p "Você tem certeza que deseja continuar? (sim/não): " CONFIRMATION

if [[ "${CONFIRMATION,,}" != "sim" ]]; then # ,, converte para minúsculas
  echo "Operação cancelada pelo usuário."
  exit 0
fi

echo "Iniciando limpeza da instância Supabase: ${INSTANCE_ID}..."

# --- Passo 1: Parar e Remover Contêineres e Volumes Docker ---
if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
  echo "Parando e removendo contêineres Docker e volumes para '${INSTANCE_ID}'..."
  # O --env-file é importante se o docker-compose.yml usa variáveis dele para nomes de volumes/redes
  if [ -f "${ENV_FILE}" ]; then
    docker compose -f "${DOCKER_COMPOSE_FILE}" --env-file "${ENV_FILE}" down --volumes --remove-orphans
  else
    # Tenta sem --env-file se o .env não existir (pode dar erro se o compose precisar dele)
    echo "AVISO: Arquivo ${ENV_FILE} não encontrado. Tentando 'down' sem ele."
    docker compose -f "${DOCKER_COMPOSE_FILE}" down --volumes --remove-orphans
  fi
  echo "Contêineres e volumes Docker para '${INSTANCE_ID}' removidos."
else
  echo "AVISO: Arquivo Docker Compose '${DOCKER_COMPOSE_FILE}' não encontrado. Pulando a parada de contêineres."
fi

# --- Passo 2: Remover Arquivos de Configuração Gerados ---
echo "Removendo arquivos de configuração para '${INSTANCE_ID}'..."
if [ -f "${ENV_FILE}" ]; then
  rm -f "${ENV_FILE}"
  echo "Arquivo de ambiente '${ENV_FILE}' removido."
else
  echo "AVISO: Arquivo de ambiente '${ENV_FILE}' não encontrado."
fi

if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
  rm -f "${DOCKER_COMPOSE_FILE}"
  echo "Arquivo Docker Compose '${DOCKER_COMPOSE_FILE}' removido."
else
  echo "AVISO: Arquivo Docker Compose '${DOCKER_COMPOSE_FILE}' não encontrado."
fi

# --- Passo 3: Remover Diretórios de Volumes do Host ---
echo "Removendo diretórios de volumes do host para '${INSTANCE_ID}'..."
if [ -d "${VOLUMES_DIR}" ]; then
  # CUIDADO: rm -rf é perigoso. Verifique se VOLUMES_DIR não está vazio ou inesperado.
  if [[ -n "${VOLUMES_DIR}" && "${VOLUMES_DIR}" == "volumes-${INSTANCE_ID}" ]]; then # Dupla verificação
    echo "Removendo diretório ${VOLUMES_DIR}..."
    sudo rm -rf "${VOLUMES_DIR}" # Pode precisar de sudo dependendo de como foi criado
    echo "Diretório de volumes '${VOLUMES_DIR}' removido."
  else
    echo "ERRO: O nome do diretório de volumes '${VOLUMES_DIR}' parece inválido ou vazio. Remoção abortada por segurança."
    exit 1 # Impede remoção acidental de algo importante
  fi
else
  echo "AVISO: Diretório de volumes '${VOLUMES_DIR}' não encontrado."
fi

echo "===================================================================="
echo "Limpeza da instância Supabase '${INSTANCE_ID}' concluída."
echo "===================================================================="