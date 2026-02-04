#!/bin/bash

# TrustGraph Fixes - GitHub Repository Setup Script
# This script helps you create and push the trustgraph-fixes repository to GitHub

set -e

echo "=================================================="
echo "TrustGraph Fixes - GitHub Repository Setup"
echo "=================================================="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "⚠️  GitHub CLI (gh) not found. Please install it first:"
    echo "   brew install gh"
    echo ""
    echo "Then authenticate:"
    echo "   gh auth login"
    echo ""
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "⚠️  Not authenticated with GitHub. Please run:"
    echo "   gh auth login"
    echo ""
    exit 1
fi

# Get GitHub username
GITHUB_USER=$(gh api user --jq '.login')
echo "✓ Authenticated as: $GITHUB_USER"
echo ""

# Create the repository
echo "Creating repository 'trustgraph-fixes' on GitHub..."
gh repo create trustgraph-fixes \
    --public \
    --description "Fixes and improvements for TrustGraph - Pulsar serialization issue with list[list[float]] fields" \
    --source=~/ZCodeProject/trustgraph-fixes \
    --push

echo ""
echo "=================================================="
echo "✓ Repository created successfully!"
echo "=================================================="
echo ""
echo "Repository URL: https://github.com/$GITHUB_USER/trustgraph-fixes"
echo ""
echo "Quick apply fix to running container:"
echo "  docker cp ~/ZCodeProject/trustgraph-fixes/trustgraph-flow/trustgraph/storage/doc_embeddings/qdrant/write.py \\"
echo "    deploy-store-doc-embeddings-1:/usr/local/lib/python3.13/site-packages/trustgraph/storage/doc_embeddings/qdrant/write.py"
echo "  docker restart deploy-store-doc-embeddings-1"
echo ""
