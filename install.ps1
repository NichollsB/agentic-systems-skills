# Install agentic-systems-skills into a project's .claude/skills/ directory.
# Usage: .\install.ps1 [-Target <project-dir>]
# If no target is given, installs into the current directory.

param(
    [string]$Target = "."
)

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillsDir = Join-Path $Target ".claude\skills"

New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null

Write-Host "Installing agentic-systems-skills into $SkillsDir"

# Root collection skill
New-Item -ItemType Junction -Path "$SkillsDir\agentic-systems" -Target $RepoDir -Force | Out-Null

# Sub-skills
$subSkills = @("agentic-architecture","langgraph-fundamentals","reflection-and-validation","inter-agent-communication","guardrails-and-security","memory-and-persistence","model-selection","litellm-configuration","project-setup","deployment-and-versioning","langfuse-integration","agent-debugging","agent-harness-design")
foreach ($skill in $subSkills) {
    New-Item -ItemType Junction -Path "$SkillsDir\$skill" -Target "$RepoDir\skills\$skill" -Force | Out-Null
}

# Vendor: context engineering (https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering)
$ceSkills = @("context-fundamentals","context-degradation","context-compression","context-optimization","filesystem-context","multi-agent-patterns","memory-systems","tool-design","evaluation","advanced-evaluation","project-development")
foreach ($skill in $ceSkills) {
    New-Item -ItemType Junction -Path "$SkillsDir\$skill" -Target "$RepoDir\vendor\context-engineering\skills\$skill" -Force | Out-Null
}

# Vendor: Langfuse (https://github.com/langfuse/skills)
New-Item -ItemType Junction -Path "$SkillsDir\langfuse" -Target "$RepoDir\vendor\langfuse-skills\skills\langfuse" -Force | Out-Null

# Vendor: Anthropic skill-creator (https://github.com/anthropics/skills)
New-Item -ItemType Junction -Path "$SkillsDir\skill-creator" -Target "$RepoDir\vendor\anthropic-skills\skills\skill-creator" -Force | Out-Null

$count = (Get-ChildItem -Directory $SkillsDir).Count
Write-Host "Installed $count skills into $SkillsDir"
