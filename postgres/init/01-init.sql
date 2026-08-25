-- ===========================================
-- PostgreSQL Initialization for Keycloak
-- Runs on first database creation
-- ===========================================

-- Ensure extensions are available
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Set default privileges for keycloak user
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO keycloak;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Keycloak database initialized at %', now();
END $$;