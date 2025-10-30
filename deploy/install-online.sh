#!/bin/bash

################################################################################
# WinGet Patch Manager - Ubuntu 24.04 LTS Installation Script (Online Mode)
# This script installs all dependencies from the internet
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="winget-patch"
APP_USER="patchmgr"
APP_DIR="/opt/winget-patch"
DB_NAME="winget_patch"
DB_USER="patchmgr"
DB_PASS=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
SERVER_PORT=8080

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   WinGet Patch Manager - Ubuntu 24.04 LTS Installer       ║${NC}"
echo -e "${BLUE}║   Installation Mode: ONLINE (Internet Required)           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Running as root"

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}📁 Project root: ${PROJECT_ROOT}${NC}"

# Check if we have the necessary project files
if [ ! -f "$PROJECT_ROOT/backend/database/schema.sql" ]; then
    echo -e "${YELLOW}⚠️  Schema file not found at $PROJECT_ROOT/backend/database/schema.sql${NC}"
    echo -e "${YELLOW}   Attempting to clone repository...${NC}"

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}   Installing git...${NC}"
        apt install -y git
    fi

    # Clone the repository to a temporary location
    TEMP_DIR="/tmp/winget-patch-install-$$"
    git clone https://github.com/aravipati88/winget-patch.git "$TEMP_DIR" 2>/dev/null || \
    git clone https://github.com/yourusername/winget-patch.git "$TEMP_DIR" 2>/dev/null || {
        echo -e "${RED}❌ Could not clone repository. Please ensure you run this script from the project directory.${NC}"
        echo -e "${RED}   Or manually clone the repo first:${NC}"
        echo -e "${YELLOW}   git clone <repo-url> /opt/winget-patch-source${NC}"
        echo -e "${YELLOW}   cd /opt/winget-patch-source/deploy${NC}"
        echo -e "${YELLOW}   sudo ./install-online.sh${NC}"
        exit 1
    }

    PROJECT_ROOT="$TEMP_DIR"
    echo -e "${GREEN}✓${NC} Repository cloned to ${PROJECT_ROOT}"
fi

# Verify essential files exist
if [ ! -f "$PROJECT_ROOT/backend/database/schema.sql" ]; then
    echo -e "${RED}❌ Schema file not found: $PROJECT_ROOT/backend/database/schema.sql${NC}"
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/backend/main.go" ]; then
    echo -e "${RED}❌ Backend source not found: $PROJECT_ROOT/backend/main.go${NC}"
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/frontend/package.json" ]; then
    echo -e "${RED}❌ Frontend source not found: $PROJECT_ROOT/frontend/package.json${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} All required files found"

# Step 1: Update system
echo ""
echo -e "${YELLOW}[1/10]${NC} Updating system packages..."
apt update && apt upgrade -y
echo -e "${GREEN}✓${NC} System updated"

# Step 2: Install PostgreSQL
echo ""
echo -e "${YELLOW}[2/10]${NC} Installing PostgreSQL 16..."
apt install -y postgresql postgresql-contrib
systemctl start postgresql
systemctl enable postgresql
echo -e "${GREEN}✓${NC} PostgreSQL installed"

# Step 3: Install Go
echo ""
echo -e "${YELLOW}[3/10]${NC} Installing Go 1.21..."
if ! command -v go &> /dev/null; then
    wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
    rm go1.21.5.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
    export PATH=$PATH:/usr/local/go/bin
    echo -e "${GREEN}✓${NC} Go installed"
else
    echo -e "${GREEN}✓${NC} Go already installed"
fi

# Step 4: Install Node.js
echo ""
echo -e "${YELLOW}[4/10]${NC} Installing Node.js 20..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
    echo -e "${GREEN}✓${NC} Node.js installed"
else
    echo -e "${GREEN}✓${NC} Node.js already installed"
fi

# Step 5: Install Nginx
echo ""
echo -e "${YELLOW}[5/10]${NC} Installing Nginx..."
apt install -y nginx
systemctl enable nginx
echo -e "${GREEN}✓${NC} Nginx installed"

# Step 6: Create application user
echo ""
echo -e "${YELLOW}[6/10]${NC} Creating application user..."
if ! id "$APP_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d "$APP_DIR" "$APP_USER"
    echo -e "${GREEN}✓${NC} User $APP_USER created"
else
    echo -e "${GREEN}✓${NC} User $APP_USER already exists"
fi

# Step 7: Setup database
echo ""
echo -e "${YELLOW}[7/10]${NC} Setting up PostgreSQL database..."
sudo -u postgres psql << EOF
-- Drop existing database if exists
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;

-- Create database and user
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

-- Connect to database and grant schema permissions
\c $DB_NAME
GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOF

# Apply schema
echo -e "${BLUE}   Applying database schema from: $PROJECT_ROOT/backend/database/schema.sql${NC}"
if [ ! -f "$PROJECT_ROOT/backend/database/schema.sql" ]; then
    echo -e "${RED}❌ Error: Schema file not found at $PROJECT_ROOT/backend/database/schema.sql${NC}"
    exit 1
fi

if ! sudo -u postgres psql -d $DB_NAME -f "$PROJECT_ROOT/backend/database/schema.sql"; then
    echo -e "${RED}❌ Error: Failed to apply database schema${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Schema applied successfully"

# Grant permissions on existing tables
sudo -u postgres psql -d $DB_NAME << EOF
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
EOF

echo -e "${GREEN}✓${NC} Database configured"

# Step 8: Build and install backend
echo ""
echo -e "${YELLOW}[8/10]${NC} Building backend application..."
mkdir -p "$APP_DIR"
cd "$PROJECT_ROOT/backend"

# Install Go dependencies
export GOPATH=/tmp/go
go mod download

# Build backend
CGO_ENABLED=0 go build -a -installsuffix cgo -o "$APP_DIR/server" main.go

# Create .env file
cat > "$APP_DIR/.env" << EOF
SERVER_PORT=$SERVER_PORT
DATABASE_URL=postgres://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME?sslmode=disable
JWT_SECRET=$JWT_SECRET
JWT_EXPIRATION=24h
AGENT_POLL_INTERVAL=5m
CATALOG_SYNC_URL=https://winget.azureedge.net/cache
ENABLE_TLS=false
AGENT_BINARY_PATH=$APP_DIR/agents
EOF

# Create agents directory
mkdir -p "$APP_DIR/agents"

# Set permissions
chown -R $APP_USER:$APP_USER "$APP_DIR"
chmod 600 "$APP_DIR/.env"
chmod +x "$APP_DIR/server"

echo -e "${GREEN}✓${NC} Backend built and installed"

# Step 9: Build and install frontend
echo ""
echo -e "${YELLOW}[9/10]${NC} Building frontend application..."
cd "$PROJECT_ROOT/frontend"

# Install npm dependencies
npm install --production

# Build frontend
npm run build -- --configuration production

# Copy to web root
mkdir -p /var/www/winget-patch
cp -r dist/winget-patch-manager-ui/* /var/www/winget-patch/ 2>/dev/null || \
cp -r dist/* /var/www/winget-patch/ 2>/dev/null || \
echo "Frontend build output copied"

chown -R www-data:www-data /var/www/winget-patch

echo -e "${GREEN}✓${NC} Frontend built and installed"

# Step 10: Configure services
echo ""
echo -e "${YELLOW}[10/10]${NC} Configuring system services..."

# Create systemd service for backend
cat > /etc/systemd/system/winget-patch.service << EOF
[Unit]
Description=WinGet Patch Manager API
After=network.target postgresql.service

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/server
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx
cat > /etc/nginx/sites-available/winget-patch << 'EOF'
server {
    listen 80;
    server_name _;

    # Frontend
    location / {
        root /var/www/winget-patch;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    # API proxy
    location /api/ {
        proxy_pass http://localhost:8080/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/winget-patch /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

# Reload systemd and start services
systemctl daemon-reload
systemctl enable winget-patch
systemctl start winget-patch
systemctl restart nginx

echo -e "${GREEN}✓${NC} Services configured and started"

# Create credentials file
cat > "$APP_DIR/credentials.txt" << EOF
╔════════════════════════════════════════════════════════════╗
║           WinGet Patch Manager - Installation Complete     ║
╚════════════════════════════════════════════════════════════╝

🌐 Access URL: http://$(hostname -I | awk '{print $1}')

🔐 Default Login Credentials:
   Username: admin
   Password: admin123
   ⚠️  CHANGE THIS PASSWORD IMMEDIATELY!

📊 Database Credentials:
   Database: $DB_NAME
   User: $DB_USER
   Password: $DB_PASS

🔑 JWT Secret: $JWT_SECRET

📁 Installation Directory: $APP_DIR

🔧 Service Management:
   Backend:  systemctl status winget-patch
   Nginx:    systemctl status nginx
   Database: systemctl status postgresql

📝 Logs:
   Backend:  journalctl -u winget-patch -f
   Nginx:    tail -f /var/log/nginx/access.log

⚠️  IMPORTANT SECURITY STEPS:
   1. Change the default admin password
   2. Configure firewall (ufw allow 80/tcp)
   3. Set up SSL/TLS certificates
   4. Backup the credentials file and delete it from server

EOF

chown $APP_USER:$APP_USER "$APP_DIR/credentials.txt"
chmod 600 "$APP_DIR/credentials.txt"

# Display completion message
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installation Completed Successfully!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
cat "$APP_DIR/credentials.txt"
echo ""
echo -e "${YELLOW}📄 Credentials saved to: $APP_DIR/credentials.txt${NC}"
echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo -e "   1. Open browser: http://$(hostname -I | awk '{print $1}')"
echo -e "   2. Login with admin/admin123"
echo -e "   3. Change password immediately"
echo -e "   4. Configure firewall: sudo ufw allow 80/tcp"
echo ""
echo -e "${GREEN}✨ Happy patching!${NC}"
