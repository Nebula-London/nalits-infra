# Nginx public edge

Public reverse proxy only. Cloudflare sits in front. Nginx must terminate or pass through TLS according to the chosen origin model, allow only required upstreams, and never become a generic router into private networks.
