#!/usr/bin/env python3
"""
LexiLingo GraphCAG System Tester
================================
Công cụ kiểm thử hệ thống GraphCAG với giao diện trực quan.

Features:
- Kiểm tra sức khỏe hệ thống (Ollama, Redis, MongoDB, API)
- Đánh giá phần cứng (CPU, RAM, GPU)
- Test GraphCAG pipeline với input mẫu
- Đo latency và hiệu năng
- Hiển thị kết quả chi tiết

Usage:
    python graphcag_system_test.py
    
Requirements:
    pip install requests psutil
"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
from tkinter.font import Font
import threading
import requests
import time
import json
import os
import subprocess
from datetime import datetime
from typing import Dict, Any, Optional, List, Tuple
from dataclasses import dataclass, field

# Try to import psutil for system monitoring
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False
    print("Warning: psutil not installed. Install with: pip install psutil")


# ============================================================================
# Configuration
# ============================================================================

@dataclass
class TestConfig:
    """Configuration for the test suite."""
    api_base_url: str = "http://localhost:8001"
    ollama_url: str = "http://localhost:11434"
    redis_url: str = "localhost:6379"
    timeout: int = 180  # seconds
    

# ============================================================================
# Test Result Data Classes
# ============================================================================

@dataclass
class TestResult:
    """Result of a single test."""
    name: str
    status: str  # "pass", "fail", "warning", "info"
    message: str
    latency_ms: float = 0
    details: Dict[str, Any] = field(default_factory=dict)
    timestamp: str = ""
    
    def __post_init__(self):
        if not self.timestamp:
            self.timestamp = datetime.now().strftime("%H:%M:%S")
            

@dataclass
class HardwareInfo:
    """Hardware diagnostic information."""
    cpu_percent: float = 0
    cpu_count: int = 0
    ram_total_gb: float = 0
    ram_used_gb: float = 0
    ram_percent: float = 0
    gpu_available: bool = False
    gpu_name: str = ""
    gpu_memory_gb: float = 0
    disk_free_gb: float = 0


# ============================================================================
# Test Functions
# ============================================================================

class SystemTester:
    """Tester for GraphCAG system components."""
    
    def __init__(self, config: TestConfig):
        self.config = config
        
    def check_api_health(self) -> TestResult:
        """Check AI service health endpoint."""
        start = time.time()
        try:
            resp = requests.get(
                f"{self.config.api_base_url}/health",
                timeout=10
            )
            latency = (time.time() - start) * 1000
            
            if resp.status_code == 200:
                data = resp.json()
                status = data.get("status", "unknown")
                
                if status == "healthy":
                    return TestResult(
                        name="API Health",
                        status="pass",
                        message=f"Service healthy",
                        latency_ms=latency,
                        details=data
                    )
                else:
                    return TestResult(
                        name="API Health",
                        status="warning",
                        message=f"Status: {status}",
                        latency_ms=latency,
                        details=data
                    )
            else:
                return TestResult(
                    name="API Health",
                    status="fail",
                    message=f"HTTP {resp.status_code}",
                    latency_ms=latency
                )
        except requests.exceptions.Timeout:
            return TestResult(
                name="API Health",
                status="fail",
                message="Connection timeout"
            )
        except requests.exceptions.ConnectionError:
            return TestResult(
                name="API Health",
                status="fail",
                message="Cannot connect to API server"
            )
        except Exception as e:
            return TestResult(
                name="API Health",
                status="fail",
                message=str(e)
            )
    
    def check_ollama(self) -> TestResult:
        """Check Ollama availability and models."""
        start = time.time()
        try:
            resp = requests.get(
                f"{self.config.ollama_url}/api/tags",
                timeout=10
            )
            latency = (time.time() - start) * 1000
            
            if resp.status_code == 200:
                data = resp.json()
                models = data.get("models", [])
                model_names = [m.get("name", "") for m in models]
                
                # Check for qwen3-lexi
                has_qwen = any("qwen" in n.lower() for n in model_names)
                
                if has_qwen:
                    return TestResult(
                        name="Ollama",
                        status="pass",
                        message=f"{len(models)} models loaded",
                        latency_ms=latency,
                        details={"models": model_names}
                    )
                else:
                    return TestResult(
                        name="Ollama",
                        status="warning",
                        message="No Qwen model found",
                        latency_ms=latency,
                        details={"models": model_names}
                    )
            else:
                return TestResult(
                    name="Ollama",
                    status="fail",
                    message=f"HTTP {resp.status_code}",
                    latency_ms=latency
                )
        except requests.exceptions.ConnectionError:
            return TestResult(
                name="Ollama",
                status="fail",
                message="Ollama not running (localhost:11434)"
            )
        except Exception as e:
            return TestResult(
                name="Ollama",
                status="fail",
                message=str(e)
            )
    
    def check_ollama_inference(self) -> TestResult:
        """Test Ollama inference speed with a simple prompt."""
        start = time.time()
        try:
            resp = requests.post(
                f"{self.config.ollama_url}/api/chat",
                json={
                    "model": "qwen3-lexi",
                    "messages": [{"role": "user", "content": "Reply with just: OK"}],
                    "stream": False,
                    "options": {"num_predict": 10}
                },
                timeout=120
            )
            latency = (time.time() - start) * 1000
            
            if resp.status_code == 200:
                data = resp.json()
                content = data.get("message", {}).get("content", "")
                
                if latency < 5000:
                    status = "pass"
                    msg = f"Response in {latency/1000:.1f}s (Fast)"
                elif latency < 30000:
                    status = "warning"
                    msg = f"Response in {latency/1000:.1f}s (Slow)"
                else:
                    status = "warning"
                    msg = f"Response in {latency/1000:.1f}s (Very slow)"
                
                return TestResult(
                    name="Ollama Inference",
                    status=status,
                    message=msg,
                    latency_ms=latency,
                    details={"response": content[:100]}
                )
            else:
                return TestResult(
                    name="Ollama Inference",
                    status="fail",
                    message=f"HTTP {resp.status_code}",
                    latency_ms=latency
                )
        except requests.exceptions.Timeout:
            return TestResult(
                name="Ollama Inference",
                status="fail",
                message="Timeout (>120s) - Model may be stuck"
            )
        except Exception as e:
            return TestResult(
                name="Ollama Inference",
                status="fail",
                message=str(e)
            )
    
    def check_graphcag_endpoint(self) -> TestResult:
        """Check GraphCAG endpoint availability."""
        start = time.time()
        try:
            resp = requests.get(
                f"{self.config.api_base_url}/api/v1/ai/graph-cag/health",
                timeout=10
            )
            latency = (time.time() - start) * 1000
            
            if resp.status_code == 200:
                data = resp.json()
                return TestResult(
                    name="GraphCAG Endpoint",
                    status="pass",
                    message="Endpoint available",
                    latency_ms=latency,
                    details=data
                )
            elif resp.status_code == 404:
                return TestResult(
                    name="GraphCAG Endpoint",
                    status="warning",
                    message="Health endpoint not found (may still work)",
                    latency_ms=latency
                )
            else:
                return TestResult(
                    name="GraphCAG Endpoint",
                    status="fail",
                    message=f"HTTP {resp.status_code}",
                    latency_ms=latency
                )
        except Exception as e:
            return TestResult(
                name="GraphCAG Endpoint",
                status="fail",
                message=str(e)
            )
    
    def test_graphcag_analyze(self, text: str) -> TestResult:
        """Test GraphCAG analysis with actual input."""
        start = time.time()
        try:
            resp = requests.post(
                f"{self.config.api_base_url}/api/v1/ai/graph-cag/analyze",
                json={
                    "text": text,
                    "session_id": f"test-{int(time.time())}"
                },
                timeout=self.config.timeout
            )
            latency = (time.time() - start) * 1000
            
            if resp.status_code == 200:
                data = resp.json()
                
                # Extract key info
                tutor_response = data.get("tutor_response", "")[:200]
                corrections = data.get("corrections", [])
                models_used = data.get("metadata", {}).get("models_used", [])
                
                if latency < 10000:
                    status = "pass"
                    speed = "Fast"
                elif latency < 60000:
                    status = "pass"
                    speed = "Normal"
                else:
                    status = "warning"
                    speed = "Slow"
                
                return TestResult(
                    name="GraphCAG Analysis",
                    status=status,
                    message=f"{speed} ({latency/1000:.1f}s), {len(corrections)} corrections",
                    latency_ms=latency,
                    details={
                        "tutor_response": tutor_response,
                        "corrections": corrections,
                        "models_used": models_used,
                        "full_response": data
                    }
                )
            else:
                error = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else resp.text
                return TestResult(
                    name="GraphCAG Analysis",
                    status="fail",
                    message=f"HTTP {resp.status_code}",
                    latency_ms=latency,
                    details={"error": error}
                )
        except requests.exceptions.Timeout:
            return TestResult(
                name="GraphCAG Analysis",
                status="fail",
                message=f"Timeout ({self.config.timeout}s)"
            )
        except Exception as e:
            return TestResult(
                name="GraphCAG Analysis",
                status="fail",
                message=str(e)
            )
    
    def get_hardware_info(self) -> HardwareInfo:
        """Get hardware diagnostic information."""
        info = HardwareInfo()
        
        if HAS_PSUTIL:
            # CPU
            info.cpu_percent = psutil.cpu_percent(interval=1)
            info.cpu_count = psutil.cpu_count()
            
            # RAM
            mem = psutil.virtual_memory()
            info.ram_total_gb = mem.total / (1024**3)
            info.ram_used_gb = mem.used / (1024**3)
            info.ram_percent = mem.percent
            
            # Disk
            disk = psutil.disk_usage("/")
            info.disk_free_gb = disk.free / (1024**3)
        
        # Check GPU (NVIDIA)
        try:
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                info.gpu_available = True
                parts = result.stdout.strip().split(",")
                if len(parts) >= 2:
                    info.gpu_name = parts[0].strip()
                    info.gpu_memory_gb = float(parts[1].strip().replace(" MiB", "")) / 1024
        except (FileNotFoundError, subprocess.TimeoutExpired):
            # No NVIDIA GPU or nvidia-smi not available
            pass
        
        # Check Metal (macOS)
        if not info.gpu_available and os.uname().sysname == "Darwin":
            try:
                result = subprocess.run(
                    ["system_profiler", "SPDisplaysDataType"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if "Chipset Model" in result.stdout or "Apple" in result.stdout:
                    info.gpu_available = True
                    if "Apple M" in result.stdout:
                        # Extract Apple Silicon info
                        for line in result.stdout.split("\n"):
                            if "Chipset Model" in line:
                                info.gpu_name = line.split(":")[1].strip()
                                break
                    info.gpu_name = info.gpu_name or "Apple GPU (Metal supported)"
            except (FileNotFoundError, subprocess.TimeoutExpired):
                pass
        
        return info


# ============================================================================
# GUI Application
# ============================================================================

class GraphCAGTesterApp:
    """Main GUI application for GraphCAG testing."""
    
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("LexiLingo GraphCAG System Tester")
        self.root.geometry("1200x800")
        self.root.minsize(900, 600)
        
        # Configuration
        self.config = TestConfig()
        self.tester = SystemTester(self.config)
        
        # Test results
        self.results: List[TestResult] = []
        
        # Setup UI
        self._setup_styles()
        self._create_widgets()
        
    def _setup_styles(self):
        """Setup ttk styles."""
        style = ttk.Style()
        style.theme_use("clam")
        
        # Colors
        self.colors = {
            "pass": "#22c55e",
            "fail": "#ef4444",
            "warning": "#f59e0b",
            "info": "#3b82f6",
            "bg": "#f8fafc",
            "card": "#ffffff",
            "text": "#1e293b",
            "muted": "#64748b"
        }
        
        # Configure styles
        style.configure("TFrame", background=self.colors["bg"])
        style.configure("Card.TFrame", background=self.colors["card"])
        style.configure("TLabel", background=self.colors["bg"], foreground=self.colors["text"])
        style.configure("Header.TLabel", font=("Helvetica", 24, "bold"))
        style.configure("Subheader.TLabel", font=("Helvetica", 14), foreground=self.colors["muted"])
        style.configure("TButton", padding=(20, 10))
        
        # Status indicator styles
        style.configure("Pass.TLabel", foreground=self.colors["pass"], font=("Helvetica", 11, "bold"))
        style.configure("Fail.TLabel", foreground=self.colors["fail"], font=("Helvetica", 11, "bold"))
        style.configure("Warning.TLabel", foreground=self.colors["warning"], font=("Helvetica", 11, "bold"))
        style.configure("Info.TLabel", foreground=self.colors["info"], font=("Helvetica", 11, "bold"))
        
    def _create_widgets(self):
        """Create all widgets."""
        # Main container
        main_frame = ttk.Frame(self.root)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Header
        header_frame = ttk.Frame(main_frame)
        header_frame.pack(fill=tk.X, pady=(0, 20))
        
        ttk.Label(
            header_frame,
            text="🧪 GraphCAG System Tester",
            style="Header.TLabel"
        ).pack(side=tk.LEFT)
        
        ttk.Label(
            header_frame,
            text="Kiểm thử hệ thống GraphCAG với đánh giá phần cứng",
            style="Subheader.TLabel"
        ).pack(side=tk.LEFT, padx=(20, 0))
        
        # Two-column layout
        content_frame = ttk.Frame(main_frame)
        content_frame.pack(fill=tk.BOTH, expand=True)
        
        # Left column - Controls
        left_frame = ttk.Frame(content_frame, width=400)
        left_frame.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 10))
        left_frame.pack_propagate(False)
        
        self._create_control_panel(left_frame)
        
        # Right column - Results
        right_frame = ttk.Frame(content_frame)
        right_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        self._create_results_panel(right_frame)
        
    def _create_control_panel(self, parent):
        """Create control panel with test buttons."""
        # System Health Card
        health_card = self._create_card(parent, "🔍 System Health Check")
        
        ttk.Button(
            health_card,
            text="▶ Run All Health Checks",
            command=self._run_health_checks
        ).pack(fill=tk.X, pady=5)
        
        ttk.Button(
            health_card,
            text="Check API Health",
            command=lambda: self._run_single_test(self.tester.check_api_health)
        ).pack(fill=tk.X, pady=2)
        
        ttk.Button(
            health_card,
            text="Check Ollama",
            command=lambda: self._run_single_test(self.tester.check_ollama)
        ).pack(fill=tk.X, pady=2)
        
        ttk.Button(
            health_card,
            text="Check GraphCAG Endpoint",
            command=lambda: self._run_single_test(self.tester.check_graphcag_endpoint)
        ).pack(fill=tk.X, pady=2)
        
        # Hardware Diagnostics Card
        hw_card = self._create_card(parent, "💻 Hardware Diagnostics")
        
        self.hw_info_text = tk.Text(hw_card, height=8, font=("Courier", 10))
        self.hw_info_text.pack(fill=tk.X, pady=5)
        
        ttk.Button(
            hw_card,
            text="🔄 Refresh Hardware Info",
            command=self._refresh_hardware_info
        ).pack(fill=tk.X, pady=5)
        
        # GraphCAG Test Card
        test_card = self._create_card(parent, "🧠 GraphCAG Pipeline Test")
        
        ttk.Label(test_card, text="Test Input:").pack(anchor=tk.W)
        
        self.test_input = tk.Text(test_card, height=3, font=("Helvetica", 11))
        self.test_input.pack(fill=tk.X, pady=5)
        self.test_input.insert("1.0", "I goes to school yesterday and she don't understands me.")
        
        # Sample inputs
        ttk.Label(test_card, text="Quick Tests:", foreground=self.colors["muted"]).pack(anchor=tk.W)
        
        samples_frame = ttk.Frame(test_card)
        samples_frame.pack(fill=tk.X, pady=5)
        
        sample_inputs = [
            ("Grammar Error", "He don't know nothing"),
            ("Tense Error", "I go to school yesterday"),
            ("Mixed Errors", "She have went to the store"),
        ]
        
        for label, text in sample_inputs:
            btn = ttk.Button(
                samples_frame,
                text=label,
                command=lambda t=text: self._set_test_input(t)
            )
            btn.pack(side=tk.LEFT, padx=2)
        
        ttk.Button(
            test_card,
            text="▶ Run GraphCAG Analysis",
            command=self._run_graphcag_test
        ).pack(fill=tk.X, pady=10)
        
        # Ollama Performance Card
        perf_card = self._create_card(parent, "⚡ Ollama Performance")
        
        ttk.Button(
            perf_card,
            text="Test Ollama Inference Speed",
            command=self._test_ollama_inference
        ).pack(fill=tk.X, pady=5)
        
        self.ollama_status = ttk.Label(perf_card, text="Not tested yet", foreground=self.colors["muted"])
        self.ollama_status.pack(fill=tk.X, pady=5)
        
    def _create_results_panel(self, parent):
        """Create results display panel."""
        # Results header
        header_frame = ttk.Frame(parent)
        header_frame.pack(fill=tk.X, pady=(0, 10))
        
        ttk.Label(header_frame, text="📊 Test Results", font=("Helvetica", 16, "bold")).pack(side=tk.LEFT)
        
        ttk.Button(header_frame, text="Clear", command=self._clear_results).pack(side=tk.RIGHT)
        
        # Results summary
        self.summary_frame = ttk.Frame(parent)
        self.summary_frame.pack(fill=tk.X, pady=(0, 10))
        
        self.summary_labels = {}
        for status in ["pass", "fail", "warning"]:
            frame = ttk.Frame(self.summary_frame)
            frame.pack(side=tk.LEFT, padx=10)
            self.summary_labels[status] = ttk.Label(
                frame,
                text="0",
                font=("Helvetica", 20, "bold"),
                foreground=self.colors[status]
            )
            self.summary_labels[status].pack()
            ttk.Label(frame, text=status.upper(), foreground=self.colors["muted"]).pack()
        
        # Results list
        results_frame = ttk.Frame(parent)
        results_frame.pack(fill=tk.BOTH, expand=True)
        
        # Treeview for results
        columns = ("time", "test", "status", "message", "latency")
        self.results_tree = ttk.Treeview(results_frame, columns=columns, show="headings")
        
        self.results_tree.heading("time", text="Time")
        self.results_tree.heading("test", text="Test")
        self.results_tree.heading("status", text="Status")
        self.results_tree.heading("message", text="Message")
        self.results_tree.heading("latency", text="Latency")
        
        self.results_tree.column("time", width=80)
        self.results_tree.column("test", width=150)
        self.results_tree.column("status", width=80)
        self.results_tree.column("message", width=300)
        self.results_tree.column("latency", width=100)
        
        scrollbar = ttk.Scrollbar(results_frame, orient=tk.VERTICAL, command=self.results_tree.yview)
        self.results_tree.configure(yscrollcommand=scrollbar.set)
        
        self.results_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # Bind selection
        self.results_tree.bind("<<TreeviewSelect>>", self._on_result_select)
        
        # Details panel
        details_frame = ttk.LabelFrame(parent, text="Details")
        details_frame.pack(fill=tk.X, pady=(10, 0))
        
        self.details_text = scrolledtext.ScrolledText(details_frame, height=8, font=("Courier", 10))
        self.details_text.pack(fill=tk.X, padx=5, pady=5)
        
    def _create_card(self, parent, title: str) -> ttk.Frame:
        """Create a card with title."""
        card = ttk.LabelFrame(parent, text=title, padding=10)
        card.pack(fill=tk.X, pady=(0, 10))
        return card
    
    def _set_test_input(self, text: str):
        """Set test input field."""
        self.test_input.delete("1.0", tk.END)
        self.test_input.insert("1.0", text)
    
    def _add_result(self, result: TestResult):
        """Add result to display."""
        self.results.append(result)
        
        # Add to treeview
        latency_str = f"{result.latency_ms:.0f}ms" if result.latency_ms > 0 else "-"
        item = self.results_tree.insert(
            "",
            0,  # Insert at top
            values=(result.timestamp, result.name, result.status.upper(), result.message, latency_str)
        )
        
        # Apply color tag
        self.results_tree.tag_configure(result.status, foreground=self.colors.get(result.status, "#000"))
        self.results_tree.item(item, tags=(result.status,))
        
        # Update summary
        self._update_summary()
        
    def _update_summary(self):
        """Update summary counts."""
        counts = {"pass": 0, "fail": 0, "warning": 0}
        for r in self.results:
            if r.status in counts:
                counts[r.status] += 1
        
        for status, count in counts.items():
            self.summary_labels[status].config(text=str(count))
    
    def _clear_results(self):
        """Clear all results."""
        self.results.clear()
        self.results_tree.delete(*self.results_tree.get_children())
        self._update_summary()
        self.details_text.delete("1.0", tk.END)
    
    def _on_result_select(self, event):
        """Handle result selection."""
        selection = self.results_tree.selection()
        if not selection:
            return
        
        item = selection[0]
        idx = len(self.results) - 1 - self.results_tree.index(item)
        
        if 0 <= idx < len(self.results):
            result = self.results[idx]
            self.details_text.delete("1.0", tk.END)
            self.details_text.insert("1.0", json.dumps(result.details, indent=2, ensure_ascii=False))
    
    def _run_in_thread(self, func, *args):
        """Run function in background thread."""
        def wrapper():
            try:
                func(*args)
            except Exception as e:
                self.root.after(0, lambda: self._add_result(
                    TestResult(name="Error", status="fail", message=str(e))
                ))
        
        thread = threading.Thread(target=wrapper, daemon=True)
        thread.start()
    
    def _run_single_test(self, test_func):
        """Run a single test in background."""
        def run():
            result = test_func()
            self.root.after(0, lambda: self._add_result(result))
        
        self._run_in_thread(run)
    
    def _run_health_checks(self):
        """Run all health checks."""
        def run():
            tests = [
                self.tester.check_api_health,
                self.tester.check_ollama,
                self.tester.check_graphcag_endpoint,
            ]
            
            for test_func in tests:
                result = test_func()
                self.root.after(0, lambda r=result: self._add_result(r))
                time.sleep(0.1)
        
        self._run_in_thread(run)
    
    def _refresh_hardware_info(self):
        """Refresh hardware information."""
        def run():
            info = self.tester.get_hardware_info()
            
            text = f"""CPU Usage:    {info.cpu_percent:.1f}% ({info.cpu_count} cores)
RAM Usage:    {info.ram_used_gb:.1f}GB / {info.ram_total_gb:.1f}GB ({info.ram_percent:.1f}%)
Disk Free:    {info.disk_free_gb:.1f}GB
GPU:          {"✓ " + info.gpu_name if info.gpu_available else "✗ Not detected"}
"""
            
            self.root.after(0, lambda: self._update_hw_display(text, info))
        
        self._run_in_thread(run)
    
    def _update_hw_display(self, text: str, info: HardwareInfo):
        """Update hardware display."""
        self.hw_info_text.delete("1.0", tk.END)
        self.hw_info_text.insert("1.0", text)
        
        # Add hardware result
        if info.ram_percent > 90:
            status = "warning"
            msg = f"High RAM usage: {info.ram_percent:.1f}%"
        elif info.cpu_percent > 90:
            status = "warning"
            msg = f"High CPU usage: {info.cpu_percent:.1f}%"
        else:
            status = "pass"
            msg = f"CPU: {info.cpu_percent:.1f}%, RAM: {info.ram_percent:.1f}%"
        
        self._add_result(TestResult(
            name="Hardware Check",
            status=status,
            message=msg,
            details={
                "cpu_percent": info.cpu_percent,
                "ram_percent": info.ram_percent,
                "gpu_available": info.gpu_available,
                "gpu_name": info.gpu_name
            }
        ))
    
    def _run_graphcag_test(self):
        """Run GraphCAG analysis test."""
        text = self.test_input.get("1.0", tk.END).strip()
        if not text:
            messagebox.showwarning("Warning", "Please enter test input")
            return
        
        def run():
            # Add info result
            self.root.after(0, lambda: self._add_result(TestResult(
                name="GraphCAG Test",
                status="info",
                message=f"Testing: {text[:50]}..."
            )))
            
            result = self.tester.test_graphcag_analyze(text)
            self.root.after(0, lambda: self._add_result(result))
        
        self._run_in_thread(run)
    
    def _test_ollama_inference(self):
        """Test Ollama inference performance."""
        self.ollama_status.config(text="Testing... (may take up to 2 minutes)")
        
        def run():
            result = self.tester.check_ollama_inference()
            self.root.after(0, lambda: self._add_result(result))
            self.root.after(0, lambda: self.ollama_status.config(text=result.message))
        
        self._run_in_thread(run)


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    """Main entry point."""
    root = tk.Tk()
    
    # Set icon if available
    try:
        root.iconphoto(True, tk.PhotoImage(file="icon.png"))
    except:
        pass
    
    app = GraphCAGTesterApp(root)
    
    # Initial hardware check
    root.after(500, app._refresh_hardware_info)
    
    root.mainloop()


if __name__ == "__main__":
    main()
