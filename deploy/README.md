# Ubuntu 24.04 LTS Deployment Package

This directory contains automated installation scripts for deploying WinGet Patch Manager on Ubuntu 24.04 LTS.

## 📦 Two Deployment Scenarios

### Scenario 1: Online Installation (Internet Available)
Use when the target server has internet connectivity.

### Scenario 2: Offline Installation (No Internet)
Use when the target server is air-gapped or has no internet access.

---

## 🌐 Scenario 1: Online Installation

### Requirements
- Ubuntu 24.04 LTS (fresh installation recommended)
- Root/sudo access
- Active internet connection
- Minimum 2GB RAM, 20GB disk space

### Installation Steps

**⚠️ IMPORTANT**: You MUST have the full project directory before running the installer. The script needs access to backend source code, frontend code, and database schema files.

1. **Copy the project to the server**
```bash
# Method 1: Clone from git (RECOMMENDED)
git clone https://github.com/aravipati88/winget-patch.git
cd winget-patch

# Method 2: Copy the entire project directory
scp -r windsurf-project user@server:/tmp/
cd /tmp/windsurf-project

# Method 3: Let the installer auto-clone (if you run it standalone)
# The installer will attempt to clone the repo automatically if needed
```

2. **Run the online installer from within the project directory**
```bash
cd winget-patch/deploy  # or windsurf-project/deploy
sudo bash install-online.sh
```

**❌ DO NOT** download just the install script and run it alone. It requires the full project structure.

3. **Wait for installation to complete** (10-15 minutes)
   - System packages will be downloaded and installed
   - Go, Node.js, PostgreSQL, and Nginx will be installed
   - Application will be built and configured
   - Services will be started automatically

4. **Access the application**
```bash
# The installer will display the access URL
# Open in browser: http://<server-ip>
# Login: admin / admin123
```

### What Gets Installed
- ✅ PostgreSQL 16
- ✅ Nginx web server
- ✅ Go 1.21.5
- ✅ Node.js 20
- ✅ Backend API service
- ✅ Frontend web application
- ✅ Systemd service configuration

---

## 🔒 Scenario 2: Offline Installation

### Phase 1: Prepare Offline Package (On Internet-Connected Machine)

1. **Run the preparation script**
```bash
cd windsurf-project/deploy
sudo bash prepare-offline.sh
```

2. **Wait for package creation** (20-30 minutes)
   - Downloads Go, Node.js, and system packages
   - Builds backend and agent binaries
   - Builds frontend production bundle
   - Creates compressed package

3. **Locate the package**
```bash
# Package will be created as:
# winget-patch-offline-YYYYMMDD.tar.gz
# Size: ~500MB-1GB
ls -lh winget-patch-offline-*.tar.gz
```

### Phase 2: Deploy on Offline Server

1. **Transfer package to target server**
```bash
# Using USB drive, SCP, or other method
scp winget-patch-offline-*.tar.gz user@offline-server:/tmp/
scp install-offline.sh user@offline-server:/tmp/
```

2. **On the offline server, extract package**
```bash
cd /tmp
tar -xzf winget-patch-offline-*.tar.gz
```

3. **Run the offline installer**
```bash
sudo bash install-offline.sh
```

4. **Access the application**
```bash
# Open in browser: http://<server-ip>
# Login: admin / admin123
```

### What's Included in Offline Package
- ✅ Go 1.21.5 binary
- ✅ Node.js 20 binary
- ✅ PostgreSQL .deb packages
- ✅ Nginx .deb packages
- ✅ Pre-built backend server
- ✅ Pre-built Windows agent
- ✅ Frontend production build
- ✅ All npm dependencies

---

## 📋 Post-Installation Steps (Both Scenarios)

### 1. Change Default Password
```bash
# Login to web interface
# Navigate to user settings
# Change password from 'admin123' to a strong password
```

### 2. Configure Firewall
```bash
# Allow HTTP traffic
sudo ufw allow 80/tcp

# Enable firewall
sudo ufw enable
```

### 3. Optional: Setup SSL/TLS
```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d your-domain.com
```

### 4. Deploy Windows Agent
```bash
# Agent location
/opt/winget-patch/agents/winget-agent.exe

# Copy to Windows machines and configure
set PATCH_SERVER_URL=http://your-server-ip
winget-agent.exe
```

---

## 🔧 Service Management

### Check Service Status
```bash
# Backend API
sudo systemctl status winget-patch

# Web server
sudo systemctl status nginx

# Database
sudo systemctl status postgresql
```

### View Logs
```bash
# Backend logs
sudo journalctl -u winget-patch -f

# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Restart Services
```bash
# Restart backend
sudo systemctl restart winget-patch

# Restart nginx
sudo systemctl restart nginx

# Restart database
sudo systemctl restart postgresql
```

---

## 📊 Default Configuration

### Application
- **Web Interface**: http://server-ip
- **API Endpoint**: http://server-ip/api
- **Backend Port**: 8080 (internal)
- **Web Port**: 80 (external)

### Credentials
- **Username**: admin
- **Password**: admin123 (⚠️ CHANGE IMMEDIATELY)

### File Locations
- **Application**: /opt/winget-patch
- **Frontend**: /var/www/winget-patch
- **Config**: /opt/winget-patch/.env
- **Credentials**: /opt/winget-patch/credentials.txt
- **Logs**: journalctl -u winget-patch

### Database
- **Name**: winget_patch
- **User**: patchmgr
- **Password**: Auto-generated (see credentials.txt)

---

## 🐛 Troubleshooting

### Installation Fails
```bash
# Check system requirements
df -h  # Disk space
free -h  # Memory

# Check logs
tail -f /var/log/syslog
```

### Service Won't Start
```bash
# Check backend service
sudo journalctl -u winget-patch -n 50

# Check configuration
cat /opt/winget-patch/.env

# Test database connection
sudo -u postgres psql -d winget_patch -c "SELECT 1;"
```

### Can't Access Web Interface
```bash
# Check nginx status
sudo systemctl status nginx

# Check if port 80 is listening
sudo netstat -tlnp | grep :80

# Check firewall
sudo ufw status
```

### Database Connection Issues
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Check database exists
sudo -u postgres psql -l | grep winget_patch

# Test connection
sudo -u postgres psql -d winget_patch
```

---

## 🔄 Updating the Application

### Online Mode
```bash
# Pull latest code
cd windsurf-project
git pull

# Rebuild backend
cd backend
go build -o /opt/winget-patch/server main.go

# Rebuild frontend
cd ../frontend
npm install
npm run build
sudo cp -r dist/* /var/www/winget-patch/

# Restart services
sudo systemctl restart winget-patch
sudo systemctl restart nginx
```

### Offline Mode
```bash
# Prepare new offline package on internet-connected machine
sudo bash prepare-offline.sh

# Transfer and extract on target server
# Stop services
sudo systemctl stop winget-patch

# Replace binaries
sudo cp offline-packages/binaries/server /opt/winget-patch/
sudo cp -r offline-packages/frontend-dist/* /var/www/winget-patch/

# Start services
sudo systemctl start winget-patch
```

---

## 📞 Support

### Logs Location
- Backend: `journalctl -u winget-patch`
- Nginx: `/var/log/nginx/`
- PostgreSQL: `/var/log/postgresql/`

### Configuration Files
- Backend: `/opt/winget-patch/.env`
- Nginx: `/etc/nginx/sites-available/winget-patch`
- Systemd: `/etc/systemd/system/winget-patch.service`

### Credentials
- Stored in: `/opt/winget-patch/credentials.txt`
- **Delete this file after noting credentials!**

---

## 🔐 Security Checklist

- [ ] Changed default admin password
- [ ] Configured firewall (ufw)
- [ ] Set up SSL/TLS certificates
- [ ] Deleted credentials.txt file
- [ ] Configured PostgreSQL to only accept local connections
- [ ] Set up regular database backups
- [ ] Reviewed and secured .env file permissions
- [ ] Configured log rotation

---

## 📈 Performance Tuning

### For Large Deployments (1000+ devices)

1. **Increase PostgreSQL resources**
```bash
sudo nano /etc/postgresql/16/main/postgresql.conf
# Adjust: shared_buffers, effective_cache_size, work_mem
sudo systemctl restart postgresql
```

2. **Optimize backend**
```bash
# Increase file descriptors
sudo nano /etc/security/limits.conf
# Add: patchmgr soft nofile 65536
```

3. **Add caching**
```bash
# Consider adding Redis for session storage
# Configure nginx caching for static assets
```

---

## 🔧 Troubleshooting

### Error: "Schema file not found at /home/backend/database/schema.sql"

**Problem**: The installer cannot find the database schema file.

**Cause**: You're running the installer script without the full project directory structure.

**Solution**:

1. **Clone the entire repository first**:
```bash
git clone https://github.com/aravipati88/winget-patch.git
cd winget-patch/deploy
sudo bash install-online.sh
```

2. **Or copy the full project directory**:
```bash
# On your local machine
scp -r windsurf-project user@server:/opt/
# On the server
cd /opt/windsurf-project/deploy
sudo bash install-online.sh
```

3. **Auto-recovery (new feature)**: The updated installer will automatically attempt to clone the repository if files are missing.

### Error: "Failed to apply database schema"

**Problem**: PostgreSQL cannot execute the schema file.

**Solutions**:
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check if database was created
sudo -u postgres psql -c "\l" | grep winget_patch

# Manually apply schema
sudo -u postgres psql -d winget_patch -f /path/to/backend/database/schema.sql
```

### Error: "Build failed" or "Go not found"

**Problem**: Dependencies not installed correctly.

**Solutions**:
```bash
# Verify Go installation
go version  # Should show 1.21+

# If not found, ensure PATH is set
export PATH=$PATH:/usr/local/go/bin
go version

# Re-run the installer
cd windsurf-project/deploy
sudo bash install-online.sh
```

### Service Won't Start

**Check logs**:
```bash
# Backend logs
sudo journalctl -u winget-patch -n 50 --no-pager

# Nginx logs
sudo tail -f /var/log/nginx/error.log

# Check if port 8080 is in use
sudo lsof -i :8080
```

**Common fixes**:
```bash
# Restart services
sudo systemctl restart winget-patch
sudo systemctl restart nginx
sudo systemctl restart postgresql

# Check file permissions
sudo ls -la /opt/winget-patch/
sudo chown -R patchmgr:patchmgr /opt/winget-patch/
```

---

## 📄 License

See main project LICENSE file.

---

## 🎉 Quick Reference

| Task | Command |
|------|---------|
| Install (Online) | `sudo bash install-online.sh` |
| Prepare Offline | `sudo bash prepare-offline.sh` |
| Install (Offline) | `sudo bash install-offline.sh` |
| Check Status | `sudo systemctl status winget-patch` |
| View Logs | `sudo journalctl -u winget-patch -f` |
| Restart Service | `sudo systemctl restart winget-patch` |
| Access Web | `http://<server-ip>` |
| Default Login | `admin / admin123` |

---

**For detailed documentation, see the main project README.md**
