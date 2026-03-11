#!/bin/bash
# =============================================================================
# frappe-dev-setup.sh
# Frappe v15 Dev Environment Setup — Ubuntu 22.04
# Stack: ERPNext v15.79.0 | HRMS v15.56.0 | India Compliance v15.25.6
#        Payments version-15 | Python 3.11.9 | Node 18.20.2 | MariaDB 10.6
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# CONFIGURATION
# =============================================================================
DB_ROOT_PASSWORD="root"
SITE_ADMIN_PASSWORD="admin"
SITE_NAME="frontend"
FRAPPE_BRANCH="version-15"
ERPNEXT_VERSION="v15.79.0"
HRMS_VERSION="v15.56.0"
INDIA_COMPLIANCE_VERSION="v15.25.6"
PYTHON_VERSION="3.11.9"
NODE_VERSION="18.20.2"
BENCH_DIR="$HOME/frappe-bench"
MARIADB_VERSION="10.6"

# =============================================================================
# STEP 1 — System Dependencies
# =============================================================================
log "Updating system..."
sudo apt update && sudo apt upgrade -y

log "Installing system dependencies..."
sudo apt install -y git curl wget build-essential cron \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  wkhtmltopdf redis-server vim

# =============================================================================
# STEP 2 — Purge any existing MariaDB completely
# =============================================================================
log "Purging any existing MariaDB installation..."
sudo systemctl stop mariadb 2>/dev/null || true
sudo apt remove --purge -y mariadb-server mariadb-client mariadb-common \
  mariadb-server-core* mariadb-client-core* 2>/dev/null || true
sudo rm -rf /var/lib/mysql /etc/mysql /var/log/mysql
sudo rm -f /etc/apt/sources.list.d/mariadb.list \
           /etc/apt/sources.list.d/mariadb*.list
sudo apt autoremove -y
sudo apt clean
log "MariaDB purged ✓"

# =============================================================================
# STEP 3 — Install MariaDB 10.6 fresh
# =============================================================================
log "Installing MariaDB $MARIADB_VERSION..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup \
  | sudo bash -s -- --mariadb-server-version="mariadb-$MARIADB_VERSION"
sudo apt update
sudo apt install -y mariadb-server mariadb-client libmysqlclient-dev

log "Configuring MariaDB charset..."
sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf > /dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

log "Starting MariaDB..."
sudo systemctl enable mariadb
sudo systemctl start mariadb
sleep 3
sudo systemctl is-active --quiet mariadb && log "MariaDB running ✓" || error "MariaDB failed to start"

log "Setting MariaDB root password..."
sudo mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" 2>/dev/null || \
  mysql -u root -p${DB_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;" 2>/dev/null || \
  warn "MariaDB root already configured, continuing..."

log "MariaDB configured ✓"

# =============================================================================
# STEP 4 — pyenv + Python
# =============================================================================
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

if [ ! -d "$PYENV_ROOT" ]; then
    log "Installing pyenv..."
    curl https://pyenv.run | bash
    eval "$(pyenv init -)"
    log "Installing Python $PYTHON_VERSION..."
    pyenv install $PYTHON_VERSION
    pyenv global $PYTHON_VERSION
else
    log "pyenv found ✓"
    eval "$(pyenv init -)"
    pyenv global $PYTHON_VERSION 2>/dev/null || true
fi

if ! grep -q "pyenv" ~/.bashrc; then
    cat >> ~/.bashrc <<'BASHEOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)"
BASHEOF
fi

log "Python $(python --version) ✓"

# =============================================================================
# STEP 5 — nvm + Node
# =============================================================================
export NVM_DIR="$HOME/.nvm"

if [ ! -d "$NVM_DIR" ]; then
    log "Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    log "Installing Node $NODE_VERSION..."
    nvm install $NODE_VERSION
    nvm use $NODE_VERSION
    nvm alias default $NODE_VERSION
    npm install -g yarn
else
    log "nvm found ✓"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

export PATH="$NVM_DIR/versions/node/v${NODE_VERSION}/bin:$PATH"

if ! grep -q "NVM_DIR" ~/.bashrc; then
    cat >> ~/.bashrc <<'BASHEOF'

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
BASHEOF
fi

log "Node $(node --version) ✓"
log "Yarn $(yarn --version) ✓"

# =============================================================================
# STEP 6 — bench
# =============================================================================
if ! command -v bench &> /dev/null; then
    log "Installing frappe-bench..."
    pip install frappe-bench
fi

log "Bench $(bench --version) ✓"

# =============================================================================
# STEP 7 — Init bench
# =============================================================================
if [ -d "$BENCH_DIR" ]; then
    warn "frappe-bench already exists at $BENCH_DIR — skipping init"
else
    log "Initializing frappe-bench..."
    bench init $BENCH_DIR \
        --frappe-branch $FRAPPE_BRANCH \
        --python $(pyenv which python)
fi

cd $BENCH_DIR

# =============================================================================
# STEP 8 — Get Apps at pinned versions
# =============================================================================
log "Getting ERPNext $ERPNEXT_VERSION..."
bench get-app erpnext --branch version-15
cd apps/erpnext && git fetch --tags && git checkout $ERPNEXT_VERSION && cd ../..

log "Getting Payments..."
bench get-app payments --branch version-15

log "Getting HRMS $HRMS_VERSION..."
bench get-app hrms --branch version-15
cd apps/hrms && git fetch --tags && git checkout $HRMS_VERSION && cd ../..

log "Getting India Compliance $INDIA_COMPLIANCE_VERSION..."
bench get-app india_compliance \
    https://github.com/resilient-tech/india-compliance \
    --branch version-15
cd apps/india_compliance && git fetch --tags && git checkout $INDIA_COMPLIANCE_VERSION && cd ../..

log "Getting Print Designer..."
bench get-app print_designer https://github.com/frappe/print_designer

# =============================================================================
# STEP 9 — Start Redis
# =============================================================================
log "Starting Redis..."
REDIS_CACHE_PORT=$(grep "^port" config/redis_cache.conf 2>/dev/null | awk '{print $2}' || echo "13000")
REDIS_QUEUE_PORT=$(grep "^port" config/redis_queue.conf 2>/dev/null | awk '{print $2}' || echo "11000")

pkill -f "redis-server config/" 2>/dev/null || true
sleep 1

redis-server config/redis_cache.conf --daemonize yes
redis-server config/redis_queue.conf --daemonize yes
sleep 3

redis-cli -p $REDIS_CACHE_PORT ping | grep -q "PONG" && log "Redis cache ✓ (port $REDIS_CACHE_PORT)" || error "Redis cache failed"
redis-cli -p $REDIS_QUEUE_PORT ping | grep -q "PONG" && log "Redis queue ✓ (port $REDIS_QUEUE_PORT)" || error "Redis queue failed"

# =============================================================================
# STEP 10 — Create Site
# =============================================================================
log "Creating site: $SITE_NAME..."
bench new-site $SITE_NAME \
    --db-root-password $DB_ROOT_PASSWORD \
    --admin-password $SITE_ADMIN_PASSWORD \
    --no-mariadb-socket

# =============================================================================
# STEP 11 — Install Apps
# =============================================================================
log "Installing ERPNext..."
bench --site $SITE_NAME install-app erpnext

log "Installing Payments..."
bench --site $SITE_NAME install-app payments

log "Installing HRMS..."
bench --site $SITE_NAME install-app hrms

log "Installing India Compliance..."
bench --site $SITE_NAME install-app india_compliance

log "Installing Print Designer..."
bench --site $SITE_NAME install-app print_designer

# =============================================================================
# STEP 12 — Dev Mode
# =============================================================================
log "Enabling developer mode..."
bench set-config -g developer_mode 1
bench use $SITE_NAME
bench --site $SITE_NAME set-maintenance-mode off

if ! grep -q "127.0.0.1 $SITE_NAME" /etc/hosts; then
    echo "127.0.0.1 $SITE_NAME" | sudo tee -a /etc/hosts
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Frappe Dev Setup Complete! 🚀            ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  Site:      http://$SITE_NAME:8000"
echo -e "  Username:  Administrator"
echo -e "  Password:  $SITE_ADMIN_PASSWORD"
echo ""
echo -e "  Start dev server:"
echo -e "  ${YELLOW}cd ~/frappe-bench && bench start${NC}"
echo ""
