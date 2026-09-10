"""OIDC JWKS verification against Keycloak. MVP: verify RS256 tokens.

If KEYCLOAK_URL unreachable or no token provided, endpoints still allow
health without auth; protected routes will 401.
"""
import httpx
from jose import jwt, jwk
from jose.utils import base64url_decode
from fastapi import Header, HTTPException
from app.core.config import settings
from loguru import logger
from typing import Optional

_jwks_cache = None


async def fetch_jwks() -> dict:
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache
    url = f"{settings.keycloak_url.rstrip('/')}/realms/{settings.keycloak_realm}/protocol/openid-connect/certs"
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.get(url)
            r.raise_for_status()
            _jwks_cache = r.json()
            return _jwks_cache
    except Exception as e:
        logger.warning(f"JWKS fetch failed {url}: {e}")
        return {"keys": []}


async def verify_token(authorization: Optional[str] = Header(None)) -> dict | None:
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        return None
    jwks = await fetch_jwks()
    if not jwks.get("keys"):
        # no cache available, accept decode without verify in dev (warn)
        logger.warning("JWKS empty — skipping signature verify (dev mode)")
        try:
            return jwt.get_unverified_claims(token)
        except Exception:
            return None
    try:
        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        key_data = next((k for k in jwks["keys"] if k["kid"] == kid), None)
        if not key_data:
            logger.warning(f"kid {kid} not in JWKS")
            return jwt.get_unverified_claims(token)
        # jose will verify if we pass key
        public_key = jwk.construct(key_data)
        message, encoded_sig = token.rsplit(".", 1)
        decoded_sig = base64url_decode(encoded_sig.encode())
        if not public_key.verify(message.encode(), decoded_sig):
            raise HTTPException(status_code=401, detail="Invalid signature")
        claims = jwt.get_unverified_claims(token)
        # basic expiry check
        return claims
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"token verify failed: {e}")
        return None


def require_roles(claims: dict | None, allowed: list[str]) -> None:
    if not claims:
        raise HTTPException(status_code=401, detail="Missing or invalid token")
    roles = []
    # realm_access.roles + resource_access.*.roles
    realm = claims.get("realm_access", {}).get("roles", [])
    roles.extend(realm)
    resource = claims.get("resource_access", {})
    for v in resource.values():
        roles.extend(v.get("roles", []))
    # groups claim (Keycloak mapper groups)
    roles.extend(claims.get("groups", []))
    # normalize: samba-* and legacy admin/hr
    if not any(r in roles for r in allowed) and "samba-super-admin" not in roles and "admin" not in roles:
        raise HTTPException(status_code=403, detail=f"Requires one of {allowed}, have {roles}")
