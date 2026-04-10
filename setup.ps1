#Requires -Version 5.1
<#
.SYNOPSIS
    Master setup script for the OpenClaw Job Auto-Apply project.
    Installs all dependencies, builds OpenClaw from source, configures
    the browser tool for Brave Profile 6, generates project files,
    installs the skill, and starts the gateway.

.NOTES
    Run from an elevated (Administrator) PowerShell terminal.
    Ensure OPENROUTER_API_KEY is set in your environment before running.
#>

param(
    [string]$ProjectRoot = "$PSScriptRoot\job-auto-apply",
    [string]$OpenClawRepo = "https://github.com/openclaw/openclaw.git",
    [string]$BravePath = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
    [string]$BraveProfileDir = "C:\Users\$env:USERNAME\AppData\Local\BraveSoftware\Brave-Browser\User Data\Profile 6"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Colors and helpers ──────────────────────────────────────────────
function Write-Step  { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red }

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# ── Pre-flight checks ──────────────────────────────────────────────
Write-Step "Pre-flight checks"

if (-not $env:OPENROUTER_API_KEY) {
    Write-Fail "Environment variable OPENROUTER_API_KEY is not set."
    Write-Host "    Set it with:  `$env:OPENROUTER_API_KEY = 'sk-or-...'`" -ForegroundColor Yellow
    exit 1
}
Write-Ok "OPENROUTER_API_KEY detected"

if (-not (Test-Path $BravePath)) {
    Write-Fail "Brave browser not found at: $BravePath"
    exit 1
}
Write-Ok "Brave browser found at $BravePath"

if (-not (Test-Path $BraveProfileDir)) {
    Write-Warn "Brave Profile 6 directory not found at: $BraveProfileDir"
    Write-Host "    The profile will be created when Brave opens with --profile-directory=`"Profile 6`"" -ForegroundColor Yellow
}
else {
    Write-Ok "Brave Profile 6 directory exists"
}

# ── Step 1: Node.js 24+ ────────────────────────────────────────────
Write-Step "Step 1: Checking Node.js >= 24"

$needNode = $true
if (Test-Command "node") {
    $nodeVer = (node --version) -replace '^v', ''
    $nodeMajor = [int]($nodeVer.Split('.')[0])
    if ($nodeMajor -ge 24) {
        Write-Ok "Node.js v$nodeVer already installed"
        $needNode = $false
    }
    else {
        Write-Warn "Node.js v$nodeVer found but need >= 24. Installing..."
    }
}

if ($needNode) {
    Write-Host "    Installing Node.js LTS via winget..."
    winget install --id OpenJS.NodeJS --accept-source-agreements --accept-package-agreements --silent
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-Command "node")) {
        Write-Fail "Node.js installation failed. Install manually from https://nodejs.org"
        exit 1
    }
    Write-Ok "Node.js $(node --version) installed"
}

# ── Step 2: pnpm ───────────────────────────────────────────────────
Write-Step "Step 2: Checking pnpm"

if (-not (Test-Command "pnpm")) {
    Write-Host "    Installing pnpm via corepack..."
    corepack enable
    corepack prepare pnpm@latest --activate
    if (-not (Test-Command "pnpm")) {
        Write-Host "    Falling back to npm install..."
        npm install -g pnpm
    }
}
Write-Ok "pnpm $(pnpm --version) available"

# ── Step 3: Git ─────────────────────────────────────────────────────
Write-Step "Step 3: Checking Git"

if (-not (Test-Command "git")) {
    Write-Host "    Installing Git via winget..."
    winget install --id Git.Git --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-Command "git")) {
        Write-Fail "Git installation failed. Install manually from https://git-scm.com"
        exit 1
    }
}
Write-Ok "Git $(git --version) available"

# ── Step 4: Clone OpenClaw ──────────────────────────────────────────
Write-Step "Step 4: Cloning OpenClaw from source"

$openclawDir = Join-Path $PSScriptRoot "openclaw"

if (Test-Path $openclawDir) {
    Write-Warn "OpenClaw directory already exists. Pulling latest..."
    Push-Location $openclawDir
    git pull --ff-only
    Pop-Location
}
else {
    git clone --depth 1 $OpenClawRepo $openclawDir
}
Write-Ok "OpenClaw source ready at $openclawDir"

# ── Step 5: Build OpenClaw ──────────────────────────────────────────
Write-Step "Step 5: Building OpenClaw (pnpm install, ui:build, build)"

Push-Location $openclawDir
pnpm install --frozen-lockfile
Write-Ok "pnpm install complete"

# ui:build may not exist in all versions; attempt it
try {
    pnpm run ui:build 2>$null
    Write-Ok "pnpm ui:build complete"
}
catch {
    Write-Warn "ui:build not found — skipping (may be bundled in build)"
}

pnpm run build
Write-Ok "pnpm build complete"

# Make openclaw CLI available
$openclawBin = Join-Path $openclawDir "openclaw.mjs"
if (-not (Test-Command "openclaw")) {
    # Create a wrapper so openclaw is on PATH for this session
    $wrapperPath = Join-Path $openclawDir "openclaw.cmd"
    @"
@echo off
node "$openclawBin" %*
"@ | Set-Content $wrapperPath -Encoding ASCII
    $env:Path = "$openclawDir;$env:Path"
}
Pop-Location
Write-Ok "openclaw CLI accessible"

# ── Step 6: Onboard / configure OpenRouter + DeepSeek ───────────────
Write-Step "Step 6: Configuring OpenClaw (OpenRouter + DeepSeek)"

$openclawHome = Join-Path $env:USERPROFILE ".openclaw"
$openclawConfig = Join-Path $openclawHome "openclaw.json"

if (-not (Test-Path $openclawHome)) {
    New-Item -ItemType Directory -Path $openclawHome -Force | Out-Null
}

# Build the configuration JSON
# This sets OpenRouter as provider, DeepSeek as model, Brave as browser,
# and Groq as fallback provider
$configJson = @"
{
  "models": {
    "providers": {
      "openrouter": {
        "apiKey": { "source": "env", "id": "OPENROUTER_API_KEY" },
        "baseUrl": "https://openrouter.ai/api/v1",
        "models": [
          { "id": "deepseek/deepseek-chat", "displayName": "DeepSeek Chat" },
          { "id": "deepseek/deepseek-reasoner", "displayName": "DeepSeek Reasoner" }
        ]
      },
      "groq": {
        "apiKey": { "source": "env", "id": "GROQ_API_KEY" },
        "baseUrl": "https://api.groq.com/openai/v1",
        "models": [
          { "id": "llama-3.3-70b-versatile", "displayName": "Llama 3.3 70B (Groq)" }
        ]
      }
    },
    "chat": "openrouter/deepseek/deepseek-chat",
    "thinking": "openrouter/deepseek/deepseek-reasoner",
    "fallbackProviders": ["groq"]
  },
  "browser": {
    "enabled": true,
    "headless": false,
    "defaultProfile": "jobsearch",
    "executablePath": "C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe",
    "profiles": {
      "jobsearch": {
        "driver": "existing-session",
        "attachOnly": true,
        "userDataDir": "C:\\Users\\$env:USERNAME\\AppData\\Local\\BraveSoftware\\Brave-Browser\\User Data",
        "color": "#FB542B"
      }
    }
  },
  "plugins": {
    "allow": ["browser"]
  },
  "gateway": {
    "port": 18789
  },
  "agents": {
    "defaults": {
      "skills": ["job-apply"]
    }
  }
}
"@

# Write config — but preserve existing if present
if (Test-Path $openclawConfig) {
    $backupPath = "$openclawConfig.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $openclawConfig $backupPath
    Write-Warn "Existing config backed up to $backupPath"
}

$configJson | Set-Content $openclawConfig -Encoding UTF8
Write-Ok "openclaw.json written to $openclawHome"

# ── Step 7: Try running onboard with daemon install ─────────────────
Write-Step "Step 7: Installing OpenClaw daemon"

try {
    openclaw onboard --install-daemon 2>$null
    Write-Ok "Daemon installed via onboard"
}
catch {
    Write-Warn "openclaw onboard --install-daemon had issues — config was written manually"
    Write-Host "    You may need to register the gateway as a Windows service manually." -ForegroundColor Yellow
}

# ── Step 8: Create project folder structure ─────────────────────────
Write-Step "Step 8: Creating project folder structure"

$folders = @(
    $ProjectRoot,
    (Join-Path $ProjectRoot "skills"),
    (Join-Path $ProjectRoot "logs"),
    (Join-Path $ProjectRoot "screenshots"),
    (Join-Path $ProjectRoot "resumes")
)

foreach ($dir in $folders) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Initialize empty log
$logFile = Join-Path $ProjectRoot "logs\applications_log.json"
if (-not (Test-Path $logFile)) {
    "[]" | Set-Content $logFile -Encoding UTF8
}

Write-Ok "Project structure created at $ProjectRoot"

# ── Step 9: Generate config.yaml ────────────────────────────────────
Write-Step "Step 9: Generating config.yaml template"

$configYaml = @"
# ============================================================
# JOB AUTO-APPLY — Candidate Configuration
# ============================================================
# Fill in ALL fields below. The agent reads this file for every
# application. Edit and save — changes take effect on next run.
# ============================================================

candidate:
  full_name: ""
  email: ""
  phone: ""
  linkedin_url: ""
  portfolio_url: ""
  github_url: ""
  location: ""
  willing_to_relocate: true
  work_authorization: ""
  requires_sponsorship: false
  years_of_experience: 0

resume:
  default_path: "resumes/resume_default.pdf"
  sde_path: "resumes/resume_sde.pdf"
  ai_ml_path: "resumes/resume_ai_ml.pdf"
  data_path: "resumes/resume_data.pdf"

education:
  - degree: ""
    field: ""
    university: ""
    graduation_year: ""
    gpa: ""

experience:
  - title: ""
    company: ""
    duration: ""
    description: ""

skills:
  languages: []
  frameworks: []
  tools: []
  domains: []

job_preferences:
  target_titles:
    - "Software Engineer"
    - "Software Development Engineer"
    - "SDE"
    - "Data Engineer"
    - "Data Scientist"
    - "ML Engineer"
    - "Machine Learning Engineer"
    - "AI Engineer"
    - "Data Analyst"
  experience_level: "entry-level,1-2 years"
  job_type: "full-time"
  preferred_locations: []
  remote_ok: true
  salary_minimum: 0

screening_answers:
  why_interested_template: ""
  strengths: ""
  cover_letter_base: ""
  additional_qa:
    - question_pattern: ""
      answer: ""

# Set to true for fully autonomous applications.
# Set to false to queue matches on the dashboard for your approval.
auto_mode: false

# Dry-run mode: agent does everything EXCEPT click final Submit.
dry_run: true

# Safety limits
max_applications_per_company_per_day: 10
delay_between_applications_seconds_min: 30
delay_between_applications_seconds_max: 60
"@

$configYamlPath = Join-Path $ProjectRoot "config.yaml"
$configYaml | Set-Content $configYamlPath -Encoding UTF8
Write-Ok "config.yaml generated (fill in your details!)"

# ── Step 10: Generate companies.yaml ────────────────────────────────
Write-Step "Step 10: Generating companies.yaml"

$companiesYaml = @"
# ============================================================
# TARGET COMPANIES — Hardcoded career page URLs
# ============================================================
# These are the ONLY sites the agent will visit.
# Do NOT add or remove entries unless you update the skill too.
# ============================================================

companies:
  - name: "Adobe"
    careers_url: "https://careers.adobe.com/us/en"

  - name: "Apple"
    careers_url: "https://jobs.apple.com"

  - name: "McKinsey"
    careers_url: "https://www.mckinsey.com/careers/search-jobs"

  - name: "Google"
    careers_url: "https://www.google.com/about/careers/applications/jobs/results"

  - name: "Meta"
    careers_url: "https://www.metacareers.com/jobs"

  - name: "Intuit"
    careers_url: "https://jobs.intuit.com"

  - name: "JP Morgan"
    careers_url: "https://careers.jpmorgan.com/global/en/jobs"

  - name: "LinkedIn"
    careers_url: "https://careers.linkedin.com"

  - name: "Morgan Stanley"
    careers_url: "https://ms.taleo.net/careersection/2/jobsearch.ftl"

  - name: "Microsoft"
    careers_url: "https://careers.microsoft.com/global/en/search"

  - name: "Netflix"
    careers_url: "https://jobs.netflix.com"

  - name: "Anthropic"
    careers_url: "https://www.anthropic.com/careers"

  - name: "Atlassian"
    careers_url: "https://www.atlassian.com/company/careers/all-jobs"
"@

$companiesYamlPath = Join-Path $ProjectRoot "companies.yaml"
$companiesYaml | Set-Content $companiesYamlPath -Encoding UTF8
Write-Ok "companies.yaml generated with 13 target companies"

# ── Step 11: Generate SKILL.md ──────────────────────────────────────
Write-Step "Step 11: Generating job-apply skill (SKILL.md)"

$skillDir = Join-Path $ProjectRoot "skills\job-apply"
if (-not (Test-Path $skillDir)) {
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
}

# The SKILL.md content is written below as a here-string.
# It follows the AgentSkills-compatible format with YAML frontmatter.
$skillMd = @'
---
name: job-apply
description: Autonomous job application agent. Searches 13 target company career sites, finds matching roles based on candidate config, and applies to each one using the browser tool and LLM reasoning. No hardcoded selectors — the agent interprets every page visually and adaptively.
metadata: {"openclaw":{"requires":{"config":["browser.enabled"]},"os":["win32","darwin","linux"]}}
---

# Job Auto-Apply Skill

You are an autonomous job application agent. Your mission is to apply to relevant jobs at specific companies on behalf of the candidate.

## Core Principles

1. **You NEVER type passwords or handle login flows.** The Brave browser profile is already logged into all target sites.
2. **You NEVER visit any URL not listed in companies.yaml.** Only the 13 hardcoded career page URLs.
3. **You NEVER use hardcoded CSS selectors or XPath.** You interpret every page by reading the browser snapshot and deciding what to do.
4. **You read config.yaml for ALL candidate information.** Never invent or guess personal details.
5. **You log every action to logs/applications_log.json.**

## Workflow Overview

When triggered, execute the following for each company in companies.yaml:

### Phase 1: Search & Discover

1. Read `{baseDir}/../config.yaml` for candidate preferences (target_titles, experience_level, preferred_locations, remote_ok).
2. Read `{baseDir}/../companies.yaml` for the list of target companies and their career URLs.
3. For each company:
   a. Open the company's career page URL using the browser tool with `profile="jobsearch"`.
   b. Take a snapshot of the page to understand its layout.
   c. Use whatever search bar, filter dropdowns, or keyword fields exist on that page to search for roles matching the candidate's target_titles.
   d. If filters for experience level, location, or job type exist, apply them.
   e. Scroll through and collect all matching job listings.

### Phase 2: Evaluate Relevance

For each discovered job listing:
1. Open the job detail page.
2. Read the job description via browser snapshot.
3. Decide if the role matches the candidate's profile by checking:
   - Title matches or is closely related to one of job_preferences.target_titles
   - Experience level is appropriate (entry-level to 1-2 years unless config says otherwise)
   - Location is acceptable (check preferred_locations and remote_ok)
4. If the role does NOT match, log it as "skipped" with a reason and move on.
5. If the role matches, proceed to Phase 3.

### Phase 3: Apply

Check the `auto_mode` and `dry_run` settings from config.yaml:
- If `auto_mode` is false: log the match as "needs_review" and continue to next listing. The user will approve from the dashboard.
- If `auto_mode` is true: proceed with application.

For each application:
1. Click the "Apply" button (or equivalent) on the job listing page.
2. The application process will vary per site. Use browser snapshots to read each form page.
3. Fill in ALL form fields using data from config.yaml:
   - Personal info: candidate.full_name, candidate.email, candidate.phone, etc.
   - Education: education entries
   - Experience: experience entries
   - Links: candidate.linkedin_url, candidate.github_url, candidate.portfolio_url
4. Upload the appropriate resume:
   - For SDE/Software roles: use resume.sde_path
   - For AI/ML roles: use resume.ai_ml_path
   - For Data roles: use resume.data_path
   - For anything else: use resume.default_path
   - Use the browser upload tool to select the file.
5. Answer screening questions:
   - First check screening_answers.additional_qa for a matching question_pattern.
   - If no match, use screening_answers templates (why_interested_template, strengths).
   - If the question is novel, generate an appropriate answer using the candidate's profile as context.
   - For complex questions requiring deeper reasoning, use DeepSeek Reasoner.
6. If a cover letter field exists:
   - Use screening_answers.cover_letter_base as a starting point.
   - Customize it for this specific role and company.
7. Navigate through multi-step forms by clicking "Next", "Continue", or equivalent buttons.
8. Before final submission:
   - If `dry_run` is true: DO NOT click Submit. Log as "dry_run" and take a screenshot.
   - If `dry_run` is false: Click Submit / Send Application.
9. After submission, take a screenshot of the confirmation page and save it to `{baseDir}/../screenshots/`.

### Phase 4: Logging

After each application attempt, append an entry to `{baseDir}/../logs/applications_log.json`:

```json
{
  "timestamp": "ISO-8601 timestamp",
  "company": "Company Name",
  "job_title": "Job Title",
  "job_url": "https://...",
  "resume_used": "path/to/resume.pdf",
  "status": "applied|skipped|failed|needs_review|dry_run",
  "reason": "only if skipped or failed",
  "screening_questions": [
    {
      "question": "Why are you interested?",
      "answer": "Generated answer..."
    }
  ],
  "screenshot": "screenshots/Company_JobTitle_timestamp.png"
}
