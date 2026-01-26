#!/bin/bash
# Quick start script for voice testing

echo "🎤 LexiLingo Voice Test - Quick Start"
echo "======================================"
echo ""
echo "Installing dependencies..."

# Install required packages
pip3 install -q sounddevice soundfile numpy pyttsx3 2>/dev/null

echo "✅ Dependencies ready!"
echo ""
echo "Starting test in DEMO MODE (no microphone needed)..."
echo ""

# Run in demo mode automatically
echo "2" | python3 test_voice_interactive.py
