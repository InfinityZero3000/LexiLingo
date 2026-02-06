#!/bin/bash
# Script tối ưu Ollama cho Intel Mac với AMD GPU

echo "🚀 LexiLingo - Ollama Optimization Script"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

echo "📋 Phân tích hệ thống..."
echo ""

# Detect hardware
CPU_CORES=$(sysctl -n hw.physicalcpu)
LOGICAL_CORES=$(sysctl -n hw.logicalcpu)
RAM_GB=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024/1024}')

echo "Hardware hiện tại:"
echo "  CPU: ${CPU_CORES} cores / ${LOGICAL_CORES} threads"
echo "  RAM: ${RAM_GB} GB"
echo ""

# Check current model
echo "📦 Models hiện có:"
ollama list
echo ""

# Menu options
echo "Chọn giải pháp tối ưu:"
echo ""
echo "1. 🎯 STREAMING MODE (Khuyến nghị)"
echo "   → Giữ model hiện tại, enable streaming"
echo "   → Perceived latency giảm 50%"
echo "   → Response xuất hiện ngay lập tức"
echo ""
echo "2. ⚡ FAST MODEL (Phi-3 Mini)"
echo "   → Download model 2.3GB"
echo "   → Inference ~3-5s (nhanh gấp 5x)"
echo "   → Quality vẫn tốt cho teaching"
echo ""
echo "3. 🚄 ULTRA FAST (Gemma2 2B)"
echo "   → Download model 1.6GB"
echo "   → Inference ~2-4s (nhanh gấp 7x)"
echo "   → Đủ cho grammar checking"
echo ""
echo "4. 💎 HYBRID MODE"
echo "   → Smart routing: simple → local, complex → Gemini"
echo "   → Best of both worlds"
echo "   → Tự động chọn model phù hợp"
echo ""
echo "5. ☁️  GEMINI ONLY"
echo "   → Disable Ollama, dùng Gemini 100%"
echo "   → Nhanh nhất (~1-3s)"
echo "   → Thông minh nhất"
echo ""
echo "0. ❌ Exit"
echo ""

read -p "Nhập lựa chọn (0-5): " choice

case $choice in
    1)
        echo ""
        print_warning "Implementing STREAMING MODE..."
        
        # Update .env
        cd "$(dirname "$0")/.."
        
        # Add streaming config to .env
        if ! grep -q "OLLAMA_STREAM" .env; then
            echo "" >> .env
            echo "# Streaming optimization" >> .env
            echo "OLLAMA_STREAM=true" >> .env
            echo "OLLAMA_NUM_CTX=4096  # Reduced from 262K" >> .env
            echo "OLLAMA_NUM_THREAD=${CPU_CORES}" >> .env
            echo "OLLAMA_TIMEOUT=15  # Fast fail → fallback" >> .env
        fi
        
        print_success "Config updated!"
        echo ""
        echo "Restart service:"
        echo "  cd ai-service"
        echo "  python -m uvicorn api.main_lite:app --reload"
        ;;
        
    2)
        echo ""
        print_warning "Downloading Phi-3 Mini (2.3GB)..."
        ollama pull phi-3:mini
        
        if [ $? -eq 0 ]; then
            print_success "Downloaded!"
            
            # Test inference speed
            echo ""
            echo "Testing inference speed..."
            time ollama run phi-3:mini "Say hi" --verbose
            
            echo ""
            echo "Update .env để dùng Phi-3:"
            echo "  OLLAMA_MODEL=phi-3:mini"
        else
            print_error "Download failed"
        fi
        ;;
        
    3)
        echo ""
        print_warning "Downloading Gemma2 2B (1.6GB)..."
        ollama pull gemma2:2b
        
        if [ $? -eq 0 ]; then
            print_success "Downloaded!"
            
            # Test
            echo ""
            echo "Testing speed..."
            time ollama run gemma2:2b "Hi" --verbose
            
            echo ""
            echo "Update .env:"
            echo "  OLLAMA_MODEL=gemma2:2b"
        else
            print_error "Download failed"
        fi
        ;;
        
    4)
        echo ""
        print_warning "Implementing HYBRID MODE..."
        
        # Download fast model for simple queries
        print_warning "Step 1: Download fast model cho simple queries..."
        ollama pull gemma2:2b
        
        # Update config
        cd "$(dirname "$0")/.."
        
        if ! grep -q "HYBRID_MODE" .env; then
            echo "" >> .env
            echo "# Hybrid mode configuration" >> .env
            echo "HYBRID_MODE=true" >> .env
            echo "OLLAMA_MODEL_SIMPLE=gemma2:2b" >> .env
            echo "OLLAMA_MODEL_COMPLEX=gemini" >> .env
            echo "COMPLEXITY_THRESHOLD=50  # words" >> .env
        fi
        
        print_success "Hybrid mode configured!"
        echo ""
        echo "Routing rules:"
        echo "  • Simple queries (<50 words) → Local (gemma2:2b)"
        echo "  • Complex queries → Gemini"
        echo "  • Grammar tasks → Gemini (high quality)"
        ;;
        
    5)
        echo ""
        print_warning "Switching to GEMINI ONLY mode..."
        
        cd "$(dirname "$0")/.."
        
        # Update .env
        sed -i.bak 's/USE_OLLAMA=true/USE_OLLAMA=false/' .env
        sed -i.bak 's/USE_GATEWAY=true/USE_GATEWAY=true/' .env
        
        if ! grep -q "GEMINI_PRIMARY" .env; then
            echo "" >> .env
            echo "# Gemini-only mode" >> .env
            echo "GEMINI_PRIMARY=true" >> .env
        fi
        
        print_success "Switched to Gemini-only!"
        echo ""
        echo "Benefits:"
        echo "  ✓ Response time: 1-3s"
        echo "  ✓ Quality: Excellent"
        echo "  ✓ Free: 1500 requests/day"
        ;;
        
    0)
        echo "Bye!"
        exit 0
        ;;
        
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
print_success "Done! Restart AI service để apply changes."
echo ""
echo "Quick restart:"
echo "  pkill -f 'uvicorn api.main_lite'"
echo "  cd ai-service && python -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001"
