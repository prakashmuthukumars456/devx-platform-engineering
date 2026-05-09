from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
import redis.asyncio as aioredis
from app.database import get_db
from app.core.config import get_settings

router = APIRouter(prefix="/health", tags=["health"])
settings = get_settings()


@router.get("/live")
async def liveness():
    """
    Liveness probe — answers: is the process alive?
    K8s restarts the pod if this fails.
    Keep it dead-simple: no DB, no Redis.
    """
    return {"status": "alive", "version": settings.APP_VERSION}


@router.get("/ready")
async def readiness(db: AsyncSession = Depends(get_db)):
    """
    Readiness probe — answers: is the app ready to serve traffic?
    K8s stops sending traffic if this fails (but doesn't restart the pod).
    Check DB and Redis here.
    """
    checks = {}

    # Database check
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = f"error: {str(e)}"

    # Redis check
    try:
        r = aioredis.from_url(settings.REDIS_URL, socket_connect_timeout=2)
        await r.ping()
        await r.aclose()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = f"error: {str(e)}"

    all_ok = all(v == "ok" for v in checks.values())

    return {
        "status": "ready" if all_ok else "degraded",
        "checks": checks,
    }


@router.get("")
async def health_summary():
    """
    Simple health endpoint — used by docker-compose and load balancers.
    """
    return {
        "status": "ok",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "env": settings.APP_ENV,
    }
