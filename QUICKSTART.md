# 🚀 LexiLingo - Quick Start Guide

Get LexiLingo up and running in under 5 minutes!

## Prerequisites

Make sure you have installed:
- ✅ **Python 3.11+**
- ✅ **Flutter 3.24.0+**
- ✅ **PostgreSQL 14+**

## 1️⃣ Clone & Setup (2 minutes)

```bash
# Clone repository
git clone https://github.com/InfinityZero3000/LexiLingo.git
cd LexiLingo

# Run automated setup
./scripts/setup-all.sh
```

This command will:
- Create Python virtual environments
- Install all dependencies (Python & Flutter)
- Setup PostgreSQL database
- Create configuration files

## 2️⃣ Configure (1 minute)

Edit the `.env` files with your credentials:

**Backend** (`backend-service/.env`):
```env
DATABASE_URL=postgresql+asyncpg://your_user:your_pass@localhost:5432/lexilingo
SECRET_KEY=change-this-to-random-string
```

**AI Service** (`ai-service/.env`):
```env
GEMINI_API_KEY=your_gemini_api_key_here
```

**Flutter App** (`flutter-app/.env`):
```env
API_BASE_URL=http://localhost:8000/api/v1
```

> 💡 **Tip**: Get your Gemini API key from [Google AI Studio](https://ai.google.dev/)

## 3️⃣ Start All Services (30 seconds)

```bash
./scripts/start-all.sh
```

This will start:
- 🔧 **Backend API** → http://localhost:8000
- 🤖 **AI Service** → http://localhost:8001
- 📱 **Flutter Web** → http://localhost:8080

## 4️⃣ Verify Setup

Open your browser:
- **Flutter App**: http://localhost:8080
- **API Docs**: http://localhost:8000/docs

Check service status:
```bash
./scripts/status.sh
```

## ✅ You're Ready!

Start developing! All services are running and ready to use.

---

## Common Commands

```bash
# Check service status
./scripts/status.sh

# View logs
./scripts/dev.sh logs

# Stop all services
./scripts/stop-all.sh
# or press Ctrl+C in the terminal running start-all.sh

# Restart all services
./scripts/dev.sh restart
```

---

## Need Help?

### Service URLs
- **Frontend**: http://localhost:8080
- **Backend API**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs
- **AI Service**: http://localhost:8001

### Troubleshooting

**Port already in use?**
```bash
./scripts/stop-all.sh
./scripts/start-all.sh
```

**Database connection error?**
```bash
# Check PostgreSQL is running
pg_isready

# Check database exists
psql -l | grep lexilingo

# Reset database
./scripts/dev.sh db-reset
```

**Service not starting?**
```bash
# Check logs
./scripts/dev.sh log-backend
./scripts/dev.sh log-ai
./scripts/dev.sh log-flutter
```

### Documentation
- 📚 [Full README](README.md)
- 🔧 [Scripts Documentation](scripts/README.md)
- 🏗️ [Architecture](architecture.md)
- 💻 [Backend Service](backend-service/README.md)
- 🤖 [AI Service](ai-service/README.md)
- 📱 [Flutter App](flutter-app/README.md)

---

## What's Next?

1. **Create an account** on http://localhost:8080
2. **Explore the API** at http://localhost:8000/docs
3. **Read the documentation** in each service folder
4. **Start developing** your features!

---

**Happy Coding! 🎉**
