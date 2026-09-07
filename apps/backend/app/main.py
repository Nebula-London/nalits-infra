from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.health import router as health_router
from app.api.stats import router as stats_router
from loguru import logger

app = FastAPI(title=settings.app_name, version=settings.version)

origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"name": settings.app_name, "version": settings.version, "docs": "/docs", "health": "/health"}


app.include_router(health_router, tags=["health"])
app.include_router(stats_router, tags=["stats"])

# placeholder routers for MVP expansion (users/groups/ous/dns/audit)
# from app.api.users import router as users_router
# app.include_router(users_router, prefix="/users", tags=["users"])


@app.on_event("startup")
async def startup():
    logger.info(f"Starting {settings.app_name} v{settings.version} — LDAP {settings.ldap_host}:{settings.ldap_port} base {settings.ldap_base_dn}")
