#!/bin/bash
# Save as: fix_structure.sh
# Run: chmod +x fix_structure.sh && ./fix_structure.sh

set -e

echo "🧹 Cleaning up project structure..."

cd /home/prometheus/coding/finance/project-chronos

# ============================================================================
# 1. Move scripts to root level
# ============================================================================
echo "📁 Moving scripts to root level..."

# Create root-level scripts directory
mkdir -p scripts

# Move daily_update.sh if it exists in src/scripts
if [ -f "src/scripts/daily_update.sh" ]; then
    mv src/scripts/daily_update.sh scripts/
    echo "  ✅ Moved daily_update.sh to scripts/"
fi

# Keep Python scripts in src/scripts (they're part of the package)
echo "  ℹ️  Python ingestion scripts remain in src/scripts/ (correct location)"

# ============================================================================
# 2. Remove mystery src directory inside ingestion
# ============================================================================
echo "🗑️  Removing errant directories..."

if [ -d "src/chronos/ingestion/src" ]; then
    rm -rf src/chronos/ingestion/src
    echo "  ✅ Removed src/chronos/ingestion/src/"
fi

# ============================================================================
# 3. Clean up __pycache__ directories
# ============================================================================
echo "🧹 Removing __pycache__ directories..."

find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type f -name "*.pyo" -delete 2>/dev/null || true

echo "  ✅ Cleaned up Python cache files"

# ============================================================================
# 4. Create missing directories
# ============================================================================
echo "📁 Creating missing directories..."

mkdir -p .devcontainer
mkdir -p logs
mkdir -p tests/integration
mkdir -p tests/unit
mkdir -p database/migrations
mkdir -p database/seeds

# Add __init__.py to test directories
touch tests/__init__.py
touch tests/integration/__init__.py
touch tests/unit/__init__.py

echo "  ✅ Created standard directory structure"

# ============================================================================
# 5. Update .gitignore
# ============================================================================
echo "📝 Updating .gitignore..."

cat > .gitignore << 'EOF'
# ============================================================================
# Project Chronos: Git Ignore Rules
# ============================================================================

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
.pytest_cache/
.coverage
htmlcov/
.tox/
.mypy_cache/
.dmypy.json
dmypy.json

# Virtual Environment
venv/
env/
ENV/
.venv/

# Environment Variables
.env
.env.local
.env.*.local

# IDEs
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store

# Database
*.db
*.sqlite
*.sqlite3
pgdata/

# Logs
logs/
*.log

# OS
Thumbs.db

# Project-specific
database/backups/

# Jupyter
.ipynb_checkpoints/

# Docker
.dockerignore
EOF

echo "  ✅ Updated .gitignore"

# ============================================================================
# 6. Move test_connection.py to correct location
# ============================================================================
echo "📦 Organizing test files..."

if [ -f "tests/test_connection.py" ]; then
    mv tests/test_connection.py tests/unit/
    echo "  ✅ Moved test_connection.py to tests/unit/"
fi

# ============================================================================
# 7. Create placeholder files
# ============================================================================
echo "📄 Creating placeholder files..."

# .gitkeep files for empty directories
touch database/migrations/.gitkeep
touch database/seeds/.gitkeep
touch logs/.gitkeep

echo "  ✅ Created .gitkeep files"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "✅ Project structure cleanup complete!"
echo ""
echo "Structure now follows institutional best practices:"
echo "  📁 scripts/          → Operational scripts (root level)"
echo "  📁 src/scripts/      → Python CLI entry points"
echo "  📁 logs/             → Application logs (gitignored)"
echo "  📁 .devcontainer/    → VS Code Dev Container config"
echo "  📁 tests/unit/       → Unit tests"
echo "  📁 tests/integration/→ Integration tests"
echo ""
echo "Next steps:"
echo "  1. Review changes: git status"
echo "  2. Create daily_update.sh in scripts/"
echo "  3. Set up Dev Container configuration"
