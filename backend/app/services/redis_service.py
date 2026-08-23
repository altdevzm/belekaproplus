import os
import json
import logging
from typing import Any, Optional
import redis

logger = logging.getLogger(__name__)

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_DB = int(os.getenv("REDIS_DB", 0))

class RedisService:
    def __init__(self):
        try:
            self.client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                db=REDIS_DB,
                decode_responses=True,
                socket_timeout=2.0
            )
            self.is_connected = self.client.ping()
            if self.is_connected:
                logger.info(f"Connected to Redis server at {REDIS_HOST}:{REDIS_PORT}")
        except Exception as e:
            self.is_connected = False
            logger.warning(f"Redis not available ({e}). Running without in-memory caching.")

    def get_json(self, key: str) -> Optional[Any]:
        """Fetch and deserialize JSON value from Redis."""
        if not self.is_connected:
            return None
        try:
            val = self.client.get(key)
            if val:
                return json.loads(val)
        except Exception as e:
            logger.warning(f"Redis get error for key '{key}': {e}")
        return None

    def set_json(self, key: str, value: Any, ttl_seconds: int = 300) -> bool:
        """Serialize and store value in Redis with TTL expiration."""
        if not self.is_connected:
            return False
        try:
            val_str = json.dumps(value, default=str)
            return bool(self.client.setex(key, ttl_seconds, val_str))
        except Exception as e:
            logger.warning(f"Redis set error for key '{key}': {e}")
            return False

    def delete(self, key: str) -> bool:
        """Delete specific key from Redis."""
        if not self.is_connected:
            return False
        try:
            return bool(self.client.delete(key))
        except Exception as e:
            logger.warning(f"Redis delete error for key '{key}': {e}")
            return False

    def invalidate_store_cache(self, store_id: int):
        """Invalidate all cached data for a specific store branch."""
        if not self.is_connected:
            return
        try:
            pattern = f"store:{store_id}:*"
            keys = self.client.keys(pattern)
            if keys:
                self.client.delete(*keys)
                logger.info(f"Invalidated {len(keys)} Redis keys for store {store_id}")
        except Exception as e:
            logger.warning(f"Redis cache invalidation error for store {store_id}: {e}")

redis_service = RedisService()
