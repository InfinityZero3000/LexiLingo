"""
Structured Logging Configuration

Provides JSON-formatted logging with request context tracking and
performance measurement capabilities.
"""

import logging
import json
import time
from typing import Dict, Any, Optional
from datetime import datetime
from contextvars import ContextVar

# Context variable for request tracking
request_context: ContextVar[Dict[str, Any]] = ContextVar('request_context', default={})


class StructuredFormatter(logging.Formatter):
    """
    JSON formatter for structured logging.
    
    Outputs logs in JSON format for easy parsing by log aggregators
    like ElasticSearch, Splunk, or CloudWatch.
    """
    
    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON."""
        log_data = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno
        }
        
        # Add request context if available
        ctx = request_context.get()
        if ctx:
            if "request_id" in ctx:
                log_data["request_id"] = ctx["request_id"]
            if "session_id" in ctx:
                log_data["session_id"] = ctx["session_id"]
            if "user_id" in ctx:
                log_data["user_id"] = ctx["user_id"]
        
        # Add extra fields from record
        if hasattr(record, 'extra_data'):
            log_data.update(record.extra_data)
        
        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)
            log_data["exc_type"] = record.exc_info[0].__name__ if record.exc_info[0] else None
        
        return json.dumps(log_data)


class PerformanceLogger:
    """
    Context manager for tracking performance of operations.
    
    Usage:
        with PerformanceLogger("load_model") as perf:
            model = load_model()
            perf.log_milestone("model_loaded")
            process(model)
            perf.log_milestone("processing_done")
    
    This automatically logs start, milestones, and completion with timings.
    """
    
    def __init__(self, operation: str, logger: Optional[logging.Logger] = None):
        self.operation = operation
        self.logger = logger or logging.getLogger(__name__)
        self.start_time = None
        self.milestones = []
    
    def __enter__(self):
        """Start performance tracking."""
        self.start_time = time.time()
        self.logger.debug(
            f"Started: {self.operation}",
            extra={'extra_data': {'operation': self.operation, 'status': 'started'}}
        )
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Complete performance tracking and log results."""
        duration_ms = (time.time() - self.start_time) * 1000
        
        log_data = {
            'operation': self.operation,
            'duration_ms': round(duration_ms, 2),
            'milestones': self.milestones
        }
        
        if exc_type:
            log_data['status'] = 'failed'
            log_data['error'] = str(exc_val)
            log_data['error_type'] = exc_type.__name__
            
            self.logger.error(
                f"Failed: {self.operation} ({duration_ms:.2f}ms)",
                extra={'extra_data': log_data}
            )
        else:
            log_data['status'] = 'completed'
            
            self.logger.info(
                f"Completed: {self.operation} ({duration_ms:.2f}ms)",
                extra={'extra_data': log_data}
            )
        
        return False  # Don't suppress exceptions
    
    def log_milestone(self, name: str, metadata: Optional[Dict[str, Any]] = None):
        """
        Log a milestone during operation.
        
        Args:
            name: Milestone name
            metadata: Optional additional data
        """
        elapsed_ms = (time.time() - self.start_time) * 1000
        
        milestone = {
            'name': name,
            'elapsed_ms': round(elapsed_ms, 2)
        }
        
        if metadata:
            milestone['metadata'] = metadata
        
        self.milestones.append(milestone)
        
        self.logger.debug(
            f"Milestone: {self.operation}/{name} ({elapsed_ms:.2f}ms)",
            extra={'extra_data': milestone}
        )


def setup_logging(
    level: str = "INFO",
    log_file: Optional[str] = None,
    json_format: bool = False
):
    """
    Configure application logging.
    
    Args:
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: Optional file path to write logs to
        json_format: Use JSON structured logging format
    
    Example:
        # Development
        setup_logging(level="DEBUG", json_format=False)
        
        # Production
        setup_logging(level="INFO", json_format=True, log_file="/var/log/app.log")
    """
    # Get root logger
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, level.upper()))
    
    # Remove existing handlers
    logger.handlers.clear()
    
    # Console handler
    console_handler = logging.StreamHandler()
    
    if json_format:
        console_handler.setFormatter(StructuredFormatter())
    else:
        console_handler.setFormatter(
            logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
        )
    
    logger.addHandler(console_handler)
    
    # File handler if specified
    if log_file:
        file_handler = logging.FileHandler(log_file)
        
        if json_format:
            file_handler.setFormatter(StructuredFormatter())
        else:
            file_handler.setFormatter(
                logging.Formatter(
                    '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S'
                )
            )
        
        logger.addHandler(file_handler)
    
    logger.info(f"Logging configured: level={level}, json={json_format}, file={log_file}")


def set_request_context(
    request_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None
):
    """
    Set request context for structured logging.
    
    Call this at the start of request handling to add context to all logs.
    """
    ctx = {}
    if request_id:
        ctx['request_id'] = request_id
    if session_id:
        ctx['session_id'] = session_id
    if user_id:
        ctx['user_id'] = user_id
    
    request_context.set(ctx)


def clear_request_context():
    """Clear request context."""
    request_context.set({})
