"""
MongoDB Database Manager

Async MongoDB client following Repository pattern
Similar to Flutter's DataSource layer in Clean Architecture
"""

import logging
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo.errors import ConnectionFailure, ServerSelectionTimeoutError

from api.core.config import settings

logger = logging.getLogger(__name__)


class MongoDBManager:
    """
    MongoDB connection manager (Singleton pattern).
    
    Similar to Flutter's DatabaseHelper singleton.
    """
    
    _instance: Optional['MongoDBManager'] = None
    _client: Optional[AsyncIOMotorClient] = None
    _db: Optional[AsyncIOMotorDatabase] = None
    
    def __new__(cls):
        """Ensure singleton instance."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    async def connect(self) -> None:
        """
        Connect to MongoDB.
        
        Similar to Flutter's DatabaseHelper.database getter.
        """
        if self._client is not None:
            logger.info("MongoDB already connected")
            return
        
        try:
            logger.info(f"Connecting to MongoDB: {settings.MONGODB_DATABASE}")
            
            # MongoDB Atlas requires ServerApi for stable API version
            from pymongo.server_api import ServerApi
            
            # Create async client with Atlas support
            connection_kwargs: dict = {
                "maxPoolSize": settings.MONGODB_MAX_POOL_SIZE,
                "minPoolSize": settings.MONGODB_MIN_POOL_SIZE,
                "serverSelectionTimeoutMS": 10000,
            }
            
            # Add ServerApi if using MongoDB Atlas (mongodb+srv://)
            if "mongodb+srv://" in settings.MONGODB_URI:
                connection_kwargs["server_api"] = ServerApi('1')
                logger.info("Using MongoDB Atlas with Stable API v1")
            
            self._client = AsyncIOMotorClient(
                settings.MONGODB_URI,
                **connection_kwargs
            )
            
            # Test connection
            await self._client.admin.command('ping')
            
            # Get database
            self._db = self._client[settings.MONGODB_DATABASE]
            
            logger.info(f"MongoDB connected: {settings.MONGODB_DATABASE}")
            
        except (ConnectionFailure, ServerSelectionTimeoutError) as e:
            logger.error(f"Failed to connect to MongoDB: {e}")
            raise
    
    async def disconnect(self) -> None:
        """Disconnect from MongoDB."""
        if self._client:
            self._client.close()
            self._client = None
            self._db = None
            logger.info("MongoDB disconnected")
    
    @property
    def db(self) -> AsyncIOMotorDatabase:
        """
        Get database instance.
        
        Raises:
            RuntimeError: If database not connected
        """
        if self._db is None:
            raise RuntimeError("Database not connected. Call connect() first.")
        return self._db
    
    @property
    def is_connected(self) -> bool:
        """Check if database is connected."""
        return self._client is not None


# Global instance (similar to Flutter's GetIt registration)
mongodb_manager = MongoDBManager()


# Dependency injection for FastAPI routes
async def get_database() -> AsyncIOMotorDatabase:
    """
    Get database instance for dependency injection.
    
    Usage in routes:
        @router.get("/")
        async def handler(db: AsyncIOMotorDatabase = Depends(get_database)):
            ...
    
    Raises RuntimeError if MongoDB is not connected.
    """
    if not mongodb_manager.is_connected:
        try:
            await mongodb_manager.connect()
        except Exception:
            raise RuntimeError(
                "MongoDB is not available. Please check your MongoDB connection."
            )
    
    return mongodb_manager.db
