#!/bin/bash
# Script để chạy LexiLingo Web với port cố định cho Google OAuth

echo "🚀 Starting LexiLingo on http://localhost:8080"
echo "📱 Google Sign-In will work on this port"
echo ""

flutter run -d chrome --web-port 8080
