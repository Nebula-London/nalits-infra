from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    app_name: str = "Samba AD Management API"
    version: str = "0.1.0-mvp"
    debug: bool = False

    ldap_host: str = Field(default="samba", alias="LDAP_HOST")
    ldap_port: int = Field(default=389, alias="LDAP_PORT")
    ldap_base_dn: str = Field(default="DC=RENTOPTION,DC=COM", alias="LDAP_BASE_DN")
    ldap_bind_dn: str = Field(default="CN=Administrator,CN=Users,DC=RENTOPTION,DC=COM", alias="LDAP_BIND_DN")
    ldap_bind_password: str = Field(default="", alias="LDAP_BIND_PASSWORD")
    # fallback to SAMBA_ADMIN_PASSWORD if LDAP_BIND_PASSWORD not set
    samba_admin_password: str = Field(default="", alias="SAMBA_ADMIN_PASSWORD")
    ldap_use_ssl: bool = Field(default=False, alias="LDAP_USE_SSL")
    ldap_tls_verify: bool = Field(default=False, alias="LDAP_TLS_VERIFY")

    keycloak_url: str = Field(default="https://sso.rentoption.com", alias="KEYCLOAK_URL")
    keycloak_realm: str = Field(default="rentoption.com", alias="KEYCLOAK_REALM")
    keycloak_client_id: str = Field(default="samba-admin-ui", alias="KEYCLOAK_CLIENT_ID")
    keycloak_client_secret: str = Field(default="", alias="KEYCLOAK_CLIENT_SECRET")

    # Oracle - reuse KC DB; optional for MVP (health OK without DB)
    db_url: str = Field(default="", alias="SAMBA_UI_DB_URL")
    db_username: str = Field(default="", alias="SAMBA_UI_DB_USERNAME")
    db_password: str = Field(default="", alias="SAMBA_UI_DB_PASSWORD")
    # also accept KC_* vars as fallback
    kc_db_url: str = Field(default="", alias="KC_DB_URL")
    kc_db_username: str = Field(default="", alias="KC_DB_USERNAME")
    kc_db_password: str = Field(default="", alias="KC_DB_PASSWORD")

    redis_url: str = Field(default="redis://samba-redis:6379/0", alias="REDIS_URL")
    redis_password: str = Field(default="", alias="REDIS_PASSWORD")

    session_secret: str = Field(default="change-me", alias="SESSION_SECRET")
    cors_origins: str = Field(default="https://dc.rentoption.com,http://localhost:3000", alias="CORS_ORIGINS")

    class Config:
        env_file = ".env"
        extra = "ignore"

    @property
    def effective_ldap_password(self) -> str:
        return self.ldap_bind_password or self.samba_admin_password

    @property
    def effective_db_url(self) -> str:
        return self.db_url or self.kc_db_url

    @property
    def effective_db_username(self) -> str:
        return self.db_username or self.kc_db_username

    @property
    def effective_db_password(self) -> str:
        return self.db_password or self.kc_db_password


settings = Settings()
