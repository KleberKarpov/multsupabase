!/bin/bash
set -e # Sai imediatamente se um comando falhar
# set -x # Descomente para imprimir cada comando antes de executá-lo (ótimo para depuração)

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

# --- Geração de Portas Aleatórias ---
echo "Gerando portas de serviço aleatórias para ${INSTANCE_ID}..."
export POSTGRES_PORT=5432
export POSTGRES_PORT_EXT=54$(shuf -i 10-99 -n 1)

export KONG_HTTP_PORT=80$(shuf -i 10-99 -n 1)
export KONG_HTTPS_PORT=84$(shuf -i 10-99 -n 1)

export STUDIO_PORT=30$(shuf -i 10-99 -n 1)
export AUTH_PORT=99$(shuf -i 10-99 -n 1)
export REST_PORT=31$(shuf -i 10-99 -n 1)
export REALTIME_PORT=40$(shuf -i 10-99 -n 1)
export STORAGE_PORT=50$(shuf -i 10-99 -n 1)
export IMGPROXY_PORT=51$(shuf -i 10-99 -n 1)
export META_PORT=81$(shuf -i 10-99 -n 1)
export ANALYTICS_PORT=41$(shuf -i 10-99 -n 1)

echo "Portas geradas (exemplo):"
echo "  PostgreSQL (externa): ${POSTGRES_PORT_EXT}"
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
echo "Diretórios de volumes criados."

# --- Criação de Diretórios de Volumes Específicos da Instância ---
VOLUMES_DIR_INSTANCE="volumes-${INSTANCE_ID}"
echo "Criando diretórios de volumes em ${VOLUMES_DIR_INSTANCE}..."
mkdir -p "${VOLUMES_DIR_INSTANCE}/functions"
mkdir -p "${VOLUMES_DIR_INSTANCE}/logs"
mkdir -p "${VOLUMES_DIR_INSTANCE}/db/init"
mkdir -p "${VOLUMES_DIR_INSTANCE}/api"
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
  echo "AVISO: Arquivo volumes/api/kong.yml (template) não encontrado. O Kong pode não funcionar corretamente se este arquivo for essencial para sua configuração."
fi

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
echo "    Kong HTTPS: ${KONG_HTTPS_PORT} -> (porta interna do kong, ex: 8443)"
echo "    Studio: ${STUDIO_PORT} -> (porta interna do studio, ex: 3000)"
echo "Caso utilize Firewall libere o acesso às Portas Kong ${KONG_HTTPS_PORT} -> (porta interna do kong, ex: 8443)"
echo "Para ver os logs: docker compose -f ${DOCKER_COMPOSE_FILE} --env-file ${ENV_FILE} logs -f"
echo "Para parar: docker compose -f ${DOCKER_COMPOSE_FILE} --env-file ${ENV_FILE} down"
echo "===================================================================="

