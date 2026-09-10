from fastapi import APIRouter, Depends, Header
from app.ldap.client import ldap_count
from app.auth.oidc import verify_token
from typing import Optional

router = APIRouter()


@router.get("/stats")
async def stats(authorization: Optional[str] = Header(None)):
    # MVP: allow unauthenticated for dashboard demo; production will require verify
    # if want enforce: claims = await verify_token(authorization)
    counts = {}
    # LDAP filters — source of truth per prompt
    filters = {
        "users": "(objectClass=user)",
        "groups": "(objectClass=group)",
        "ous": "(objectClass=organizationalUnit)",
        "computers": "(objectClass=computer)",
        # locked heuristic: lockoutTime >=1 (AD)
        "locked": "(&(objectClass=user)(lockoutTime>=1))",
        "disabled": "(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2))",
    }
    for k, f in filters.items():
        counts[k] = ldap_count(f)

    return {
        "domain": "rentoption.com",
        "realm": "RENTOPTION.COM",
        "counts": counts,
        "note": "null = LDAP not configured or bind failed; counts are live LDAP queries",
    }
