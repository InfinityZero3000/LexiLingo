# LexiLingo - Quick Reference Card

## 🚀 Essential Commands

```bash
# Setup (first time only)
./scripts/setup-all.sh

# Start all services
./scripts/start-all.sh

# Check status
./scripts/status.sh

# Stop all services
./scripts/stop-all.sh
```

## 📍 Service URLs

| Service | URL | Description |
|---------|-----|-------------|
| Frontend | http://localhost:8080 | Flutter Web App |
| Backend | http://localhost:8000 | REST API |
| API Docs | http://localhost:8000/docs | Swagger UI |
| AI Service | http://localhost:8001 | AI/ML API |

## 🔧 Development Helper

```bash
./scripts/dev.sh [command]

# Quick commands:
./scripts/dev.sh start      # Start all
./scripts/dev.sh stop       # Stop all
./scripts/dev.sh restart    # Restart all
./scripts/dev.sh status     # Check status
./scripts/dev.sh logs       # View all logs
./scripts/dev.sh clean      # Clean logs/PIDs
./scripts/dev.sh db-reset   # Reset database
./scripts/dev.sh test-all   # Run all tests
```

## 📝 Log Files

```bash
# View logs
tail -f logs/backend.log
tail -f logs/ai-service.log
tail -f logs/flutter-web.log

# Or use helper
./scripts/dev.sh log-backend
./scripts/dev.sh log-ai
./scripts/dev.sh log-flutter
```

## 🗄️ Database

```bash
# Access database
psql lexilingo

# Run migrations
./scripts/dev.sh db-migrate

# Reset database
./scripts/dev.sh db-reset
```

## 🏗️ Project Structure

```
LexiLingo/
├── backend-service/     # FastAPI backend (Port 8000)
├── ai-service/          # AI/ML service (Port 8001)
├── flutter-app/         # Flutter app (Port 8080)
├── scripts/             # Management scripts
│   ├── setup-all.sh    # Setup everything
│   ├── start-all.sh    # Start all services
│   ├── stop-all.sh     # Stop all services
│   ├── status.sh       # Check status
│   └── dev.sh          # Development helper
├── logs/                # Service logs
└── .pids/              # Process IDs
```

## ⚡ Quick Troubleshooting

### Port already in use
```bash
./scripts/stop-all.sh
./scripts/start-all.sh
```

### Database connection error
```bash
pg_isready              # Check PostgreSQL
./scripts/dev.sh db-reset   # Reset database
```

### Service not starting
```bash
./scripts/dev.sh logs   # Check all logs
./scripts/status.sh     # Check what's running
```

### Clean restart
```bash
./scripts/stop-all.sh
./scripts/dev.sh clean
./scripts/start-all.sh
```

## 📚 Documentation

- [Quick Start](QUICKSTART.md) - 5-minute setup
- [Scripts Guide](scripts/README.md) - Scripts documentation
- [Backend](backend-service/README.md) - Backend service docs
- [AI Service](ai-service/README.md) - AI service docs
- [Flutter](flutter-app/README.md) - Flutter app docs

## 🔑 Configuration Files

```bash
backend-service/.env    # Backend config
ai-service/.env         # AI service config
flutter-app/.env        # Flutter config
```

## 🎯 Common Workflows

### Daily Development
```bash
./scripts/start-all.sh     # Morning
# ... do your work ...
./scripts/stop-all.sh      # End of day
```

### Testing Changes
```bash
./scripts/dev.sh restart   # Restart all
./scripts/dev.sh test-all  # Run tests
./scripts/dev.sh lint      # Check code quality
```

### Debugging
```bash
./scripts/status.sh        # What's running?
./scripts/dev.sh logs      # View all logs
```

---

**Need more help?** Check [QUICKSTART.md](QUICKSTART.md) or [README.md](README.md)
