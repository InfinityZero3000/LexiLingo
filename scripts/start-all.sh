#!/bin/bash
# ===========================================
# LexiLingo - Start All Services (Local)
# Runs Backend, AI, and Flutter without Docker
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'

# Gradient color codes (256-color)
C1='\033[38;5;51m'   # bright cyan
C2='\033[38;5;45m'   # cyan-blue
C3='\033[38;5;39m'   # blue
C4='\033[38;5;33m'   # blue-indigo
C5='\033[38;5;63m'   # indigo
C6='\033[38;5;99m'   # purple
C7='\033[38;5;135m'  # magenta
C8='\033[38;5;171m'  # pink

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PID_DIR="$PROJECT_ROOT/.pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

# Load environment variables from .env if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    echo -e "${GREEN}[OK] Loaded environment from .env${NC}"
fi

# ============ Animated Banner ============
clear 2>/dev/null || true

# Hide cursor during animation
printf '\033[?25l'

# Typewriter function
typewriter() {
    local text="$1"
    local delay="${2:-0.02}"
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
}

# Matrix rain intro effect
matrix_rain() {
    local cols=$(tput cols 2>/dev/null || echo 80)
    local chars='0123456789abcdefMNOPQRSTUVWXYZ@#$%&*!<>{}[]|/\'

    for frame in 1 2 3 4 5; do
        printf "\r"
        for ((c=0; c<cols; c++)); do
            local rand=$((RANDOM % 100))
            if [ $rand -lt 35 ]; then
                local ci=$((RANDOM % ${#chars}))
                local ch="${chars:$ci:1}"
                local shade=$((RANDOM % 4))
                case $shade in
                    0) printf "\033[38;5;22m%s" "$ch" ;;
                    1) printf "\033[38;5;28m%s" "$ch" ;;
                    2) printf "\033[38;5;34m%s" "$ch" ;;
                    3) printf "\033[38;5;46m%s" "$ch" ;;
                esac
            else
                printf " "
            fi
        done
        printf "${NC}"
        sleep 0.06
    done
    # Clear the matrix lines
    printf "\r%${cols}s\r" ""
}

# Get color for a palette/index combo (Bash 3.2 compatible)
get_palette_color() {
    local palette=$1
    local idx=$2
    case "${palette}_${idx}" in
        1_0) printf "\033[38;5;51m" ;;
        1_1) printf "\033[38;5;45m" ;;
        1_2) printf "\033[38;5;39m" ;;
        1_3) printf "\033[38;5;63m" ;;
        1_4) printf "\033[38;5;99m" ;;
        1_5) printf "\033[38;5;135m" ;;
        2_0) printf "\033[38;5;199m" ;;
        2_1) printf "\033[38;5;205m" ;;
        2_2) printf "\033[38;5;211m" ;;
        2_3) printf "\033[38;5;217m" ;;
        2_4) printf "\033[38;5;223m" ;;
        2_5) printf "\033[38;5;229m" ;;
        3_0) printf "\033[38;5;46m" ;;
        3_1) printf "\033[38;5;48m" ;;
        3_2) printf "\033[38;5;50m" ;;
        3_3) printf "\033[38;5;51m" ;;
        3_4) printf "\033[38;5;45m" ;;
        3_5) printf "\033[38;5;39m" ;;
    esac
}

# Draw one frame of the banner with a given palette number
draw_banner_frame() {
    local palette_num=$1
    local line0="   ██╗     ███████╗██╗  ██╗██╗██╗     ██╗███╗   ██╗ ██████╗  ██████╗ "
    local line1="   ██║     ██╔════╝╚██╗██╔╝██║██║     ██║████╗  ██║██╔════╝ ██╔═══██╗"
    local line2="   ██║     █████╗   ╚███╔╝ ██║██║     ██║██╔██╗ ██║██║  ███╗██║   ██║"
    local line3="   ██║     ██╔══╝   ██╔██╗ ██║██║     ██║██║╚██╗██║██║   ██║██║   ██║"
    local line4="   ███████╗███████╗██╔╝ ██╗██║███████╗██║██║ ╚████║╚██████╔╝╚██████╔╝"
    local line5="   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ "

    local idx=0
    for line_text in "$line0" "$line1" "$line2" "$line3" "$line4" "$line5"; do
        local color_idx=$(( idx % 6 ))
        printf "\r  "
        get_palette_color "$palette_num" "$color_idx"
        printf "${BOLD}%s${NC}" "$line_text"
        echo ""
        idx=$((idx + 1))
    done
}

# Animated gradient banner with effects
show_banner() {
    # Matrix rain intro
    matrix_rain

    echo ""

    # ── Sparkle separator with typewriter ──
    printf "  ${C1}"
    typewriter "  ✦ " 0.015
    printf "${C5}─── "
    printf "${C6}✧ "
    printf "${C7}─────────────────────────────────────────────── "
    printf "${C5}✧ "
    printf "${C1}───"
    printf " ✦"
    echo -e "${NC}"
    echo ""

    # Phase 1: Reveal ASCII art line by line (palette 1 = cyan-purple gradient)
    local line0="   ██╗     ███████╗██╗  ██╗██╗██╗     ██╗███╗   ██╗ ██████╗  ██████╗ "
    local line1="   ██║     ██╔════╝╚██╗██╔╝██║██║     ██║████╗  ██║██╔════╝ ██╔═══██╗"
    local line2="   ██║     █████╗   ╚███╔╝ ██║██║     ██║██╔██╗ ██║██║  ███╗██║   ██║"
    local line3="   ██║     ██╔══╝   ██╔██╗ ██║██║     ██║██║╚██╗██║██║   ██║██║   ██║"
    local line4="   ███████╗███████╗██╔╝ ██╗██║███████╗██║██║ ╚████║╚██████╔╝╚██████╔╝"
    local line5="   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ "

    local idx=0
    for line_text in "$line0" "$line1" "$line2" "$line3" "$line4" "$line5"; do
        local color_idx=$(( idx % 6 ))
        printf "  "
        get_palette_color 1 "$color_idx"
        printf "${BOLD}%s${NC}" "$line_text"
        echo ""
        sleep 0.05
        idx=$((idx + 1))
    done

    # Phase 2: Color cycling pulse (3 rapid redraws with different palettes)
    sleep 0.15

    for pnum in 2 3 1; do
        # Move cursor up 6 lines to redraw
        printf "\033[6A"
        draw_banner_frame "$pnum"
        sleep 0.12
    done

    echo ""

    # ── Sparkle separator ──
    printf "  ${C7}"
    typewriter "  ✦ " 0.015
    printf "${C5}─── "
    printf "${C6}✧ "
    printf "${C1}─────────────────────────────────────────────── "
    printf "${C5}✧ "
    printf "${C7}───"
    printf " ✦"
    echo -e "${NC}"
    echo ""

    
    # Final sparkle
    sleep 0.1
    printf "  ${C1}✓${NC} ${BOLD}${GREEN}Ready to launch!${NC}"
    echo ""
    echo ""

    # Show cursor again
    printf '\033[?25h'
}

# show_banner

# Cleanup function
cleanup() {
    printf '\033[?25h'  # Show cursor
    clear 2>/dev/null || true
    echo ""
    echo -e "${YELLOW}[STOP] Shutting down all services...${NC}"
    
    # Kill by PID files
    for pidfile in "$PID_DIR"/*.pid; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
            fi
            rm -f "$pidfile"
        fi
    done
    
    # Kill processes on ports
    lsof -ti :8000 | xargs kill -9 2>/dev/null || true
    lsof -ti :8001 | xargs kill -9 2>/dev/null || true
    lsof -ti :5176 | xargs kill -9 2>/dev/null || true
    lsof -ti :8080 | xargs kill -9 2>/dev/null || true
    
    echo -e "${GREEN}[OK] All services stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Function to check and report port status
check_port() {
    local port=$1
    local service=$2
    local process=$(lsof -ti :$port 2>/dev/null)
    
    if [ -n "$process" ]; then
        local cmd=$(ps -p $process -o comm= 2>/dev/null)
        echo -e "   ${YELLOW}[WARN] Port $port is occupied by PID $process ($cmd)${NC}"
        return 1
    fi
    return 0
}

# Function to kill process on port
kill_port() {
    local port=$1
    local service=$2
    if lsof -ti :$port >/dev/null 2>&1; then
        # echo -e "   ${YELLOW}Killing process on port $port for $service...${NC}"
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
        wait 2>/dev/null || true
        if lsof -ti :$port >/dev/null 2>&1; then
            echo -e "   ${RED}[ERROR] Failed to kill process on port $port${NC}"
            return 1
        fi
        # echo -e "   ${GREEN}[OK] Port $port freed${NC}"
    fi
    return 0
}

# Always cleanup ports before starting
# echo -e "${YELLOW}[CLEANUP] Stopping any existing services on ports...${NC}"
kill_port 8000 "Backend"
kill_port 8001 "AI Service"
kill_port 5176 "Admin Dashboard"
kill_port 8080 "Flutter"
# echo -e "${GREEN}[OK] All ports cleared${NC}"
echo ""

# Clean up old PID files
rm -f "$PID_DIR"/*.pid

# ============ Backend Service ============
# echo -e "${BLUE}[START] Starting Backend Service (port 8000)...${NC}"

BACKEND_VENV="$PROJECT_ROOT/backend-service/venv"

# Clear old logs
> "$LOG_DIR/backend.log"

# Check if venv exists
if [ ! -d "$BACKEND_VENV" ]; then
    echo -e "   ${RED}[ERROR] Virtual environment not found at $BACKEND_VENV${NC}"
    echo -e "   ${YELLOW}Run: cd backend-service && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt${NC}"
    exit 1
fi

# Start backend
(
    cd "$PROJECT_ROOT/backend-service"
    source venv/bin/activate
    echo "$(date): Starting Backend on port 8000" >> "$LOG_DIR/backend.log"
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 >> "$LOG_DIR/backend.log" 2>&1
) &
BACKEND_PID=$!
disown $BACKEND_PID
echo $BACKEND_PID > "$PID_DIR/backend.pid"
# echo -e "${GREEN}[OK] Backend started (PID: $BACKEND_PID)${NC}"

# Wait logic removed for immediate dashboard

# ============ AI Service ============
# echo -e "${BLUE}[START] Starting AI Service (port 8001)...${NC}"

AI_VENV="$PROJECT_ROOT/.venv"

# Check if venv exists
if [ ! -d "$AI_VENV" ]; then
    echo -e "   ${RED}[ERROR] Virtual environment not found at $AI_VENV${NC}"
    echo -e "   ${YELLOW}Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r ai-service/requirements.txt${NC}"
    exit 1
fi

# Check if Gemini API key is set (optional warning)
if [ -z "$GEMINI_API_KEY" ]; then
    echo -e "   ${YELLOW}[WARN] GEMINI_API_KEY not set - AI will use Qwen model only${NC}"
    echo -e "   [INFO] To enable Gemini: export GEMINI_API_KEY='your-key' in .env${NC}"
fi

# Clear old logs
> "$LOG_DIR/ai-service.log"

# Start AI service with main.py (full endpoints for Flutter)
(
    cd "$PROJECT_ROOT/ai-service"
    source "$AI_VENV/bin/activate"
    export PYTHONPATH="$PROJECT_ROOT/ai-service"
    export GEMINI_API_KEY="$GEMINI_API_KEY"
    export CHAT_MODEL="${CHAT_MODEL:-qwen}"
    export OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:1.5b}"
    export USE_GRAPHCAG="${USE_GRAPHCAG:-true}"
    echo "$(date): Starting AI Service on port 8001" >> "$LOG_DIR/ai-service.log"
    echo "$(date): CHAT_MODEL=$CHAT_MODEL, OLLAMA_MODEL=$OLLAMA_MODEL, USE_GRAPHCAG=$USE_GRAPHCAG" >> "$LOG_DIR/ai-service.log"
    python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 >> "$LOG_DIR/ai-service.log" 2>&1
) &
AI_PID=$!
disown $AI_PID
echo $AI_PID > "$PID_DIR/ai-service.pid"
# echo -e "${GREEN}[OK] AI Service started (PID: $AI_PID)${NC}"

# Wait logic removed for immediate dashboard

# ============ Admin Dashboard ============
# echo -e "${BLUE}[START] Starting Admin Dashboard (port 5176)...${NC}"

ADMIN_DIR="$PROJECT_ROOT/admin-service"

# Check if node_modules exists
if [ ! -d "$ADMIN_DIR/node_modules" ]; then
    echo -e "   ${YELLOW}[SETUP] Installing admin dependencies...${NC}"
    (cd "$ADMIN_DIR" && npm install >> "$LOG_DIR/admin.log" 2>&1)
fi

# Clear old logs
> "$LOG_DIR/admin.log"

# Start admin dashboard
(
    cd "$ADMIN_DIR"
    echo "$(date): Starting Admin Dashboard on port 5176" >> "$LOG_DIR/admin.log"
    npx vite --port 5176 >> "$LOG_DIR/admin.log" 2>&1
) &
ADMIN_PID=$!
echo $ADMIN_PID > "$PID_DIR/admin.pid"
# echo -e "${GREEN}[OK] Admin Dashboard started (PID: $ADMIN_PID)${NC}"

# Wait logic removed for immediate dashboard

# ============ Flutter Web ============
# echo -e "${BLUE}[START] Starting Flutter Web (port 8080)...${NC}"

FLUTTER_RUNNING=false

# Check if Flutter is already running
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] Flutter Web already running on port 8080${NC}"
    FLUTTER_RUNNING=true
fi

cd "$PROJECT_ROOT/flutter-app"

# Clean Chrome cache
rm -rf .dart_tool/chrome-device 2>/dev/null || true

HAS_FLUTTER=true
# Check if flutter command exists
if ! command -v flutter &> /dev/null; then
    HAS_FLUTTER=false
    echo -e "   ${YELLOW}[WARN] Flutter CLI not found in PATH${NC}"
fi

# Start Flutter in background if available and not running
if [ "$FLUTTER_RUNNING" = false ] && [ "$HAS_FLUTTER" = true ]; then
    (
        cd "$PROJECT_ROOT/flutter-app"
        flutter run -d chrome --web-port=8080 >> "$LOG_DIR/flutter.log" 2>&1
    ) &
    FLUTTER_PID=$!
    echo $FLUTTER_PID > "$PID_DIR/flutter.pid"
    # echo -e "${GREEN}[OK] Flutter starting in background (PID: $FLUTTER_PID)${NC}"
fi

# ============ Persistent Animated Dashboard ============
START_TIME=$(date +%s)

# Check service status
check_service() {
    lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1
}

# Format uptime
format_uptime() {
    local s=$1
    local h=$((s / 3600)) m=$(( (s % 3600) / 60 )) sec=$((s % 60))
    if [ $h -gt 0 ]; then
        printf "%02d:%02d:%02d" $h $m $sec
    else
        printf "%02d:%02d" $m $sec
    fi
}

# Print separator safely (avoids printf -- error)
print_sep() {
    printf '%s' "$1"
}

animated_dashboard() {
    local frame=0

    # Clear screen ONCE at the start, hide cursor
    printf '\033[?25l'
    printf '\033[2J'

    while true; do
        # Move cursor to top-left — do NOT clear screen
        printf '\033[H'

        local now=$(date +%s)
        local elapsed=$((now - START_TIME))
        local uptime=$(format_uptime $elapsed)

        # Spinner using case (no arrays, Bash 3.2 safe)
        local si=$((frame % 4))
        local sp
        case $si in
            0) sp='/' ;;
            1) sp='-' ;;
            2) sp='|' ;;
            3) sp='-' ;;
        esac

        # Color cycling palette
        local pn=$(( (frame / 4) % 3 + 1 ))

        # === DRAW FRAME (each line overwrites previous in-place) ===

        printf '\033[K\n'

        # Top separator (sparkle style)
        printf "  "
        get_palette_color "$pn" 0
        print_sep "  ✦ "
        get_palette_color "$pn" 2
        print_sep "─── "
        get_palette_color "$pn" 3
        print_sep "✧ "
        get_palette_color "$pn" 4
        print_sep "─────────────────────────────────────────────── "
        get_palette_color "$pn" 3
        print_sep "✧ "
        get_palette_color "$pn" 2
        print_sep "─── "
        get_palette_color "$pn" 0
        print_sep "✦"
        printf "${NC}\033[K\n"

        printf '\033[K\n'

        # ASCII art banner — inline, each line colored by palette
        printf "  "
        get_palette_color "$pn" 0
        printf "${BOLD}   ██╗     ███████╗██╗  ██╗██╗██╗     ██╗███╗   ██╗ ██████╗  ██████╗ ${NC}\033[K\n"

        printf "  "
        get_palette_color "$pn" 1
        printf "${BOLD}   ██║     ██╔════╝╚██╗██╔╝██║██║     ██║████╗  ██║██╔════╝ ██╔═══██╗${NC}\033[K\n"

        printf "  "
        get_palette_color "$pn" 2
        printf "${BOLD}   ██║     █████╗   ╚███╔╝ ██║██║     ██║██╔██╗ ██║██║  ███╗██║   ██║${NC}\033[K\n"

        printf "  "
        get_palette_color "$pn" 3
        printf "${BOLD}   ██║     ██╔══╝   ██╔██╗ ██║██║     ██║██║╚██╗██║██║   ██║██║   ██║${NC}\033[K\n"

        printf "  "
        get_palette_color "$pn" 4
        printf "${BOLD}   ███████╗███████╗██╔╝ ██╗██║███████╗██║██║ ╚████║╚██████╔╝╚██████╔╝${NC}\033[K\n"

        printf "  "
        get_palette_color "$pn" 5
        printf "${BOLD}   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ ${NC}\033[K\n"

        printf '\033[K\n'

        # Bottom separator (sparkle style)
        printf "  "
        get_palette_color "$pn" 5
        print_sep "  ✦ "
        get_palette_color "$pn" 3
        print_sep "─── "
        get_palette_color "$pn" 2
        print_sep "✧ "
        get_palette_color "$pn" 1
        print_sep "─────────────────────────────────────────────── "
        get_palette_color "$pn" 2
        print_sep "✧ "
        get_palette_color "$pn" 3
        print_sep "─── "
        get_palette_color "$pn" 5
        print_sep "✦"
        printf "${NC}\033[K\n"

        printf '\033[K\n'

        # Service status header
        printf "  ${BOLD}${C3}[${sp}] SERVICES${NC}  ${DIM}uptime ${C2}${uptime}${NC}\033[K\n"
        printf '\033[K\n'

        # Services status logic: Check Port -> Check PID File -> Status
        # Backend
        if check_service 8000; then
            printf "  ${GREEN}  [*] Backend${NC}        ${DIM}http://localhost:${NC}${C2}8000${NC}\033[K\n"
        elif [ -f "$PID_DIR/backend.pid" ]; then
            printf "  ${YELLOW}  [~] Backend${NC}        ${DIM}starting...${NC}\033[K\n"
        else
            printf "  ${RED}  [ ] Backend${NC}        ${DIM}offline${NC}\033[K\n"
        fi

        # AI Service
        if check_service 8001; then
            printf "  ${GREEN}  [*] AI Service${NC}     ${DIM}http://localhost:${NC}${C2}8001${NC}\033[K\n"
        elif [ -f "$PID_DIR/ai-service.pid" ]; then
            printf "  ${YELLOW}  [~] AI Service${NC}     ${DIM}starting...${NC}\033[K\n"
        else
            printf "  ${RED}  [ ] AI Service${NC}     ${DIM}offline${NC}\033[K\n"
        fi

        # Admin Service
        if check_service 5176; then
            printf "  ${GREEN}  [*] Admin${NC}          ${DIM}http://localhost:${NC}${C2}5176${NC}\033[K\n"
        elif [ -f "$PID_DIR/admin.pid" ]; then
            printf "  ${YELLOW}  [~] Admin${NC}          ${DIM}starting...${NC}\033[K\n"
        else
            printf "  ${RED}  [ ] Admin${NC}          ${DIM}offline${NC}\033[K\n"
        fi

        # Flutter Web
        if check_service 8080; then
            printf "  ${GREEN}  [*] Flutter Web${NC}    ${DIM}http://localhost:${NC}${C2}8080${NC}\033[K\n"
        elif [ "$HAS_FLUTTER" = false ]; then
            printf "  ${RED}  [!] Flutter Web${NC}    ${DIM}not installed${NC}\033[K\n"
        elif [ -f "$PID_DIR/flutter.pid" ]; then
            printf "  ${YELLOW}  [~] Flutter Web${NC}    ${DIM}starting...${NC}\033[K\n"
        else
            printf "  ${RED}  [ ] Flutter Web${NC}    ${DIM}offline${NC}\033[K\n"
        fi

        printf '\033[K\n'
        printf "  ${DIM}${C5}  API Docs: ${NC}${DIM}http://localhost:8000/docs${NC}\033[K\n"
        printf '\033[K\n'
        printf "  ${DIM}${C3}  Logs:${NC} ${DIM}tail -f logs/{backend,ai-service,admin}.log${NC}\033[K\n"
        printf '\033[K\n'
        printf "  ${DIM}${C5}  Press ${NC}${BOLD}${C1}Ctrl+C${NC}${DIM}${C5} to stop all services${NC}\033[K\n"

        # Clear everything below current cursor
        printf "\033[J"

        frame=$((frame + 1))
        # Responsive loop sleep
        sleep 0.2
    done
}

animated_dashboard
