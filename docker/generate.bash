#!/bin/bash
set -e # Sai imediatamente se um comando falhar
# set -x # Descomente para imprimir cada comando antes de executá-lo (ótimo para depuração)

# --- Funções para verificação de portas ---
# Função para verificar se uma porta está em uso
is_port_in_use() {
  local port=$1
  netstat -tuln | grep -q ":$port " && return 0 || return 1
}

# Função para gerar uma porta livre dentro de um intervalo
get_free_port() {
  local min=$1
  local max=$2
  local port
  local max_attempts=50
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    port=$(shuf -i ${min}-${max} -n 1)
    if ! is_port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  
  echo "ERRO: Não foi possível encontrar uma porta livre após $max_attempts tentativas." >&2
  exit 1
}

# --- Processamento de Argumentos ---
if [ -z "$1" ]; then
  echo "ERRO: Forneça um nome único para a instância Supabase como primeiro argumento."
  echo "Uso: $0 <nome_da_instancia> [nome_do_host_base]"
  echo "Exemplo com host padrão: $0 minhaInstancia"
  echo "Exemplo com host específico: $0 minhaInstancia api.meudominio.com"
  exit 1
fi
INSTANCE_ID=$1
export INSTANCE_ID # Exportar para envsubst e para o ambiente dos subcomandos

# Diretório do script atual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_JWT_SCRIPT="${SCRIPT_DIR}/generate_jwt.py"

# Verifica se o script Python existe
if [ ! -f "${PYTHON_JWT_SCRIPT}" ]; then
  echo "ERRO: O script generate_jwt.py não foi encontrado em ${SCRIPT_DIR}"
  echo "Certifique-se de que generate_jwt.py está no mesmo diretório que generate.bash."
  exit 1
fi

# Processa o segundo argumento para o nome do host base
# Se não for fornecido, usa um valor padrão.
DEFAULT_HOST_BASE="supabase.seudominio.com" # AJUSTE ESTE VALOR PADRÃO SE NECESSÁRIO
HOST_BASE=${2:-$DEFAULT_HOST_BASE}

if [ -z "$HOST_BASE" ]; then
    echo "ERRO: O nome do host base não foi fornecido e não há padrão configurado."
    echo "Uso: $0 <nome_da_instancia> <nome_do_host_base>"
    exit 1
fi

echo "===================================================================="
echo "Iniciando geração da instância Supabase: ${INSTANCE_ID}"
echo "Host Base para URLs: ${HOST_BASE}"
echo "===================================================================="

# --- Geração de Segredos Únicos por Instância ---
echo "Gerando POSTGRES_PASSWORD..."
export POSTGRES_PASSWORD=$(openssl rand -hex 16)
echo "POSTGRES_PASSWORD gerado."

echo "Gerando JWT_SECRET..."
export JWT_SECRET=$(openssl rand -base64 32)
echo "JWT_SECRET gerado: ${JWT_SECRET}"

echo "Gerando ANON_KEY usando script Python..."
export ANON_KEY=$(python3 "${PYTHON_JWT_SCRIPT}" "${JWT_SECRET}" "anon" "supabase")
if [ -z "${ANON_KEY}" ]; then
    echo "ERRO: Falha ao gerar ANON_KEY com o script Python."
    exit 1
fi
echo "ANON_KEY gerado."

echo "Gerando SERVICE_ROLE_KEY usando script Python..."
export SERVICE_ROLE_KEY=$(python3 "${PYTHON_JWT_SCRIPT}" "${JWT_SECRET}" "service_role" "supabase")
if [ -z "${SERVICE_ROLE_KEY}" ]; then
    echo "ERRO: Falha ao gerar SERVICE_ROLE_KEY com o script Python."
    exit 1
fi
echo "SERVICE_ROLE_KEY gerado."

echo "JWT_SECRET, ANON_KEY, e SERVICE_ROLE_KEY gerados."
# --- Fim da Geração de Segredos ---

# --- Variáveis de Configuração Adicionais ---
export DASHBOARD_USERNAME=${INSTANCE_ID}admin
export DASHBOARD_PASSWORD=$(openssl rand -hex 12)
export POSTGRES_DB=postgres

export SUPABASE_ANON_KEY=${ANON_KEY}
export SUPABASE_SERVICE_KEY=${SERVICE_ROLE_KEY}

# --- Geração de Portas Aleatórias com Verificação de Disponibilidade ---
echo "Gerando portas de serviço aleatórias para ${INSTANCE_ID}..."
export POSTGRES_PORT=5432
export POSTGRES_PORT_EXT=$(get_free_port 5400 5499)
export POOLER_PORT=$(get_free_port 5500 5599)  # Porta dinâmica para o pooler

export KONG_HTTP_PORT=$(get_free_port 8000 8099)
export KONG_HTTPS_PORT=$(get_free_port 8400 8499)

export STUDIO_PORT=$(get_free_port 3000 3099)
export AUTH_PORT=$(get_free_port 9000 9099)
export REST_PORT=$(get_free_port 3100 3199)
export REALTIME_PORT=$(get_free_port 4000 4099)
export STORAGE_PORT=$(get_free_port 5000 5099)
export IMGPROXY_PORT=$(get_free_port 5100 5199)
export META_PORT=$(get_free_port 8100 8199)
export ANALYTICS_PORT=$(get_free_port 4100 4199)

# Variáveis adicionais para o pooler
export SECRET_KEY_BASE=$(openssl rand -base64 32)
export VAULT_ENC_KEY="your-encryption-key-32-chars-min"
export POOLER_TENANT_ID="default"
export POOLER_DEFAULT_POOL_SIZE=20
export POOLER_MAX_CLIENT_CONN=300

echo "Portas geradas (exemplo):"
echo "  PostgreSQL (externa): ${POSTGRES_PORT_EXT}"
echo "  Pooler (externa): ${POOLER_PORT}"
echo "  Kong HTTPS: ${KONG_HTTPS_PORT}"
echo "  Studio: ${STUDIO_PORT}"

# --- Definição de URLs e Configurações da Aplicação ---
export API_EXTERNAL_URL="https://${HOST_BASE}:${KONG_HTTPS_PORT}"
export SUPABASE_PUBLIC_URL="https://${HOST_BASE}:${KONG_HTTPS_PORT}"
export SITE_URL="https://${HOST_BASE}:${STUDIO_PORT}"

export STUDIO_DEFAULT_ORGANIZATION="${INSTANCE_ID} Org"
export STUDIO_DEFAULT_PROJECT="DefaultProject"

export ENABLE_EMAIL_SIGNUP="true"
export ENABLE_EMAIL_AUTOCONFIRM="true"
export SMTP_ADMIN_EMAIL="noreply@${HOST_BASE}"
export SMTP_HOST="your_smtp_host" # AJUSTE ESTAS CONFIGURAÇÕES DE SMTP
export SMTP_PORT=587
export SMTP_USER="your_smtp_user"
export SMTP_PASS="your_smtp_pass"
export SMTP_SENDER_NAME="${INSTANCE_ID} Supabase (${HOST_BASE})"

export ENABLE_ANONYMOUS_USERS="true"
export JWT_EXPIRY=3600
export DISABLE_SIGNUP="false"
export IMGPROXY_ENABLE_WEBP_DETECTION="true"
export FUNCTIONS_VERIFY_JWT="true"
export DOCKER_SOCKET_LOCATION="/var/run/docker.sock"
export LOGFLARE_API_KEY=""
export LOGFLARE_LOGGER_BACKEND_API_KEY=""
export PGRST_DB_SCHEMAS="public,storage,graphql_public"

# --- Geração de Arquivos de Configuração da Instância ---
ENV_FILE=".env-${INSTANCE_ID}"
DOCKER_COMPOSE_FILE="docker-compose-${INSTANCE_ID}.yml"

echo "Gerando arquivo de ambiente ${ENV_FILE} a partir de .env.template..."
if [ ! -f ".env.template" ]; then
    echo "ERRO: Arquivo .env.template não encontrado! Crie-o antes de continuar."
    exit 1
fi
envsubst < .env.template > "${ENV_FILE}"
echo "${ENV_FILE} gerado."

echo "Gerando arquivo Docker Compose ${DOCKER_COMPOSE_FILE} a partir de docker-compose.yml..."
if [ ! -f "docker-compose.yml" ]; then
    echo "ERRO: Arquivo docker-compose.yml (template) não encontrado! Crie-o antes de continuar."
    exit 1
fi
envsubst < docker-compose.yml > "${DOCKER_COMPOSE_FILE}"
echo "${DOCKER_COMPOSE_FILE} gerado."

# --- Criação de Diretórios de Volumes Específicos da Instância ---
VOLUMES_DIR_INSTANCE="volumes-${INSTANCE_ID}"
echo "Criando diretórios de volumes em ${VOLUMES_DIR_INSTANCE}..."
mkdir -p "${VOLUMES_DIR_INSTANCE}/functions"
mkdir -p "${VOLUMES_DIR_INSTANCE}/logs"
mkdir -p "${VOLUMES_DIR_INSTANCE}/db/init"
mkdir -p "${VOLUMES_DIR_INSTANCE}/api"
mkdir -p "${VOLUMES_DIR_INSTANCE}/pooler"  # Diretório para o pooler
echo "Diretórios de volumes criados."

# --- Cópia e Preparação de Arquivos de Volume ---
if [ -d "volumes/db/" ]; then
  echo "Copiando conteúdo de volumes/db/ para ${VOLUMES_DIR_INSTANCE}/db/..."
  cp -a volumes/db/. "${VOLUMES_DIR_INSTANCE}/db/"
fi

if [ -d "volumes/functions/" ]; then
  echo "Copiando conteúdo de volumes/functions/ para ${VOLUMES_DIR_INSTANCE}/functions/..."
  cp -a volumes/functions/. "${VOLUMES_DIR_INSTANCE}/functions/"
fi

if [ -f "volumes/logs/vector.yml" ]; then
  echo "Processando volumes/logs/vector.yml para ${VOLUMES_DIR_INSTANCE}/logs/vector.yml..."
  envsubst < volumes/logs/vector.yml > "${VOLUMES_DIR_INSTANCE}/logs/vector.yml"
fi

if [ -f "volumes/api/kong.yml" ]; then
  echo "Processando volumes/api/kong.yml para ${VOLUMES_DIR_INSTANCE}/api/kong.yml..."
  envsubst < volumes/api/kong.yml > "${VOLUMES_DIR_INSTANCE}/api/kong.yml"
else
  # Criar um arquivo kong.yml básico se não existir
  cat > "${VOLUMES_DIR_INSTANCE}/api/kong.yml" << 'EOF'
_format_version: "2.1"
_transform: true

services:
  - name: auth-v1
    url: http://auth:9999/verify
    routes:
      - name: auth-v1
        paths:
          - /auth/v1
    plugins:
      - name: cors
  - name: rest-v1
    url: http://rest:3000
    routes:
      - name: rest-v1-all
        paths:
          - /rest/v1
    plugins:
      - name: cors
  - name: realtime-v1
    url: http://realtime:4000/socket
    routes:
      - name: realtime-v1-all
        paths:
          - /realtime/v1
    plugins:
      - name: cors
  - name: storage-v1
    url: http://storage:5000
    routes:
      - name: storage-v1-all
        paths:
          - /storage/v1
    plugins:
      - name: cors
  - name: analytics-v1
    url: http://analytics:4000
    routes:
      - name: analytics-v1-all
        paths:
          - /analytics/v1
    plugins:
      - name: cors
  - name: functions-v1
    url: http://functions:9000
    routes:
      - name: functions-v1-all
        paths:
          - /functions/v1
    plugins:
      - name: cors
  - name: meta
    url: http://meta:8080
    routes:
      - name: meta-all
        paths:
          - /pg
    plugins:
      - name: cors
  - name: studio
    url: http://studio:3000
    routes:
      - name: studio-all
        paths:
          - /
    plugins:
      - name: cors

plugins:
  - name: cors
    config:
      origins:
        - "*"
      methods:
        - GET
        - POST
        - PUT
        - PATCH
        - DELETE
        - OPTIONS
      headers:
        - Accept
        - Accept-Version
        - Content-Length
        - Content-MD5
        - Content-Type
        - Date
        - apikey
        - Authorization
        - X-CSRF-Token
        - X-Client-Info
      exposed_headers:
        - Content-Length
        - Content-Range
      credentials: true
      max_age: 3600
EOF
  echo "Arquivo kong.yml básico criado em ${VOLUMES_DIR_INSTANCE}/api/kong.yml"
fi

# Criar arquivo de configuração do pooler
cat > "${VOLUMES_DIR_INSTANCE}/pooler/pooler.exs" << 'EOF'
alias Supavisor.Repo
alias Supavisor.Tenants.{Tenant, Pool, Database}

tenant = %Tenant{
  id: System.get_env("POOLER_TENANT_ID", "default"),
  region: System.get_env("REGION", "local"),
  inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
  updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
}

database = %Database{
  id: "postgres",
  tenant_id: tenant.id,
  region: tenant.region,
  host: "db",
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  database: System.get_env("POSTGRES_DB", "postgres"),
  username: "postgres",
  password: System.get_env("POSTGRES_PASSWORD"),
  inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
  updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
}

pool = %Pool{
  id: "postgres",
  tenant_id: tenant.id,
  region: tenant.region,
  database_id: database.id,
  mode: "transaction",
  size: String.to_integer(System.get_env("POOLER_DEFAULT_POOL_SIZE", "20")),
  max_client_conn: String.to_integer(System.get_env("POOLER_MAX_CLIENT_CONN", "300")),
  default_role_name: "postgres",
  default_role_password: System.get_env("POSTGRES_PASSWORD"),
  inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
  updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
}

Repo.insert!(tenant)
Repo.insert!(database)
Repo.insert!(pool)
EOF
echo "Arquivo de configuração do pooler criado em ${VOLUMES_DIR_INSTANCE}/pooler/pooler.exs"

# --- Iniciando os Contêineres da Instância ---
echo "Iniciando contêineres para a instância ${INSTANCE_ID} usando ${DOCKER_COMPOSE_FILE} e ${ENV_FILE}..."
docker compose -f "${DOCKER_COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d

echo "===================================================================="
echo "Instância Supabase '${INSTANCE_ID}' configurada e (tentativa de) iniciada!"
echo "  Host Base Utilizado: ${HOST_BASE}"
echo "  URL da API Pública: ${SUPABASE_PUBLIC_URL}"
echo "  URL do Studio: ${SITE_URL}"
echo "  Chave Anon (ANON_KEY): ${ANON_KEY}"
echo "  Chave Service Role (SERVICE_ROLE_KEY): (Verifique ${ENV_FILE} ou o output do script Python)"
echo "  Senha do Postgres: ${POSTGRES_PASSWORD}"
echo "  Usuário do Dashboard Studio: ${DASHBOARD_USERNAME}"
echo "  Senha do Dashboard Studio: ${DASHBOARD_PASSWORD}"
echo "  Arquivo de Ambiente: ${ENV_FILE}"
echo "  Arquivo Docker Compose: ${DOCKER_COMPOSE_FILE}"
echo "  Portas expostas no host (exemplos):"
echo "    PostgreSQL: ${POSTGRES_PORT_EXT} -> ${POSTGRES_PORT}"
echo "    Pooler: ${POOLER_PORT} -> 5432"
echo "    Kong HTTPS: ${KONG_HTTPS_PORT} -> (porta interna do kong, ex: 8443)"
echo "    Studio: ${STUDIO_PORT} -> (porta interna do studio, ex: 3000)"
echo "Caso utilize Firewall libere o acesso às Portas Kong ${KONG_HTTPS_PORT} -> (porta interna do kong, ex: 8443)"
echo "Para ver os logs: docker compose -f ${DOCKER_COMPOSE_FILE} --env-file ${ENV_FILE} logs -f"
echo "Para parar: docker compose -f ${DOCKER_COMPOSE_FILE} --env-file ${ENV_FILE} down"
echo "===================================================================="
