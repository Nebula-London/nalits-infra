import ssl
from ldap3 import Server, Connection, ALL, Tls
from ldap3.core.exceptions import LDAPException
from app.core.config import settings
from loguru import logger


def get_ldap_server() -> Server:
    tls = None
    if settings.ldap_use_ssl:
        tls_kwargs = {"validate": ssl.CERT_NONE if not settings.ldap_tls_verify else ssl.CERT_REQUIRED}
        tls = Tls(validate=ssl.CERT_NONE, version=ssl.PROTOCOL_TLSv1_2)
        if settings.ldap_tls_verify:
            tls.validate = ssl.CERT_REQUIRED
    host = settings.ldap_host
    port = settings.ldap_port
    use_ssl = settings.ldap_use_ssl
    # ldap3 Server handles ldaps:// when use_ssl True
    server = Server(host, port=port, use_ssl=use_ssl, get_info=ALL, tls=tls, connect_timeout=5)
    return server


def ldap_bind_test() -> dict:
    """Test bind — used by /health. Safe, no injection."""
    pwd = settings.effective_ldap_password
    if not pwd:
        return {"ok": False, "error": "LDAP password not configured (LDAP_BIND_PASSWORD / SAMBA_ADMIN_PASSWORD)"}
    server = get_ldap_server()
    try:
        conn = Connection(server, user=settings.ldap_bind_dn, password=pwd, auto_bind=True, receive_timeout=5)
        # simple search to verify permissions
        conn.search(settings.ldap_base_dn, "(objectClass=domain)", attributes=["dc"])
        bound = conn.bound
        conn.unbind()
        return {"ok": bound, "host": f"{settings.ldap_host}:{settings.ldap_port}", "base_dn": settings.ldap_base_dn}
    except LDAPException as e:
        logger.warning(f"LDAP bind failed: {e}")
        return {"ok": False, "error": str(e), "host": f"{settings.ldap_host}:{settings.ldap_port}"}
    except Exception as e:
        logger.warning(f"LDAP unexpected error: {e}")
        return {"ok": False, "error": str(e)}


def ldap_count(base_filter: str) -> int | None:
    pwd = settings.effective_ldap_password
    if not pwd:
        return None
    server = get_ldap_server()
    try:
        conn = Connection(server, user=settings.ldap_bind_dn, password=pwd, auto_bind=True)
        # count via search; paged not needed for counts < 5k in MVP
        conn.search(settings.ldap_base_dn, base_filter, attributes=["cn"])
        count = len(conn.entries)
        conn.unbind()
        return count
    except Exception as e:
        logger.warning(f"ldap_count {base_filter} failed: {e}")
        return None
