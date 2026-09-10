from fastapi import APIRouter
from app.ldap.client import ldap_bind_test
from app.core.config import settings
import httpx
import subprocess
import shutil

router = APIRouter()


@router.get("/health")
async def health():
    ldap = ldap_bind_test()
    # Keycloak reachability (internal DNS sso.rentoption.com may not resolve from backend; use keycloak:8080 fallback)
    kc_urls = [
        f"{settings.keycloak_url}/realms/{settings.keycloak_realm}/.well-known/openid-configuration",
        "http://keycloak:8080/realms/rentoption.com/.well-known/openid-configuration",
    ]
    kc_ok = False
    kc_error = None
    for url in kc_urls:
        try:
            async with httpx.AsyncClient(timeout=3) as c:
                r = await c.get(url)
                if r.status_code == 200:
                    kc_ok = True
                    break
                kc_error = f"{url} -> {r.status_code}"
        except Exception as e:
            kc_error = str(e)
    # Redis ping (optional)
    redis_ok = None
    try:
        import redis as redis_lib

        pwd = settings.redis_password or None
        # redis_url already includes host; try simple
        r = redis_lib.from_url(settings.redis_url, password=pwd, socket_connect_timeout=2)
        r.ping()
        redis_ok = True
    except Exception as e:
        redis_ok = False
        # not fatal for MVP
    # Oracle check (lazy)
    oracle_ok = None
    if settings.effective_db_url:
        try:
            import oracledb

            # thin mode, no instant client
            # do not actually connect in health if password missing
            oracle_ok = "configured"
        except Exception as e:
            oracle_ok = f"driver error: {e}"
    else:
        oracle_ok = "not configured (UI prefs/audit will be in-memory stub)"

    status = "ok" if ldap.get("ok") else "degraded"
    return {
        "status": status,
        "version": settings.version,
        "ldap": ldap,
        "keycloak": {"ok": kc_ok, "error": kc_error, "realm": settings.keycloak_realm},
        "redis": {"ok": redis_ok, "url": settings.redis_url},
        "oracle": oracle_ok,
    }


@router.get("/health/domain")
async def domain_health():
    """Minimal domain health — mirrors prompt Domain Health checks (drs, dns, sysvol placeholder)."""
    checks = {}
    # LDAP already
    checks["ldap"] = ldap_bind_test()
    # samba-tool presence
    has_samba_tool = shutil.which("samba-tool") is not None
    checks["samba_tool"] = {"ok": has_samba_tool, "path": shutil.which("samba-tool")}
    # drs showrepl — only if samba-tool exists and we can exec (will fail from api container without samba socket; report accordingly)
    if has_samba_tool:
        try:
            # timeout quickly
            result = subprocess.run(["samba-tool", "drs", "showrepl"], capture_output=True, text=True, timeout=5)
            checks["drs"] = {"ok": result.returncode == 0, "output_snippet": result.stdout[:2000] if result.returncode == 0 else result.stderr[:2000]}
        except Exception as e:
            checks["drs"] = {"ok": False, "error": str(e), "note": "Run from samba DC container for full output"}
    else:
        checks["drs"] = {"ok": None, "note": "samba-tool not in api image — check via samba container"}

    # overall indicator
    def indicator(v):
        if v is True:
            return "green"
        if v is False:
            return "red"
        return "yellow"

    indicators = {k: indicator(v.get("ok")) for k, v in checks.items() if isinstance(v, dict) and "ok" in v}
    return {"checks": checks, "indicators": indicators}
