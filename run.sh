
#!/usr/bin/env bash
###############################################################################
# setup.sh — Master setup script for job-auto-apply (OpenClaw + ClawdBot)
# Run in Windows Git Bash:  bash setup.sh
# Prereqs: Git Bash installed, OPENROUTER_API_KEY env var set
###############################################################################
set -euo pipefail

# ─── Color helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ─── Resolve Windows username for Brave profile path ────────────────────────
WIN_USER="${USERNAME:-$USER}"
BRAVE_EXE="/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
BRAVE_USERDATA="C:\\Users\\${WIN_USER}\\AppData\\Local\\BraveSoftware\\Brave-Browser\\User Data"
BRAVE_PROFILE="Profile 6"
BRAVE_USERDATA_UNIX="/c/Users/${WIN_USER}/AppData/Local/BraveSoftware/Brave-Browser/User Data"

# ─── Project root ────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)/job-auto-apply"
OPENCLAW_DIR="$(pwd)/openclaw"
OPENCLAW_HOME="${HOME}/.openclaw"
WORKSPACE_DIR="${OPENCLAW_HOME}/workspace"
SKILLS_GLOBAL="${OPENCLAW_HOME}/workspace/skills"

info "=============================================="
info "  Job Auto-Apply — OpenClaw Project Setup"
info "=============================================="
echo ""

# ─── Preflight: check OPENROUTER_API_KEY ─────────────────────────────────────
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    fail "OPENROUTER_API_KEY is not set. Export it first:\n  export OPENROUTER_API_KEY=\"sk-or-...\""
fi
ok "OPENROUTER_API_KEY detected"

# ─── Preflight: check Brave exists ──────────────────────────────────────────
if [[ -f "$BRAVE_EXE" ]]; then
    ok "Brave browser found at: $BRAVE_EXE"
else
    warn "Brave browser not found at expected path. You may need to adjust BRAVE_EXE."
fi

###############################################################################
# 1. Install Node.js 24+ if missing
###############################################################################
info "Checking Node.js..."
if command -v node &>/dev/null; then
    NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
    if (( NODE_VER >= 22 )); then
        ok "Node.js $(node -v) found (meets minimum v22+)"
    else
        warn "Node.js $(node -v) is below v22. Installing Node 24 via winget..."
        powershell.exe -Command "winget install OpenJS.NodeJS --version 24.0.0 --accept-source-agreements --accept-package-agreements" || \
            fail "Could not install Node.js via winget. Install Node 24+ manually from https://nodejs.org"
    fi
else
    info "Node.js not found. Installing via winget..."
    powershell.exe -Command "winget install OpenJS.NodeJS --accept-source-agreements --accept-package-agreements" || \
        fail "Could not install Node.js. Install manually from https://nodejs.org"
fi

# Refresh PATH for this session (Git Bash won't pick up winget installs automatically)
export PATH="/c/Program Files/nodejs:$PATH"

###############################################################################
# 2. Install pnpm if missing
###############################################################################
info "Checking pnpm..."
if command -v pnpm &>/dev/null; then
    ok "pnpm $(pnpm -v) found"
else
    info "Installing pnpm via npm..."
    npm install -g pnpm@latest
    ok "pnpm installed"
fi

###############################################################################
# 3. Install Git if missing (should exist since we're in Git Bash)
###############################################################################
info "Checking Git..."
if command -v git &>/dev/null; then
    ok "Git $(git --version | awk '{print $3}') found"
else
    info "Installing Git via winget..."
    powershell.exe -Command "winget install Git.Git --accept-source-agreements --accept-package-agreements" || \
        fail "Could not install Git. Install manually."
fi

###############################################################################
# 4. Clone and build OpenClaw from source
###############################################################################
info "Setting up OpenClaw from source..."
if [[ -d "$OPENCLAW_DIR" ]]; then
    warn "OpenClaw directory already exists at $OPENCLAW_DIR — pulling latest..."
    cd "$OPENCLAW_DIR"
    git pull origin main || warn "Could not pull latest (may be on a release branch)"
else
    info "Cloning OpenClaw from GitHub..."
    git clone https://github.com/openclaw/openclaw.git "$OPENCLAW_DIR"
    cd "$OPENCLAW_DIR"
fi

info "Installing OpenClaw dependencies (pnpm install)..."
pnpm install

info "Building UI (pnpm ui:build)..."
pnpm ui:build

info "Building OpenClaw (pnpm build)..."
pnpm build

info "Linking OpenClaw globally..."
pnpm link --global
ok "OpenClaw built and linked globally"

# Return to original directory
cd "$(dirname "$PROJECT_DIR")"

###############################################################################
# 5. Run OpenClaw onboarding with OpenRouter + DeepSeek
###############################################################################
info "Running OpenClaw onboarding..."
openclaw onboard --install-daemon \
    --auth-choice apiKey \
    --token-provider openrouter \
    --token "$OPENROUTER_API_KEY" \
    || warn "Onboarding may need manual completion — run 'openclaw onboard' interactively if needed"

ok "OpenClaw onboarding complete"

###############################################################################
# 6. Configure openclaw.json — model, browser, Brave profile
###############################################################################
info "Configuring OpenClaw (openclaw.json)..."

# Set primary model to DeepSeek via OpenRouter with Groq fallback
openclaw config set agents.defaults.model.primary "openrouter/deepseek/deepseek-chat"

# Add fallback models (Groq for when OpenRouter limits are hit)
# Note: openclaw config set for arrays may need direct JSON editing
# We'll write the full config via a node script for reliability

OPENCLAW_JSON="${OPENCLAW_HOME}/openclaw.json"

# Use node to safely merge our config into existing openclaw.json
node -e "
const fs = require('fs');
const path = '${OPENCLAW_JSON//\\/\\\\}';
let config = {};
try { config = JSON.parse(fs.readFileSync(path, 'utf8').replace(/\/\/.*$/gm,'').replace(/\/\*[\s\S]*?\*\//g,'')); } catch(e) { config = {}; }

// Env vars
if (!config.env) config.env = {};
config.env.OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY || '';

// Agent defaults
if (!config.agents) config.agents = {};
if (!config.agents.defaults) config.agents.defaults = {};
config.agents.defaults.model = {
    primary: 'openrouter/deepseek/deepseek-chat',
    fallbacks: [
        'openrouter/deepseek/deepseek-reasoner',
        'openrouter/meta-llama/llama-4-maverick',
    ]
};
config.agents.defaults.models = {
    'openrouter/deepseek/deepseek-chat': {},
    'openrouter/deepseek/deepseek-reasoner': {},
    'openrouter/meta-llama/llama-4-maverick': {},
};

// Browser config — Brave Profile 6 \"jobsearch\"
if (!config.browser) config.browser = {};
config.browser.enabled = true;
config.browser.executablePath = 'C:\\\\Program Files\\\\BraveSoftware\\\\Brave-Browser\\\\Application\\\\brave.exe';
config.browser.defaultProfile = 'jobsearch';
config.browser.headless = false;

if (!config.browser.profiles) config.browser.profiles = {};
config.browser.profiles.jobsearch = {
    driver: 'existing-session',
    attachOnly: true,
    userDataDir: '${BRAVE_USERDATA//\\/\\\\}',
    color: '#FB542B'
};
config.browser.profiles.openclaw = {
    cdpPort: 18800,
    color: '#FF4500'
};

// Plugins — ensure browser is allowed
if (!config.plugins) config.plugins = {};
if (config.plugins.allow && !config.plugins.allow.includes('browser')) {
    config.plugins.allow.push('browser');
}

fs.writeFileSync(path, JSON.stringify(config, null, 2));
console.log('openclaw.json updated successfully');
"

ok "openclaw.json configured with DeepSeek + Brave Profile 6"

###############################################################################
# 7. Create project folder structure
###############################################################################
info "Creating project directory structure..."

mkdir -p "$PROJECT_DIR"/{skills,logs,screenshots,resumes}

# Initialize empty log file
cat > "$PROJECT_DIR/logs/applications_log.json" << 'LOGEOF'
[]
LOGEOF

ok "Project directories created at: $PROJECT_DIR"

###############################################################################
# 8. Generate config.yaml — candidate profile template
###############################################################################
info "Generating config.yaml template..."

cat > "$PROJECT_DIR/config.yaml" << 'CONFIGEOF'
# ============================================================================
# Job Auto-Apply — Candidate Configuration
# ============================================================================
# Edit ALL fields below with your actual information.
# The agent reads this file for every application.
# ============================================================================

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
  default_path: "resumes/default_resume.pdf"
  sde_path: "resumes/sde_resume.pdf"
  ai_ml_path: "resumes/ai_ml_resume.pdf"
  data_path: "resumes/data_resume.pdf"

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

# ── Control Settings ──
auto_mode: false       # true = apply immediately; false = queue for approval
dry_run: false         # true = do everything EXCEPT click final Submit
max_per_company: 10    # max applications per company per day
delay_min_seconds: 30  # minimum delay between applications (same site)
delay_max_seconds: 60  # maximum delay between applications (same site)
CONFIGEOF

ok "config.yaml created"

###############################################################################
# 9. Generate companies.yaml — hardcoded career URLs
###############################################################################
info "Generating companies.yaml..."

cat > "$PROJECT_DIR/companies.yaml" << 'COMPEOF'
# ============================================================================
# Target Companies — Career Page URLs
# ============================================================================
# These are the ONLY sites the agent visits. DO NOT modify unless you want
# to add/remove target companies.
# ============================================================================

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
COMPEOF

ok "companies.yaml created"

###############################################################################
# 10. Generate the master skill — job-apply-skill SKILL.md
###############################################################################
info "Generating job-apply skill..."

mkdir -p "$PROJECT_DIR/skills/job-auto-apply"

cat > "$PROJECT_DIR/skills/job-auto-apply/SKILL.md" << 'SKILLEOF'
---
name: job_auto_apply
description: >
  Autonomous job application agent. Searches target company career pages,
  finds matching roles, and applies to each one using the browser tool and
  candidate profile from config.yaml. Handles all page interaction adaptively
  via LLM reasoning — no hardcoded selectors.
---

# Job Auto-Apply Skill

You are an autonomous job application agent. Your mission is to visit company
career pages, find matching job listings, and apply to them on behalf of the
candidate whose profile is defined in the project config files.

## Configuration Files

The project lives in a workspace directory. Before starting any run, read these
files to load your operating parameters:

1. **config.yaml** — Contains ALL candidate information: personal details,
   resume paths, education, experience, skills, job preferences, screening
   answer templates, and control settings (auto_mode, dry_run, rate limits).

2. **companies.yaml** — Contains the list of target company career page URLs.
   You visit ONLY these URLs. Never navigate anywhere else.

## Core Workflow

For EACH company in companies.yaml, execute this loop:

### Phase 1: Search & Discovery

1. Use the `browser` tool to navigate to the company's careers_url.
2. Look at the page. Identify the search bar, filters, or job listing interface.
3. Search for roles matching the candidate's `job_preferences.target_titles`.
4. Apply any available filters for experience level, job type, location, and
   remote options based on config.yaml preferences.
5. Scan the results. For each job listing visible, read the title and brief
   description to determine if it's a relevant match.

### Phase 2: Evaluate Matches

For each potentially matching role:

1. Open the job listing detail page.
2. Read the full job description.
3. Determine relevance: Does the role match the candidate's target titles,
   experience level, and skill set? Use the candidate's skills, experience,
   and education from config.yaml to make this judgment.
4. If NOT a match, go back and continue scanning. Log it as "skipped" with
   a brief reason.
5. If it IS a match, proceed to Phase 3.

### Phase 3: Application (Auto Mode)

If `auto_mode: true` in config.yaml:

1. Click the "Apply" button (or equivalent) on the job listing page.
2. The application form will open. It may be a single page or multi-step.
3. For EVERY form field, determine what information is being requested and
   fill it from config.yaml:
   - Name, email, phone, location → from `candidate`
   - LinkedIn, portfolio, GitHub URLs → from `candidate`
   - Work authorization, sponsorship → from `candidate`
   - Years of experience → from `candidate`
   - Education details → from `education`
   - Work experience → from `experience`
   - Skills → from `skills`
4. For resume upload fields: Use the browser tool's upload capability.
   Choose the appropriate resume based on the role type:
   - SDE/Software roles → `resume.sde_path`
   - AI/ML roles → `resume.ai_ml_path`
   - Data roles → `resume.data_path`
   - General/other → `resume.default_path`
   Resolve paths relative to the project directory.
5. For screening questions:
   - Check `screening_answers.additional_qa` for pattern matches first.
   - Use `screening_answers.why_interested_template` and adapt it to the
     specific company and role.
   - Use `screening_answers.strengths` where relevant.
   - For questions not covered by templates, generate a contextually
     appropriate response using the candidate's full profile.
6. For cover letter fields:
   - Start from `screening_answers.cover_letter_base` and customize it
     for the specific role and company.
7. Navigate through ALL steps of multi-step application forms. Look for
   "Next", "Continue", "Review", etc. buttons and click through each page,
   filling all fields on each page.
8. On the final confirmation/review page:
   - If `dry_run: false` → Click Submit/Apply.
   - If `dry_run: true` → DO NOT click Submit. Log as "dry_run" status.
9. After submission, take a screenshot of the confirmation page and save it
   to the screenshots/ folder with naming: `{company}_{job_title}_{timestamp}.png`

### Phase 3: Application (Manual/Queue Mode)

If `auto_mode: false` in config.yaml:

1. Do NOT apply. Instead, collect the job details:
   - Job title, URL, company, brief description, match confidence.
2. Report this match to the user via the dashboard/chat.
3. Wait for the user to approve before applying.
4. When approved, execute the full application process from Phase 3 (Auto Mode).

## Logging

After EVERY action on every job listing, append an entry to
`logs/applications_log.json`. Each entry is a JSON object:

```json
{
  "timestamp": "2025-06-15T10:30:00Z",
  "company": "Google",
  "job_title": "Software Engineer, Cloud Infrastructure",
  "job_url": "https://careers.google.com/jobs/results/12345",
  "resume_used": "resumes/sde_resume.pdf",
  "status": "applied",
  "screening_questions": [
    {
      "question": "Why are you interested in this role?",
      "answer": "..."
    }
  ],
  "notes": ""
}
```

Status values: "applied", "skipped", "failed", "needs_review", "dry_run", "queued"

## Safety Rules — STRICT COMPLIANCE

1. **Rate limiting**: Maximum `max_per_company` applications per company per
   run (default 10). Count applications per company and stop when limit reached.

2. **Delays**: Wait a random duration between `delay_min_seconds` and
   `delay_max_seconds` between applications on the same site.

3. **CAPTCHA**: If you encounter a CAPTCHA or bot-detection challenge, STOP.
   Mark the application as "needs_review" and alert the user. Do NOT attempt
   to solve CAPTCHAs.

4. **Uncertainty**: If you encounter any form field, page element, or workflow
   step that you cannot confidently handle, STOP that application. Mark it
   "needs_review" with a detailed note explaining what was unclear.

5. **URL restriction**: You may ONLY navigate to URLs that are:
   - Listed in companies.yaml (career page roots)
   - Direct children/subpages of those career sites (job listings, application forms)
   - You must NEVER navigate to any other domain or site.

6. **No login handling**: The Brave browser profile already has active sessions
   on all target sites. NEVER type passwords. NEVER attempt login flows. If a
   site asks you to log in, mark it "needs_review" — the session may have expired.

7. **No hardcoded selectors**: You determine what to click, type, and interact
   with by READING and INTERPRETING the page content via browser snapshots.
   Every site is different. You adapt to each site's UI dynamically.

8. **Browser profile**: Always use the `jobsearch` browser profile. This is
   configured as the default in openclaw.json.

## Resume Selection Logic

Match the resume to the role category:

- Title contains "Software", "SDE", "Developer", "Backend", "Frontend",
  "Full Stack", "Platform" → use `resume.sde_path`
- Title contains "AI", "ML", "Machine Learning", "Deep Learning", "NLP",
  "Computer Vision" → use `resume.ai_ml_path`
- Title contains "Data Engineer", "Data Scientist", "Data Analyst",
  "Analytics", "BI" → use `resume.data_path`
- Anything else → use `resume.default_path`

If the specific resume path is empty, fall back to `resume.default_path`.

## Cover Letter Generation

When a cover letter is required:

1. Start with `screening_answers.cover_letter_base` as the foundation.
2. Customize the opening to mention the specific company and role title.
3. Highlight 2-3 relevant skills/experiences from the candidate profile that
   match the job description.
4. Keep it concise (250-400 words).
5. Professional tone. No AI-sounding phrases.

## Handling Multi-Step Application Forms

Many career portals (Workday, Taleo, Greenhouse, Lever, etc.) use multi-step
forms. Handle them as follows:

1. Take a snapshot after each page loads.
2. Identify all form fields on the current page.
3. Fill every field using config.yaml data.
4. Look for "Next", "Continue", "Save and Continue", or similar navigation.
5. Click to advance to the next step.
6. Repeat until you reach a review/submit page.
7. On the review page, verify the information looks correct.
8. Submit (or stop if dry_run mode).

## Error Recovery

- If a page fails to load: wait 10 seconds, retry once. If still failing,
  skip that company and log as "failed".
- If a form submission returns an error: take a screenshot, log the error
  message, mark as "failed", and move on.
- If the browser becomes unresponsive: report to user and halt the current run.
- Never retry indefinitely. Maximum 2 retries per action, then move on.

## Execution Start

When triggered (via cron job, standing order, or user command):

1. Read config.yaml from the project directory.
2. Read companies.yaml from the project directory.
3. Read the current applications_log.json to know what's already been applied to.
4. For each company, execute the Search → Evaluate → Apply workflow.
5. After processing all companies, report a summary to the user:
   - Total jobs found
   - Total applied
   - Total skipped
   - Total failed/needs_review
   - Any CAPTCHAs or issues encountered
SKILLEOF

ok "SKILL.md created at: $PROJECT_DIR/skills/job-auto-apply/SKILL.md"

###############################################################################
# 11. Install skill into OpenClaw workspace
###############################################################################
info "Installing skill into OpenClaw workspace..."

# Skills can live in ~/.openclaw/workspace/skills/ for global access [26]
mkdir -p "$SKILLS_GLOBAL"

# Symlink (or copy) the skill directory into OpenClaw's skill directory
SKILL_TARGET="$SKILLS_GLOBAL/job-auto-apply"
if [[ -d "$SKILL_TARGET" ]] || [[ -L "$SKILL_TARGET" ]]; then
    rm -rf "$SKILL_TARGET"
fi

# On Windows Git Bash, symlinks can be unreliable — copy instead
cp -r "$PROJECT_DIR/skills/job-auto-apply" "$SKILL_TARGET"
ok "Skill installed to $SKILL_TARGET"

###############################################################################
# 12. Create AGENTS.md with standing orders for the workspace
###############################################################################
info "Creating AGENTS.md with standing orders..."

mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/AGENTS.md" << 'AGENTSEOF'
# Agent Standing Orders

## Program: Job Auto-Apply

**Authority:** Search career pages, evaluate job listings, fill and submit
job applications using the browser tool and candidate profile.

**Trigger:** On-demand via user command or scheduled cron job.

**Approval gate:**
- If `auto_mode: false` in config.yaml → queue all matches for user approval
- If `auto_mode: true` → apply automatically within rate limits

**Escalation:**
- CAPTCHA encountered → pause and alert user
- Login required → pause and alert user (session expired)
- Uncertain form field → mark "needs_review" and continue to next job
- Browser unresponsive → halt and report

### Execution

When the user says "run job applications", "apply to jobs", or this task is
triggered by the daily cron:

1. Activate the `job_auto_apply` skill
2. Read config.yaml and companies.yaml from the project workspace
3. Execute the full Search → Evaluate → Apply workflow per the skill instructions
4. Log everything to logs/applications_log.json
5. Save confirmation screenshots to screenshots/
6. Report summary when complete

### What NOT to Do

- Never visit any URL outside the companies listed in companies.yaml
- Never type passwords or handle login flows
- Never solve CAPTCHAs
- Never exceed rate limits
- Never submit applications in dry_run mode
- Never modify config.yaml or companies.yaml
AGENTSEOF

ok "AGENTS.md created with standing orders"

###############################################################################
# 13. Set up cron job for daily runs
###############################################################################
info "Setting up scheduled cron job..."

# Add a cron job that fires daily at 9 AM, which the user can trigger or let run [27]
openclaw cron add \
    --name "daily-job-apply" \
    --cron "0 9 * * 1-5" \
    --timeout-seconds 3600 \
    --message "Execute job auto-apply per standing orders. Read config.yaml and companies.yaml from the job-auto-apply project directory. Run the job_auto_apply skill against all target companies. Log results and report summary when complete." \
    2>/dev/null || warn "Cron job creation may need manual setup — run: openclaw cron add --name daily-job-apply --cron '0 9 * * 1-5' --message 'Execute job auto-apply per standing orders.'"

ok "Cron job 'daily-job-apply' configured (weekdays 9 AM)"

###############################################################################
# 14. Generate README.md
###############################################################################
info "Generating README.md..."

cat > "$PROJECT_DIR/README.md" << 'READMEEOF'
# Job Auto-Apply — OpenClaw Automation

Autonomous job application bot powered by OpenClaw + DeepSeek. Visits 13
target company career pages, finds matching roles, and applies to them using
your existing Brave browser sessions.

## Quick Start

### 1. Prerequisites

- Windows 10/11 with Git Bash
- Brave Browser with Profile 6 ("jobsearch") already logged into all target sites
- OpenRouter API key (set as environment variable)

### 2. Setup

```bash
export OPENROUTER_API_KEY="sk-or-your-key-here"
bash setup.sh
```

### 3. Edit Your Profile

Open `config.yaml` and fill in ALL fields with your actual information:
- Personal details (name, email, phone, etc.)
- Education and experience
- Skills
- Resume file paths (place your PDFs in the `resumes/` folder)
- Screening answer templates
- Job preferences

### 4. Place Your Resumes

Copy your resume files into the `resumes/` folder:
- `default_resume.pdf` — general purpose resume
- `sde_resume.pdf` — software engineering focused
- `ai_ml_resume.pdf` — AI/ML focused
- `data_resume.pdf` — data engineering/science focused

### 5. Run

**Open the dashboard:**
```bash
openclaw dashboard
```

**Trigger manually from chat:**
Tell the agent: "Run job applications" or "Apply to jobs"

**Or let the cron job run:**
The daily cron fires at 9 AM on weekdays automatically.

### 6. Monitor

- **Dashboard:** OpenClaw web dashboard shows application status
- **Logs:** Check `logs/applications_log.json` for detailed records
- **Screenshots:** Confirmation screenshots saved in `screenshots/`

## Configuration

### config.yaml

All candidate information and control settings. Edit this file directly.

Key settings:
- `auto_mode: true` — apply to all matches automatically
- `auto_mode: false` — queue matches for your approval on the dashboard
- `dry_run: true` — do everything except click Submit (for testing)
- `max_per_company: 10` — rate limit per company per run

### companies.yaml

The 13 target company career page URLs. Modify only to add/remove companies.

## Target Companies

1. Adobe
2. Apple
3. McKinsey
4. Google
5. Meta
6. Intuit
7. JP Morgan
8. LinkedIn
9. Morgan Stanley
10. Microsoft
11. Netflix
12. Anthropic
13. Atlassian

## Architecture

- **OpenClaw** — open-source AI agent framework (Node.js)
- **DeepSeek** — LLM via OpenRouter API (with Groq fallback)
- **Browser tool** — OpenClaw's built-in Brave browser control
- **Brave Profile 6** — pre-authenticated browser sessions
- **Skills** — markdown-based agent instructions
- **Standing Orders** — persistent autonomous authority
- **Cron Jobs** — scheduled daily execution

## Troubleshooting

**Browser not connecting:**
```bash
openclaw browser --browser-profile jobsearch status
openclaw browser --browser-profile jobsearch start
```

Make sure Brave is running with remote debugging enabled:
Navigate to `brave://inspect/#remote-debugging` in Brave Profile 6.

**Gateway not running:**
```bash
openclaw gateway status
openclaw gateway run
```

**Skill not loading:**
```bash
openclaw skills list
openclaw gateway restart
```

**Check configuration:**
```bash
openclaw doctor
```
READMEEOF

ok "README.md created"

###############################################################################
# 15. Verify installation
###############################################################################
info "Verifying installation..."

echo ""
info "Running openclaw --version..."
openclaw --version 2>/dev/null || warn "openclaw CLI not yet in PATH — restart your terminal"

info "Running openclaw gateway status..."
openclaw gateway status 2>/dev/null || warn "Gateway not yet running — will start on next step"

info "Checking skill installation..."
openclaw skills list 2>/dev/null || warn "Skills list not available yet"

###############################################################################
# 16. Start the gateway and open dashboard
###############################################################################
echo ""
info "=============================================="
info "  Setup Complete!"
info "=============================================="
echo ""
info "Project directory: $PROJECT_DIR"
echo ""
info "NEXT STEPS:"
echo "  1. Edit $PROJECT_DIR/config.yaml with your information"
echo "  2. Place resume PDFs in $PROJECT_DIR/resumes/"
echo "  3. Open Brave Profile 6 and ensure you're logged into all target sites"
echo "  4. Enable remote debugging: brave://inspect/#remote-debugging"
echo "  5. Start the gateway and dashboard:"
echo ""
echo "     openclaw gateway run &"
echo "     openclaw dashboard"
echo ""
echo "  6. In the dashboard, tell the agent: \"Run job applications\""
echo ""
info "To run a dry test first, set dry_run: true in config.yaml"
echo ""

# Attempt to start the gateway in background
info "Starting OpenClaw gateway..."
openclaw gateway run &>/dev/null &
sleep 3

info "Opening dashboard..."
openclaw dashboard 2>/dev/null || info "Open the dashboard manually: openclaw dashboard"

echo ""
ok "All done. Happy job hunting!"

4. Enable remote debugging in Brave by visiting `brave://inspect/#remote-debugging`
5. Set `dry_run: true` in config.yaml for your first test run to verify everything works without actually submitting applications
