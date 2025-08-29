# 🏠 Homelab Infrastructure

A comprehensive Docker-based home laboratory infrastructure showcasing modern DevOps practices, container orchestration, and automated deployment.

## 📋 Project Overview

This homelab represents a fully containerized infrastructure with over 40 Docker containers running various services including AI/ML platforms, document management, media servers, monitoring tools, and automation workflows. The setup demonstrates enterprise-grade DevOps practices in a home environment.

## 🏗️ Architecture Diagram

```mermaid
graph TB
    subgraph "Networking & Proxy"
        NPM[Nginx Proxy Manager]
        GLUE[Gluetun VPN]
    end

    subgraph "AI & Machine Learning"
        OLLAMA[Ollama LLM]
        OPENWEBUI[OpenWebUI]
        IMMICH_ML[Immich ML]
    end

    subgraph "Storage & Media"
        IMMICH[Immich Photo]
        PLEX[Plex Media]
        NEXTCLOUD[Nextcloud]
    end

    subgraph "Automation & Workflows"
        N8N[n8n Automation]
        PAPERLESS[Paperless-ngx]
        PAPERLESS_AI[Paperless-AI]
    end

    subgraph "Monitoring & Management"
        PORTAINER[Portainer]
        PROMETHEUS[Prometheus]
        WATCHTOWER[Watchtower]
    end

    NPM --> OLLAMA
    NPM --> OPENWEBUI
    NPM --> IMMICH
    NPM --> PLEX
    NPM --> NEXTCLOUD
    NPM --> N8N
    
    GLUE --> PLEX
    GLUE --> RADARR
    GLUE --> SONARR
```

## 🛠️ Tech Stack

### Containerization & Orchestration
- **Docker** - Container runtime
- **Docker Compose** - Container orchestration
- **Portainer** - Container management UI
- **Watchtower** - Automatic container updates

### Networking & Security
- **Nginx Proxy Manager** - Reverse proxy with SSL
- **Gluetun VPN** - Secure container networking
- **Vaultwarden** - Password manager

### AI & Machine Learning
- **Ollama** - Large Language Model framework
- **OpenWebUI** - Web interface for LLMs
- **Immich Machine Learning** - Photo analysis AI

### Storage & Media
- **Immich** - Google Photos alternative
- **Plex** - Media server
- **Nextcloud** - File sharing & collaboration
- **Paperless-ngx** - Document management
- **Paperless-AI** - AI-powered document processing

### Automation & Monitoring
- **n8n** - Workflow automation
- **Prometheus** - Monitoring & alerting
- **Gotify** - Push notifications

## 🤖 AI & Machine Learning Stack

### Ollama + OpenWebUI - Modern AI Infrastructure

This homelab features a cutting-edge AI stack with **Ollama** for local LLM inference and **OpenWebUI** as a professional ChatGPT alternative. This combination represents the forefront of self-hosted AI infrastructure and is currently at the center of the AI narrative.

#### 🎯 Why This Matters for DevOps/SRE Roles:
- **Enterprise AI Readiness**: Demonstrates ability to deploy and manage production AI infrastructure
- **GPU Optimization**: AMD ROCm integration shows hardware acceleration expertise
- **Scalable AI Services**: Containerized approach allows horizontal scaling of AI workloads
- **Monitoring Integration**: AI services integrated with Prometheus monitoring stack

#### Key Features:
- **Local LLM Inference**: Run models like Llama 3 (70B), Mistral (8x22B), and CodeLlama locally
- **Enterprise Web Interface**: Production-grade web UI comparable to ChatGPT Plus
- **Multi-Model Orchestration**: Dynamic model loading and switching capabilities
- **Voice Integration**: Edge-TTS with German language support for text-to-speech
- **Document Intelligence**: Apache Tika for advanced document processing and analysis
- **GPU Acceleration**: Full AMD ROCm support with hardware optimization

#### Architecture:
```mermaid
graph TB
    User[User Request] --> NPM[Nginx Proxy]
    NPM --> OpenWebUI[OpenWebUI Interface]
    OpenWebUI --> Ollama[Ollama LLM Engine]
    OpenWebUI --> EdgeTTS[Edge-TTS German]
    OpenWebUI --> Tika[Apache Tika]
    Ollama --> GPU[AMD ROCm GPU Acceleration]
    
    subgraph "AI Services Network"
        OpenWebUI
        Ollama
        EdgeTTS
        Tika
    end
    
    Prometheus[Prometheus] -.-> OpenWebUI
    Prometheus -.-> Ollama
    Prometheus -.-> EdgeTTS
```

#### Performance Optimization:
- **GPU Acceleration**: AMD ROCm support with dedicated GPU memory allocation
- **Memory Management**: 8GB+ VRAM allocation for large language models
- **Model Persistence**: OLLAMA_KEEP_ALIVE=-1 prevents costly model reloading
- **Flash Attention**: Optimized attention mechanisms for 2x inference speed
- **Health Monitoring**: Comprehensive health checks and metrics collection

#### Model Management:
```bash
# Pull and run state-of-the-art models
docker exec -it ollama ollama pull llama3:70b
docker exec -it ollama ollama pull mistral:8x22b
docker exec -it ollama ollama pull codellama:34b

# Monitor model performance
docker exec -it ollama ollama ps
docker logs ollama --tail=50

# API access for integration
curl http://localhost:11434/api/generate -d '{
  "model": "llama3",
  "prompt": "Explain DevOps best practices",
  "stream": false
}'
```

### Quick AI Stack Deployment

```bash
# Start AI services with GPU support
cd ai-stack
docker-compose up -d

# Verify GPU acceleration
docker exec -it ollama ollama run llama3 "Hello" --verbose

# Access interfaces:
# OpenWebUI: https://ai.your-domain.com
# Ollama API: http://localhost:11434
# Metrics: http://localhost:9090 (Prometheus)
```

## 🚀 Quick Start

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+
- 8GB+ RAM recommended
- 100GB+ storage

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/psimaker/homelab.git
   cd homelab
   ```

2. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. **Start the infrastructure**
   ```bash
   # Start all services
   docker-compose up -d
   
   # Or start specific stacks
   docker-compose -f ai-stack.yml up -d
   docker-compose -f media-stack.yml up -d
   ```

### Access Points

- **Portainer**: http://localhost:9000
- **Nginx Proxy Manager**: http://localhost:81
- **Immich**: http://immich.your-domain.com
- **Nextcloud**: http://nextcloud.your-domain.com
- **OpenWebUI**: http://ai.your-domain.com

## 📁 Project Structure

```
homelab/
├── ai-stack/                 # AI & Machine Learning services
│   ├── ollama/
│   ├── openwebui/
│   └── docker-compose.yml
├── media-stack/              # Media services
│   ├── immich/
│   ├── plex/
│   └── docker-compose.yml
├── automation-stack/         # Automation tools
│   ├── n8n/
│   ├── paperless/
│   └── docker-compose.yml
├── monitoring-stack/         # Monitoring & management
│   ├── portainer/
│   ├── prometheus/
│   └── docker-compose.yml
├── .env.example              # Environment template
├── docker-compose.yml        # Main composition
└── README.md
```

## 🔧 Configuration

### Environment Variables
Key environment variables to configure:

```bash
# Docker user/group IDs
PUID=1000
PGID=1000

# Timezone
TZ=Europe/Zurich

# Database credentials
MYSQL_ROOT_PASSWORD=secure_password
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=db_password

# Domain configuration
DOMAIN=your-domain.com
```

### Network Setup
The infrastructure uses multiple Docker networks for security isolation:
- **Internal networks** for database and backend services
- **External networks** for public-facing services
- **VPN network** for secure external access

## 📊 Monitoring & Logging

- **Prometheus** for metrics collection
- **Portainer** for container monitoring
- **Docker logs** with log rotation
- **Health checks** for all critical services

## 🔒 Security Features

- SSL encryption via Let's Encrypt
- Network segmentation and isolation
- Regular security updates via Watchtower
- Environment variables for sensitive data
- VPN integration for secure access

## 🚦 Status

**Active Development** - This homelab is continuously improved with new services and optimizations. All core services are production-ready and stable.

## 🤝 Contributing

This project is part of my personal infrastructure, but suggestions and improvements are welcome through GitHub issues.

## 📞 Contact

- **GitHub**: [psimaker](https://github.com/psimaker)
- **LinkedIn**: https://www.linkedin.com/in/umut-erdem
- **Email**: umut.erdem@protonmail.com

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

*Built with ❤️ using Docker.*
