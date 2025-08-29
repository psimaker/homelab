# 🚀 GitHub Repository Deployment Guide

This guide provides complete instructions for deploying your Homelab project to GitHub with full automation.

## 📋 Prerequisites

### Required Tools
- **GitHub CLI (gh)**: For repository management
- **Git**: Version control system
- **Docker**: For local testing (optional)
- **GitHub Account**: With SSH key configured

### Installation Commands

```bash
# Install GitHub CLI (Ubuntu/Debian)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Install GitHub CLI (macOS)
brew install gh

# Install GitHub CLI (Windows)
winget install --id GitHub.cli
```

## 🔐 GitHub Authentication

```bash
# Authenticate with GitHub CLI
gh auth login

# Choose:
# 1. GitHub.com
# 2. HTTPS protocol
# 3. Yes for authentication via browser
# 4. Default settings for git operations
```

## 🎯 Automated Repository Setup

### Option 1: Automated Script (Recommended)
```bash
# Make the script executable
chmod +x setup-github-repo.sh

# Run the setup script
./setup-github-repo.sh
```

### Option 2: Manual Setup
```bash
# Create repository
gh repo create homelab \
  --description "A comprehensive Docker-based home laboratory infrastructure showcasing modern DevOps practices and AI integration" \
  --public \
  --confirm

# Initialize and push code
git init
git branch -M main
git remote add origin https://github.com/psimaker/homelab.git
git add .
git commit -m "feat: Initial commit - Homelab infrastructure with Docker, AI integration, and automated workflows"
git push -u origin main
```

## 🔧 Repository Configuration

### Set Repository Topics
```bash
gh repo edit psimaker/homelab --add-topic \
  "devops,docker,kubernetes,homelab,selfhosted,ai-ml,monitoring,automation,infrastructure-as-code"
```

### Enable Features
```bash
gh repo edit psimaker/homelab \
  --enable-issues \
  --enable-projects \
  --enable-wiki \
  --enable-discussions \
  --delete-branch-on-merge
```

## 🔐 GitHub Secrets Setup

For full automation, set these secrets in your repository:

1. Go to: `https://github.com/psimaker/homelab/settings/secrets/actions`
2. Add the following secrets:

### Required Secrets
- **GH_TOKEN**: GitHub Personal Access Token with `repo` permissions
- **DOCKERHUB_USERNAME**: Your Docker Hub username
- **DOCKERHUB_PASSWORD**: Your Docker Hub password/access token

### Creating GitHub PAT
1. Visit: `https://github.com/settings/tokens`
2. Click "Generate new token"
3. Select these permissions:
   - `repo` (all)
   - `workflow`
   - `write:packages`
   - `read:packages`
4. Generate token and copy it

## 🤖 Automation Features

### What's Automated:
- **CI/CD**: Automatic testing on every push
- **Security Scanning**: Weekly vulnerability checks
- **Dependency Updates**: Automated Docker image updates
- **Sync**: Automatic synchronization between repositories
- **Notifications**: Slack/email alerts for critical issues

### Workflow Overview:
1. **Push to main** → Automatic sync to GitHub
2. **Weekly schedule** → Security scanning + dependency checks
3. **Daily schedule** → Critical security updates
4. **Dependabot** → Automated dependency PRs

## 📊 Monitoring and Analytics

### GitHub Insights to Monitor:
- **Traffic**: Repository views and clones
- **Contributors**: Commit activity
- **Community**: Stars, forks, and issues
- **Workflows**: CI/CD success rates

### Setting Up Monitoring:
```bash
# Enable GitHub insights
gh api \
  --method PUT \
  -H "Accept: application/vnd.github.v3+json" \
  /repos/psimaker/homelab/actions/permissions \
  -f enabled=true \
  -f allowed_actions='all'
```

## 🎨 Profile Optimization

### Pinning Repositories
1. Go to your GitHub profile: `https://github.com/psimaker`
2. Scroll to "Pinned repositories"
3. Click "Customize your pins"
4. Select: `homelab`, `loogi`, `LOOGI.ch`

### Profile README
1. Create repository: `psimaker/psimaker`
2. Copy content from `PROFILE_README.md` to `README.md`
3. Push to main branch

## 🚀 Production Deployment Checklist

- [ ] ✅ Repository created and configured
- [ ] ✅ GitHub Secrets set up
- [ ] ✅ GitHub Actions enabled
- [ ] ✅ Repository topics added
- [ ] ✅ Initial code pushed
- [ ] ✅ Profile README updated
- [ ] ✅ Repositories pinned
- [ ] ✅ DNS domains configured (if applicable)
- [ ] ✅ SSL certificates generated
- [ ] ✅ Monitoring configured

## 📈 Performance Optimization

### Repository Settings:
```bash
# Enable automated security fixes
gh api \
  --method PUT \
  -H "Accept: application/vnd.github.v3+json" \
  /repos/psimaker/homelab/automated-security-fixes \
  -f enabled=true

# Enable vulnerability alerts
gh api \
  --method PUT \
  -H "Accept: application/vnd.github.v3+json" \
  /repos/psimaker/homelab/vulnerability-alerts \
  -f enabled=true
```

## 🆘 Troubleshooting

### Common Issues:

1. **Authentication Errors**
   ```bash
   gh auth logout
   gh auth login
   ```

2. **Permission Denied**
   ```bash
   chmod 600 ~/.ssh/id_rsa
   ssh-add ~/.ssh/id_rsa
   ```

3. **Workflow Not Running**
   - Check GitHub Secrets are set
   - Verify Actions are enabled in repository settings

4. **Dependabot Not Working**
   - Check `.github/dependabot.yml` syntax
   - Verify registry credentials

## 📞 Support

### GitHub Documentation:
- [GitHub CLI Documentation](https://cli.github.com/)
- [GitHub Actions Guide](https://docs.github.com/en/actions)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)

### Getting Help:
1. Check workflow logs in GitHub Actions tab
2. Review repository settings
3. Consult GitHub documentation
4. Create issue in repository for support

---

**🎉 Congratulations!** Your Homelab project is now ready for production deployment and will impress any DevOps/SRE hiring manager with its professional setup and automation capabilities.