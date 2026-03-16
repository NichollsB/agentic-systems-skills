#!/usr/bin/env bash
# Install agentic-systems-skills into a project's .claude/skills/ directory.
# Usage: ./install.sh [target-project-dir]
# If no target is given, installs into the current directory.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.}"
SKILLS_DIR="$TARGET/.claude/skills"

mkdir -p "$SKILLS_DIR"

echo "Installing agentic-systems-skills into $SKILLS_DIR"

# Root collection skill
ln -sfn "$REPO_DIR" "$SKILLS_DIR/agentic-systems"

# Sub-skills
for skill in agentic-architecture langgraph-fundamentals reflection-and-validation inter-agent-communication guardrails-and-security memory-and-persistence model-selection litellm-configuration project-setup deployment-and-versioning langfuse-integration agent-debugging agent-harness-design; do
  ln -sfn "$REPO_DIR/skills/$skill" "$SKILLS_DIR/$skill"
done

# Vendor: context engineering (https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering)
for skill in context-fundamentals context-degradation context-compression context-optimization filesystem-context multi-agent-patterns memory-systems tool-design evaluation advanced-evaluation project-development; do
  ln -sfn "$REPO_DIR/vendor/context-engineering/skills/$skill" "$SKILLS_DIR/$skill"
done

# Vendor: Langfuse (https://github.com/langfuse/skills)
ln -sfn "$REPO_DIR/vendor/langfuse-skills/skills/langfuse" "$SKILLS_DIR/langfuse"

# Vendor: Anthropic skill-creator (https://github.com/anthropics/skills)
ln -sfn "$REPO_DIR/vendor/anthropic-skills/skills/skill-creator" "$SKILLS_DIR/skill-creator"

echo "Installed $(ls -1 "$SKILLS_DIR" | wc -l) skills into $SKILLS_DIR"
