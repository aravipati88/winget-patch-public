#!/bin/bash

################################################################################
# WinGet Patch Manager - Ubuntu 24.04 LTS Installation Script (Offline Mode)
# This script installs from pre-downloaded packages (no internet required)
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
echo -e "${BLUE}║   Installation Mode: OFFLINE (No Internet Required)       ║${NC}"
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
OFFLINE_DIR="$SCRIPT_DIR/offline-packages"

echo -e "${BLUE}📁 Project root: ${PROJECT_ROOT}${NC}"
echo -e "${BLUE}📦 Offline packages: ${OFFLINE_DIR}${NC}"

# Check if offline packages exist
if [ ! -d "$OFFLINE_DIR" ]; then
    echo -e "${RED}❌ Offline packages directory not found!${NC}"
    echo -e "${YELLOW}Please run prepare-offline.sh first to download all packages${NC}"
    exit 1
fi

# Step 1: Install system packages from offline debs
echo ""
echo -e "${YELLOW}[1/10]${NC} Installing system packages from offline repository..."

# Install PostgreSQL from debs
echo "Installing PostgreSQL..."
dpkg -i "$OFFLINE_DIR/debs/postgresql"*.deb 2>/dev/null || apt install -f -y

# Install Nginx from debs
echo "Installing Nginx..."
dpkg -i "$OFFLINE_DIR/debs/nginx"*.deb 2>/dev/null || apt install -f -y

systemctl start postgresql
systemctl enable postgresql
systemctl enable nginx

echo -e "${GREEN}✓${NC} System packages installed"

# Step 2: Install Go from offline tarball
echo ""
echo -e "${YELLOW}[2/10]${NC} Installing Go from offline package..."
if [ -f "$OFFLINE_DIR/go1.21.5.linux-amd64.tar.gz" ]; then
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$OFFLINE_DIR/go1.21.5.linux-amd64.tar.gz"
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
    export PATH=$PATH:/usr/local/go/bin
    echo -e "${GREEN}✓${NC} Go installed"
else
    echo -e "${RED}❌ Go package not found in offline directory${NC}"
    exit 1
fi

# Step 3: Install Node.js from offline tarball
echo ""
echo -e "${YELLOW}[3/10]${NC} Installing Node.js from offline package..."
if [ -f "$OFFLINE_DIR/node-v20.10.0-linux-x64.tar.xz" ]; then
    tar -C /usr/local -xJf "$OFFLINE_DIR/node-v20.10.0-linux-x64.tar.xz"
    ln -sf /usr/local/node-v20.10.0-linux-x64/bin/node /usr/local/bin/node
    ln -sf /usr/local/node-v20.10.0-linux-x64/bin/npm /usr/local/bin/npm
    echo -e "${GREEN}✓${NC} Node.js installed"
else
    echo -e "${RED}❌ Node.js package not found in offline directory${NC}"
    exit 1
fi

# Step 4: Create application user
echo ""
echo -e "${YELLOW}[4/10]${NC} Creating application user..."
if ! id "$APP_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d "$APP_DIR" "$APP_USER"
    echo -e "${GREEN}✓${NC} User $APP_USER created"
else
    echo -e "${GREEN}✓${NC} User $APP_USER already exists"
fi

# Step 5: Setup database
echo ""
echo -e "${YELLOW}[5/10]${NC} Setting up PostgreSQL database..."
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
sudo -u postgres psql -d $DB_NAME -f "$PROJECT_ROOT/backend/database/schema.sql"

# Grant permissions on existing tables
sudo -u postgres psql -d $DB_NAME << EOF
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
EOF

echo -e "${GREEN}✓${NC} Database configured"

# Step 6: Install pre-built backend
echo ""
echo -e "${YELLOW}[6/10]${NC} Installing backend application..."
mkdir -p "$APP_DIR"

if [ -f "$OFFLINE_DIR/binaries/server" ]; then
    cp "$OFFLINE_DIR/binaries/server" "$APP_DIR/server"
    chmod +x "$APP_DIR/server"
else
    echo -e "${YELLOW}⚠️  Pre-built binary not found, building from source...${NC}"
    cd "$PROJECT_ROOT/backend"
    export GOPATH=/tmp/go
    CGO_ENABLED=0 go build -a -installsuffix cgo -o "$APP_DIR/server" main.go
fi

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

echo -e "${GREEN}✓${NC} Backend installed"

# Step 7: Install pre-built frontend
echo ""
echo -e "${YELLOW}[7/10]${NC} Installing frontend application..."
mkdir -p /var/www/winget-patch

if [ -d "$OFFLINE_DIR/frontend-dist" ]; then
    cp -r "$OFFLINE_DIR/frontend-dist"/* /var/www/winget-patch/
else
    echo -e "${YELLOW}⚠️  Pre-built frontend not found, building from source...${NC}"
    cd "$PROJECT_ROOT/frontend"
    
    # Use offline node_modules if available
    if [ -d "$OFFLINE_DIR/node_modules" ]; then
        cp -r "$OFFLINE_DIR/node_modules" .
    fi
    
    npm run build -- --configuration production 2>/dev/null || npm run build
    cp -r dist/winget-patch-manager-ui/* /var/www/winget-patch/ 2>/dev/null || \
    cp -r dist/* /var/www/winget-patch/
fi

chown -R www-data:www-data /var/www/winget-patch

echo -e "${GREEN}✓${NC} Frontend installed"

# Step 8: Install Windows agent binary
echo ""
echo -e "${YELLOW}[8/10]${NC} Installing Windows agent..."
if [ -f "$OFFLINE_DIR/binaries/winget-agent.exe" ]; then
    cp "$OFFLINE_DIR/binaries/winget-agent.exe" "$APP_DIR/agents/"
    chown $APP_USER:$APP_USER "$APP_DIR/agents/winget-agent.exe"
    echo -e "${GREEN}✓${NC} Windows agent installed"
else
    echo -e "${YELLOW}⚠️  Windows agent not found, will need to be built separately${NC}"
fi

# Step 9: Configure services
echo ""
echo -e "${YELLOW}[9/10]${NC} Configuring system services..."

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

# Step 10: Create documentation
echo ""
echo -e "${YELLOW}[10/10]${NC} Creating documentation..."

# Create credentials file
cat > "$APP_DIR/credentials.txt" << EOF
╔════════════════════════════════════════════════════════════╗
║           WinGet Patch Manager - Installation Complete     ║
║                    (OFFLINE MODE)                          ║
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

📦 Windows Agent:
   Location: $APP_DIR/agents/winget-agent.exe
   Copy this file to Windows machines for deployment

⚠️  IMPORTANT SECURITY STEPS:
   1. Change the default admin password
   2. Configure firewall (ufw allow 80/tcp)
   3. Set up SSL/TLS certificates
   4. Backup the credentials file and delete it from server

⚠️  OFFLINE MODE LIMITATIONS:
   - WinGet catalog sync requires internet access
   - Agent updates require manual distribution
   - Consider setting up a local package mirror

EOF

chown $APP_USER:$APP_USER "$APP_DIR/credentials.txt"
chmod 600 "$APP_DIR/credentials.txt"

# Display completion message
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation Completed Successfully! (OFFLINE)     ║${NC}"
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
echo -e "   5. Deploy agent: $APP_DIR/agents/winget-agent.exe"
echo ""
echo -e "${GREEN}✨ Happy patching!${NC}"
