#!/bin/bash

# GitHub Repository Setup Script for Homelab Project
# This script automates the creation and configuration of the GitHub repository

set -e  # Exit on error

# Configuration
REPO_NAME="homelab"
REPO_DESCRIPTION="A comprehensive Docker-based home laboratory infrastructure showcasing modern DevOps practices and AI integration"
GITHUB_USER="psimaker"
TARGET_DIR="/data"

echo "🚀 Setting up GitHub repository for Homelab project"

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Please install it first:"
    echo "   https://github.com/cli/cli#installation"
    exit 1
fi

# Check if user is authenticated with GitHub
if ! gh auth status &> /dev/null; then
    echo "🔐 Please authenticate with GitHub CLI:"
    gh auth login
fi

# Delete existing repository if it exists
echo "🗑️ Checking for existing repository..."
if gh repo view "$GITHUB_USER/$REPO_NAME" &> /dev/null; then
    echo "⚠️ Repository exists - requesting delete permissions..."
    # Request the required scope first
    gh auth refresh -h github.com -s delete_repo
    
    echo "🗑️ Deleting existing repository..."
    gh repo delete "$GITHUB_USER/$REPO_NAME" --yes
fi

# Create the repository
echo "📦 Creating repository $REPO_NAME..."
gh repo create "$REPO_NAME" \
    --description "$REPO_DESCRIPTION" \
    --public \
    --confirm

# Initialize git if not already initialized
if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "📝 Initializing git repository..."
    cd "$TARGET_DIR"
    git init
    git branch -M main
fi

# Add remote origin
echo "🔗 Adding remote origin..."
cd "$TARGET_DIR"
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"

# Create initial commit
echo "💾 Creating initial commit..."
git add .
git commit -m "feat: Initial commit - Homelab infrastructure with Docker, AI integration, and automated workflows

- Comprehensive Docker Compose setup with 40+ services
- AI/ML stack with Ollama and OpenWebUI
- Automated CI/CD workflows and security scanning
- Professional documentation and project structure
- Ready for production deployment"

# Push to GitHub
echo "📤 Pushing to GitHub..."
git push -u origin main

# Configure repository settings
echo "⚙️ Configuring repository settings..."
gh repo edit "$GITHUB_USER/$REPO_NAME" \
    --enable-issues \
    --enable-projects \
    --enable-wiki \
    --enable-discussions \
    --delete-branch-on-merge

# Set up repository topics
echo "🏷️ Setting repository topics..."
gh repo edit "$GITHUB_USER/$REPO_NAME" --add-topic "devops,docker,kubernetes,homelab,selfhosted,ai-ml,monitoring,automation,infrastructure-as-code"

# Enable GitHub Actions
echo "🔧 Enabling GitHub Actions..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github.v3+json" \
  /repos/$GITHUB_USER/$REPO_NAME/actions/permissions \
  -f enabled=true \
  -f allowed_actions='all'

# Create GitHub Secrets instructions
echo "🔐 GitHub Secrets required for full automation:"
echo ""
echo "Please set the following secrets in your repository:"
echo "1. GH_TOKEN: GitHub Personal Access Token with repo permissions"
echo "2. DOCKERHUB_USERNAME: Your Docker Hub username"
echo "3. DOCKERHUB_PASSWORD: Your Docker Hub password/access token"
echo ""
echo "To set secrets, go to:"
echo "https://github.com/$GITHUB_USER/$REPO_NAME/settings/secrets/actions"
echo ""

# Create issues for initial setup
echo "📋 Creating initial issues for project setup..."
gh issue create \
  --title "🚀 Initial Project Setup and Documentation" \
  --body "## Initial Setup Checklist

- [ ] Review and customize .env.example
- [ ] Set up GitHub Secrets for automation
- [ ] Configure domain names in reverse proxy
- [ ] Test AI stack deployment (Ollama + OpenWebUI)
- [ ] Verify monitoring stack (Prometheus + Grafana)
- [ ] Set up backup strategy for critical data
- [ ] Document network architecture and security setup

## Priority Tasks:
1. **Secrets Setup**: Configure all required environment variables
2. **DNS Configuration**: Set up proper domain names
3. **SSL Certificates**: Enable HTTPS via Let's Encrypt
4. **Monitoring**: Verify all services are being monitored
5. **Backups**: Implement regular backup procedures" \
  --label "documentation,enhancement"

gh issue create \
  --title "🤖 AI Stack Optimization and Model Management" \
  --body "## AI Infrastructure Optimization

### Current AI Stack:
- **Ollama**: Local LLM inference with GPU acceleration
- **OpenWebUI**: Professional web interface
- **Edge-TTS**: Text-to-speech with German support
- **Apache Tika**: Document analysis and processing

### Optimization Tasks:
- [ ] Benchmark different LLM models for performance
- [ ] Implement model versioning and rollback strategy
- [ ] Set up GPU monitoring and utilization alerts
- [ ] Create model training pipeline documentation
- [ ] Implement AI service health checks
- [ ] Set up prompt engineering guidelines

### Model Recommendations:
1. **Llama 3 70B** - General purpose
2. **Mistral 8x22B** - Multilingual capabilities  
3. **CodeLlama 34B** - Development tasks
4. **Whisper** - Speech-to-text (future enhancement)" \
  --label "ai-ml,enhancement"

echo "✅ GitHub repository setup completed!"
echo ""
echo "📊 Next steps:"
echo "1. Visit your repository: https://github.com/$GITHUB_USER/$REPO_NAME"
echo "2. Set up GitHub Secrets as shown above"
echo "3. Star your repository to increase visibility"
echo "4. Pin the repository to your GitHub profile"
echo "5. Share on LinkedIn and other professional networks"
echo ""
echo "🎉 Your Homelab project is now ready for DevOps/SRE job applications!"