"""
Performance Monitor

Real-time system performance monitoring using psutil.
Tracks CPU, memory, disk usage and provides health checks.
"""

import psutil
import logging
from typing import Dict, Any, List
from datetime import datetime

logger = logging.getLogger(__name__)


class PerformanceMonitor:
    """
    Monitor system and application performance.
    
    Provides real-time statistics on:
    - CPU usage and load
    - Memory usage (total, available, used)
    - Disk usage
    - Resource health warnings
    
    Usage:
        monitor = get_performance_monitor()
        stats = monitor.get_system_stats()
        health = monitor.check_resource_health()
    """
    
    def get_system_stats(self) -> Dict[str, Any]:
        """
        Get comprehensive system statistics.
        
        Returns:
            Dict with CPU, memory, disk stats and timestamp
        """
        return {
            "cpu": self.get_cpu_stats(),
            "memory": self.get_memory_stats(),
            "disk": self.get_disk_stats(),
            "network": self.get_network_stats(),
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    
    def get_cpu_stats(self) -> Dict[str, Any]:
        """
        Get CPU usage statistics.
        
        Returns:
            Dict with CPU percent, count, and load average
        """
        stats = {
            "percent": psutil.cpu_percent(interval=0.1),
            "count": psutil.cpu_count(),
            "count_logical": psutil.cpu_count(logical=True)
        }
        
        # Load average (Unix only)
        if hasattr(psutil, 'getloadavg'):
            load = psutil.getloadavg()
            stats["load_avg_1min"] = round(load[0], 2)
            stats["load_avg_5min"] = round(load[1], 2)
            stats["load_avg_15min"] = round(load[2], 2)
        
        return stats
    
    def get_memory_stats(self) -> Dict[str, Any]:
        """
        Get memory usage statistics.
        
        Returns:
            Dict with memory totals in GB and usage percentage
        """
        mem = psutil.virtual_memory()
        
        return {
            "total_gb": round(mem.total / (1024 ** 3), 2),
            "available_gb": round(mem.available / (1024 ** 3), 2),
            "used_gb": round(mem.used / (1024 ** 3), 2),
            "free_gb": round(mem.free / (1024 ** 3), 2),
            "percent": round(mem.percent, 1),
            "cached_gb": round(getattr(mem, 'cached', 0) / (1024 ** 3), 2) if hasattr(mem, 'cached') else 0
        }
    
    def get_disk_stats(self) -> Dict[str, Any]:
        """
        Get disk usage statistics for root partition.
        
        Returns:
            Dict with disk space in GB and usage percentage
        """
        disk = psutil.disk_usage('/')
        
        return {
            "total_gb": round(disk.total / (1024 ** 3), 2),
            "used_gb": round(disk.used / (1024 ** 3), 2),
            "free_gb": round(disk.free / (1024 ** 3), 2),
            "percent": round(disk.percent, 1)
        }
    
    def get_network_stats(self) -> Dict[str, Any]:
        """
        Get network I/O statistics.
        
        Returns:
            Dict with bytes sent/received
        """
        net = psutil.net_io_counters()
        
        return {
            "bytes_sent_mb": round(net.bytes_sent / (1024 ** 2), 2),
            "bytes_recv_mb": round(net.bytes_recv / (1024 ** 2), 2),
            "packets_sent": net.packets_sent,
            "packets_recv": net.packets_recv,
            "errors_in": net.errin,
            "errors_out": net.errout
        }
    
    def check_resource_health(self) -> Dict[str, Any]:
        """
        Check if system resources are healthy.
        
        Returns warnings if resources are constrained.
        
        Returns:
            Dict with healthy flag, warnings list, and timestamp
        """
        warnings: List[Dict[str, str]] = []
        
        # Check CPU
        cpu_percent = psutil.cpu_percent(interval=0.1)
        if cpu_percent > 90:
            warnings.append({
                "type": "CRITICAL_CPU",
                "message": f"CPU usage is critically high: {cpu_percent}%",
                "severity": "critical",
                "value": cpu_percent
            })
        elif cpu_percent > 80:
            warnings.append({
                "type": "HIGH_CPU",
                "message": f"CPU usage is high: {cpu_percent}%",
                "severity": "warning",
                "value": cpu_percent
            })
        
        # Check memory
        mem = psutil.virtual_memory()
        if mem.percent > 90:
            warnings.append({
                "type": "CRITICAL_MEMORY",
                "message": f"Memory usage is critically high: {mem.percent}%",
                "severity": "critical",
                "value": mem.percent
            })
        elif mem.percent > 85:
            warnings.append({
                "type": "HIGH_MEMORY",
                "message": f"Memory usage is high: {mem.percent}%",
                "severity": "warning",
                "value": mem.percent
            })
        
        # Check disk
        disk = psutil.disk_usage('/')
        if disk.percent > 95:
            warnings.append({
                "type": "CRITICAL_DISK",
                "message": f"Disk usage is critically high: {disk.percent}%",
                "severity": "critical",
                "value": disk.percent
            })
        elif disk.percent > 90:
            warnings.append({
                "type": "LOW_DISK",
                "message": f"Disk space is running low: {disk.percent}%",
                "severity": "warning",
                "value": disk.percent
            })
        
        # Check load average (Unix only)
        if hasattr(psutil, 'getloadavg'):
            load_avg = psutil.getloadavg()[0]
            cpu_count = psutil.cpu_count()
            
            if load_avg > cpu_count * 2:
                warnings.append({
                    "type": "HIGH_LOAD",
                    "message": f"System load is very high: {load_avg} (CPUs: {cpu_count})",
                    "severity": "warning",
                    "value": load_avg
                })
        
        return {
            "healthy": len(warnings) == 0,
            "warnings": warnings,
            "warning_count": len(warnings),
            "critical_count": sum(1 for w in warnings if w["severity"] == "critical"),
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    
    def get_process_stats(self) -> Dict[str, Any]:
        """
        Get statistics for current process.
        
        Returns:
            Dict with process-specific CPU and memory usage
        """
        process = psutil.Process()
        
        with process.oneshot():
            mem_info = process.memory_info()
            
            return {
                "pid": process.pid,
                "cpu_percent": round(process.cpu_percent(interval=0.1), 2),
                "memory_mb": round(mem_info.rss / (1024 ** 2), 2),
                "memory_percent": round(process.memory_percent(), 2),
                "num_threads": process.num_threads(),
                "num_fds": process.num_fds() if hasattr(process, 'num_fds') else None,
                "create_time": datetime.fromtimestamp(process.create_time()).isoformat()
            }


# Singleton instance
_performance_monitor: PerformanceMonitor = None


def get_performance_monitor() -> PerformanceMonitor:
    """
    Get performance monitor singleton.
    
    Returns:
        PerformanceMonitor instance
    """
    global _performance_monitor
    
    if _performance_monitor is None:
        _performance_monitor = PerformanceMonitor()
    
    return _performance_monitor
