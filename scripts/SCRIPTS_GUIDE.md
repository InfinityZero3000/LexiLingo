# LexiLingo Scripts - Enhanced Management System

Unified management scripts for running LexiLingo services in both **Local** and **Docker** modes.

---

## 🚀 Quick Start

### Local Mode (Development)
```bash
bash scripts/start-all.sh  # Start
bash scripts/status.sh     # Check status  
bash scripts/stop-all.sh   # Stop
```

### Docker Mode (Production)
```bash
bash scripts/start-docker.sh  # Start
bash scripts/status.sh        # Check status
bash scripts/stop-docker.sh   # Stop
```

---

## 📋 Scripts Overview

| Script | Mode | Purpose | Key Features |
|--------|------|---------|--------------|
| `start-all.sh` | Local | Start services locally | Port checking, health monitoring, PID tracking |
| `start-docker.sh` | Docker | Start with Docker | Container health, sequential startup, auto-build |
| `stop-all.sh` | Local | Stop local services | Clean PID files, force kill if needed |
| `stop-docker.sh` | Docker | Stop containers | Confirmation prompt, ordered shutdown |
| `status.sh` | Both | Check system status | Auto-detect mode, health checks, URLs |
| `setup-all.sh` | Both | Initial setup | Install dependencies, create .env |

---

## 🟢 start-all.sh - Local Services

**Enhanced Features**:
- ✅ Automatic port conflict detection & resolution  
- ✅ Virtual environment validation
- ✅ GEMINI_API_KEY validation
- ✅ Real-time health checks (Backend, AI, Flutter)
- ✅ Automatic log rotation
- ✅ Graceful shutdown with Ctrl+C
- ✅ PID file management

**Services**:
1. Backend Service → `http://localhost:8000`
2. AI Service → `http://localhost:8001`
3. Flutter Web → `http://localhost:8080`

**Requirements**:
```bash
# Backend venv
backend-service/venv/

# AI venv  
.venv/

# Environment
GEMINI_API_KEY in .env
```

**Logs**:
```bash
logs/backend.log
logs/ai-service.log
```

---

## 🐳 start-docker.sh - Docker Services

**Enhanced Features**:
- ✅ Docker availability validation
- ✅ Environment file validation
- ✅ Port conflict detection
- ✅ Sequential startup (DBs → Apps)
- ✅ Container health monitoring
- ✅ Automatic image building
- ✅ Detailed error reporting with logs
- ✅ Real-time log streaming

**Services**:
1. PostgreSQL → `localhost:5432`
2. MongoDB → `localhost:27017`
3. Redis → `localhost:6379`
4. Backend → `http://localhost:8000`
5. AI Service → `http://localhost:8001`

**Startup Sequence**:
```
Step 1: Start Databases
├── PostgreSQL (wait for healthy)
├── MongoDB (wait for healthy)
└── Redis (wait for healthy)

Step 2: Start Applications
├── Backend Service (wait for /health)
└── AI Service (wait for /health)

Step 3: Stream logs
```

---

## 🔍 status.sh - Unified Status Checker

**Auto-Detection**:
- Detects if running in Docker or Local mode
- Adapts output based on mode

**Checks**:
- ✅ Service ports (8000, 8001, 8080)
- ✅ Database ports (5432, 27017, 6379)
- ✅ Health endpoints
- ✅ Container status (Docker mode)
- ✅ PID files (Local mode)

**Output Example**:
```
╔════════════════════════════════════════╗
║    LexiLingo - System Status Check     ║
╚════════════════════════════════════════╝

🐳 Running Mode: Docker

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Service Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Backend Service (port 8000) - PID: 12345
✅ AI Service (port 8001) - PID: 12346
✅ Flutter Web (port 8080) - PID: 12347

...
```

---

## 🛑 stop-all.sh - Stop Local Services

**Features**:
- Kill processes on ports 8000, 8001, 8080
- Clean PID files in `.pids/`
- Force termination if graceful fails
- Verify all stopped

**Usage**:
```bash
bash scripts/stop-all.sh
# Output: Killed processes, cleaned PID files
```

---

## 🛑 stop-docker.sh - Stop Docker Services

**Features**:
- Confirmation prompt
- Ordered shutdown (apps → databases)
- Container removal
- Status verification

**Options**:
```bash
# Normal stop (preserve volumes)
bash scripts/stop-docker.sh

# Remove volumes (delete data)
docker-compose down -v

# Remove everything
docker-compose down -v --remove-orphans
```

---

## 🎯 Common Workflows

### First Time Setup
```bash
# 1. Clone repo
git clone <url>
cd LexiLingo

# 2. Setup
bash scripts/setup-all.sh

# 3. Configure
nano .env  # Set GEMINI_API_KEY

# 4. Start (choose mode)
bash scripts/start-all.sh      # Local
bash scripts/start-docker.sh   # Docker
```

### Daily Development (Local)
```bash
# Morning
bash scripts/start-all.sh
bash scripts/status.sh

# Development...

# Evening  
bash scripts/stop-all.sh
```

### Testing in Docker
```bash
bash scripts/start-docker.sh

# In another terminal
bash scripts/status.sh
docker-compose logs -f backend-service

# When done
bash scripts/stop-docker.sh
```

### Switch Modes
```bash
# Local → Docker
bash scripts/stop-all.sh
bash scripts/start-docker.sh

# Docker → Local
bash scripts/stop-docker.sh
bash scripts/start-all.sh
```

---

## 🔧 Troubleshooting

### Port Conflicts
```bash
# Check what's using port
lsof -i :8000

# Kill it
kill -9 <PID>

# Or use stop script
bash scripts/stop-all.sh
```

### Service Won't Start
```bash
# Check logs (Local)
tail -f logs/backend.log

# Check logs (Docker)
docker-compose logs -f backend-service
docker logs lexilingo-backend-service --tail 50
```

### Environment Issues
```bash
# Verify .env
cat .env | grep GEMINI_API_KEY

# Check venv
ls -la backend-service/venv
ls -la .venv

# Re-setup
bash scripts/setup-all.sh
```

### Docker Issues
```bash
# Verify Docker running
docker info

# Clean up
docker-compose down -v
docker system prune -a

# Restart Docker Desktop (macOS)
# Cmd+Q → Restart
```

---

## 📊 Port Reference

| Service | Port | Mode | URL |
|---------|------|------|-----|
| Backend API | 8000 | Both | http://localhost:8000 |
| Backend Docs | 8000 | Both | http://localhost:8000/docs |
| AI Service | 8001 | Both | http://localhost:8001 |
| AI Docs | 8001 | Both | http://localhost:8001/docs |
| Flutter Web | 8080 | Both | http://localhost:8080 |
| PostgreSQL | 5432 | Docker | `postgres://lexilingo:pass@localhost:5432/lexilingo` |
| MongoDB | 27017 | Docker | `mongodb://localhost:27017/lexilingo` |
| Redis | 6379 | Docker | `redis://localhost:6379/0` |

---

## 📝 Environment Variables

`.env` file:
```bash
SECRET_KEY=your-secret-key-change-in-production
DEBUG=True
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
GEMINI_API_KEY=AIzaSy...  # Required!
```

---

## 🆚 Local vs Docker Comparison

| Aspect | Local Mode | Docker Mode |
|--------|------------|-------------|
| **Startup Time** | Faster (~30s) | Slower (~2min first time) |
| **Resource Usage** | Lower | Higher (needs Docker) |
| **Isolation** | Shared host | Containerized |
| **Hot Reload** | ✅ Full support | ✅ Volume-mounted |
| **Database Setup** | Manual | Automatic |
| **Best For** | Development | Production-like testing |
| **Log Access** | `logs/*.log` | `docker-compose logs` |
| **Cleanup** | Kill processes | `docker-compose down` |

---

## 🎨 Script Features Comparison

### start-all.sh (Local)
✅ Port checking  
✅ Venv validation  
✅ PID tracking  
✅ Health checks  
✅ Log files  
✅ Ctrl+C cleanup  

### start-docker.sh (Docker)
✅ Docker validation  
✅ Sequential startup  
✅ Health checks  
✅ Container monitoring  
✅ Auto-build  
✅ Error reporting  
✅ Log streaming  

### status.sh (Unified)
✅ Mode auto-detection  
✅ Port checking  
✅ Health checks  
✅ Service URLs  
✅ Container info  
✅ PID info  
✅ Quick actions  

---

## 💡 Tips

**Performance**:
```bash
# Local is faster for dev
bash scripts/start-all.sh

# Docker for production testing
bash scripts/start-docker.sh
```

**Monitoring**:
```bash
# Watch status continuously
watch -n 2 bash scripts/status.sh

# Follow logs (Local)
tail -f logs/*.log

# Follow logs (Docker)
docker-compose logs -f
```

**Cleanup**:
```bash
# Local cleanup
bash scripts/stop-all.sh
rm -rf logs/*.log .pids/*

# Docker cleanup
docker-compose down -v
docker system prune -a
```

---

## 🤝 Contributing

When adding scripts:
1. Follow naming: `<action>-<scope>.sh`
2. Add color output (GREEN, YELLOW, RED, BLUE, CYAN)
3. Include error handling
4. Update this README
5. Make executable: `chmod +x scripts/new-script.sh`

---

## 📄 License

See [LICENSE](../LICENSE) in project root.
