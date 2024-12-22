# Homelab Overview

This document provides a high-level summary of the services and tools running in my homelab. It explains why each service was chosen, how they interact with each other, and any special considerations or configurations.

## Goals

- **Self-Hosting**: Minimize third-party cloud dependencies by hosting core services at home.  
- **Scalability**: Ensure that new services or expansions can be added without a full redesign.  
- **Maintainability**: Use infrastructure-as-code (Docker Compose, scripts) to simplify updates and backups.  
- **Security**: Leverage best practices (e.g., minimal privileges, SSL, strong passwords) to protect data.

## Services

1. **Nextcloud**  
   - Purpose: Self-hosted cloud storage and collaboration  
   - Key Features: File sync, calendar, contacts, document editing (via Collabora/OnlyOffice)  
   - Why: A privacy-respecting alternative to Google Drive or Dropbox.

2. **Linkwarden**  
   - Purpose: Personal bookmark archiving and management  
   - Why: Centralize and organize bookmarks, plus offline archiving in case of link rot.

3. **Immich**  
   - Purpose: Self-hosted photo storage and sharing  
   - Why: Keep control over personal photos and metadata, avoiding public cloud lock-in.

4. **Vaultwarden**  
   - Purpose: Self-hosted password management (Bitwarden-compatible)  
   - Why: Store credentials locally, with end-to-end encryption.

5. **Portainer**  
   - Purpose: Docker/Container management GUI  
   - Why: Easily monitor and control containers, images, networks, volumes.

6. **PaperlessNGX**  
   - Purpose: Document management and OCR system  
   - Why: Digitally organize, tag, and search scanned documents.

7. **RR Stack** (Radarr, Sonarr, Sabnzbd, Bazarr, etc.)  
   - Purpose: Media automation (movies, TV shows, subtitles)  
   - Why: Automate downloads, organization, and metadata handling.

8. **Nginx Proxy Manager** (or Caddy/Traefik)  
   - Purpose: Reverse proxy with easy certificate management  
   - Why: Simplify SSL setup and route incoming requests to internal services.

9. **Other Services**  
    - E.g., Plex, Jellyseerr, Tdarr, etc., for media streaming and transcoding.

## Organization

- All services are containerized using **Docker Compose**, grouped by function (e.g., Nextcloud stack, Media stack, Linkwarden stack).  


## What’s Next?
  
- **Kubernetes** Potentially exploring a more advanced orchestrator in the future.  

Feel free to browse the [architecture documentation](architecture.md) for a technical overview of how the services are networked.


