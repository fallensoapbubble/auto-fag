#!/usr/bin/env bash
###############################################################################
# setup-remaining.sh
#
# Run from:  ~/Downloads/project/APPLY/
# In Git Bash (MINGW32):   bash setup-remaining.sh
#
# What you should have ALREADY done:
#   - OpenClaw built (pnpm install && pnpm ui:build && pnpm build)
#   - pnpm setup  (fixes global bin dir)
#   - pnpm link --global  (or use "pnpm openclaw" from openclaw/ dir)
#   - openclaw onboard --install-daemon  (auth + model = deepseek done)
#   - .env file or env vars exported with your API keys
#
# What THIS script does (Steps 5–16):
#   5.  Write all API keys + model config + fallbacks into openclaw.json
#   6.  Configure Brave Profile 6 browser
#   7.  Create job-auto-apply/ project folders
#   8.  Write config.yaml
#   9.  Write companies.yaml
#   10. Write SKILL.md
#   11. Install skill into OpenClaw
#   12. Write AGENTS.md (standing orders)
#   13. Create cron job
#   14. Write README.md
#   15. Verify everything
#   16. Launch dashboard
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

###############################################################################
# Resolve paths
###############################################################################
WIN_USER="${USERNAME:-$USER}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/job-auto-apply"
OPENCLAW_REPO="${SCRIPT_DIR}/openclaw"
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_JSON="${OPENCLAW_HOME}/openclaw.json"
WORKSPACE_DIR="${OPENCLAW_HOME}/workspace"
SKILLS_GLOBAL="${WORKSPACE_DIR}/skills"

# Detect if openclaw is global or needs pnpm prefix
if command -v openclaw &>/dev/null; then
    OC="openclaw"
elif [[ -d "$OPENCLAW_REPO" ]]; then
    OC="pnpm --dir ${OPENCLAW_REPO} openclaw"
else
    fail "Cannot find openclaw CLI. Either run 'pnpm link --global' in openclaw/ or ensure openclaw/ exists."
fi

info "=============================================="
info "  Job Auto-Apply — Setup (Steps 5–16)"
info "  User: ${WIN_USER}"
info "  Script dir: ${SCRIPT_DIR}"
info "  OpenClaw CLI: ${OC}"
info "=============================================="
echo ""

###############################################################################
# Load .env file if present (Git Bash compatible)
###############################################################################
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    info "Loading .env file..."
    set -a
    while IFS='=' read -r key val; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        # Trim whitespace and quotes
        val="${val%\"}"
        val="${val#\"}"
        val="${val%\'}"
        val="${val#\'}"
        export "$key=$val"
    done < "${SCRIPT_DIR}/.env"
    set +a
    ok ".env loaded"
fi

# Validate at least one API key is present
if [[ -z "${OPENROUTER_API_KEY:-}" && -z "${DEEPSEEK_API_KEY:-}" && -z "${GROQ_API_KEY:-}" ]]; then
    fail "No API keys found. Set at least OPENROUTER_API_KEY or DEEPSEEK_API_KEY in your .env file."
fi

###############################################################################
# STEP 5 — Configure model, fallbacks, and API keys in openclaw.json
###############################################################################
# openclaw config set handles flat keys, but nested objects like
# browser.profiles and fallback arrays need direct JSON editing.
# We use node (already installed since OpenClaw was built).
###############################################################################
info "[Step 5] Configuring models, API keys, and fallbacks..."

mkdir -p "$OPENCLAW_HOME"
# Ensure openclaw.json exists
[[ -f "$OPENCLAW_JSON" ]] || echo '{}' > "$OPENCLAW_JSON"

node -e "
const fs = require('fs');

const cfgPath = process.argv[1];
const winUser = process.argv[2];

// Read existing config — handle JSON5 comments
let raw = '{}';
try { raw = fs.readFileSync(cfgPath, 'utf8'); } catch {}
const stripped = raw
    .replace(/\/\/.*$/gm, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/,(\s*[\]}])/g, '\$1');
let cfg;
try { cfg = JSON.parse(stripped); } catch { cfg = {}; }

// ── env: inject all available API keys ──
if (!cfg.env) cfg.env = {};
if (process.env.OPENROUTER_API_KEY)   cfg.env.OPENROUTER_API_KEY   = process.env.OPENROUTER_API_KEY;
if (process.env.OPENROUTER_API_KEY_2) cfg.env.OPENROUTER_API_KEY_2 = process.env.OPENROUTER_API_KEY_2;
if (process.env.GROQ_API_KEY)         cfg.env.GROQ_API_KEY         = process.env.GROQ_API_KEY;
if (process.env.DEEPSEEK_API_KEY)     cfg.env.DEEPSEEK_API_KEY     = process.env.DEEPSEEK_API_KEY;

// ── agents.defaults: model + fallbacks ──
// Primary: DeepSeek via OpenRouter
// Fallback 1: DeepSeek direct API
// Fallback 2: Groq (fast, free tier)
// Fallback 3: OpenRouter secondary key
if (!cfg.agents) cfg.agents = {};
if (!cfg.agents.defaults) cfg.agents.defaults = {};

cfg.agents.defaults.model = {
    primary: 'openrouter/deepseek/deepseek-chat',
    fallbacks: [
        'deepseek/deepseek-chat',
        'groq/deepseek-r1-distill-llama-70b',
        'openrouter/deepseek/deepseek-reasoner'
    ]
};

cfg.agents.defaults.models = {
    'openrouter/deepseek/deepseek-chat': {},
    'openrouter/deepseek/deepseek-reasoner': {},
    'deepseek/deepseek-chat': {},
    'groq/deepseek-r1-distill-llama-70b': {}
};

// ── Browser: Brave executable + Profile 6 (jobsearch) ──
if (!cfg.browser) cfg.browser = {};
cfg.browser.enabled        = true;
cfg.browser.headless       = false;
cfg.browser.defaultProfile = 'jobsearch';
cfg.browser.executablePath =
    'C:\\\\Program Files\\\\BraveSoftware\\\\Brave-Browser\\\\Application\\\\brave.exe';

if (!cfg.browser.profiles) cfg.browser.profiles = {};
cfg.browser.profiles.jobsearch = {
    driver:      'existing-session',
    attachOnly:  true,
    userDataDir: 'C:\\\\Users\\\\' + winUser + '\\\\AppData\\\\Local\\\\BraveSoftware\\\\Brave-Browser\\\\User Data',
    color:       '#FB542B'
};
cfg.browser.profiles.openclaw = cfg.browser.profiles.openclaw || {
    cdpPort: 18800,
    color:   '#FF4500'
};

// ── Plugins: make sure browser plugin is not blocked ──
if (cfg.plugins && cfg.plugins.allow && !cfg.plugins.allow.includes('browser')) {
    cfg.plugins.allow.push('browser');
}

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log('  openclaw.json updated successfully');
" "$OPENCLAW_JSON" "$WIN_USER"

ok "Models: openrouter/deepseek/deepseek-chat (primary)"
ok "Fallbacks: deepseek-direct → groq → deepseek-reasoner"
ok "Browser: Brave Profile 6 (jobsearch) as existing-session"

###############################################################################
# STEP 6 — Restart gateway to pick up new config
###############################################################################
info "[Step 6] Restarting gateway..."
$OC gateway restart 2>/dev/null \
    || ($OC gateway run &>/dev/null &) \
    || warn "Gateway restart failed — you may need to start it manually: openclaw gateway run"
sleep 4
$OC gateway status 2>/dev/null && ok "Gateway is running" || warn "Gateway may still be starting"

###############################################################################
# STEP 7 — Create project folder structure
###############################################################################
info "[Step 7] Creating project folders..."

mkdir -p "$PROJECT_DIR"/{skills/job-auto-apply,logs,screenshots,resumes}
[[ -f "$PROJECT_DIR/logs/applications_log.json" ]] || echo '[]' > "$PROJECT_DIR/logs/applications_log.json"

ok "Project tree: $PROJECT_DIR"

###############################################################################
# STEP 8 — config.yaml
###############################################################################
info "[Step 8] Writing config.yaml..."

cat > "$PROJECT_DIR/config.yaml" << 'EOF'
# ============================================================================
#  JOB AUTO-APPLY — Candidate Configuration
#  Fill ALL fields.  The agent reads this for every application.
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

# ── Control ──
auto_mode: false
dry_run: false
max_per_company: 10
delay_min_seconds: 30
delay_max_seconds: 60
EOF

ok "config.yaml created"

###############################################################################
# STEP 9 — companies.yaml
###############################################################################
info "[Step 9] Writing companies.yaml..."

cat > "$PROJECT_DIR/companies.yaml" << 'EOF'
companies:
  - name: Adobe
    careers_url: "https://careers.adobe.com/us/en"
  - name: Apple
    careers_url: "https://jobs.apple.com"
  - name: McKinsey
    careers_url: "https://www.mckinsey.com/careers/search-jobs"
  - name: Google
    careers_url: "https://www.google.com/about/careers/applications/jobs/results"
  - name: Meta
    careers_url: "https://www.metacareers.com/jobs"
  - name: Intuit
    careers_url: "https://jobs.intuit.com"
  - name: JP Morgan
    careers_url: "https://careers.jpmorgan.com/global/en/jobs"
  - name: LinkedIn
    careers_url: "https://careers.linkedin.com"
  - name: Morgan Stanley
    careers_url: "https://ms.taleo.net/careersection/2/jobsearch.ftl"
  - name: Microsoft
    careers_url: "https://careers.microsoft.com/global/en/search"
  - name: Netflix
    careers_url: "https://jobs.netflix.com"
  - name: Anthropic
    careers_url: "https://www.anthropic.com/careers"
  - name: Atlassian
    careers_url: "https://www.atlassian.com/company/careers/all-jobs"
EOF

ok "companies.yaml — 13 companies"

###############################################################################
# STEP 10 — SKILL.md  (the core agent instructions)
###############################################################################
info "[Step 10] Writing SKILL.md..."

cat > "$PROJECT_DIR/skills/job-auto-apply/SKILL.md" << 'SKILLEOF'
---
name: job_auto_apply
description: >
  Autonomous job-application agent. Searches target company career pages,
  finds matching roles, and applies using the browser tool + candidate
  profile from config.yaml. All page interaction is adaptive via LLM
  reasoning — no hardcoded selectors.
---

# Job Auto-Apply Skill

You are an autonomous job-application agent.

## Files to Read Before Every Run

All paths are relative to the job-auto-apply project directory.

1. **config.yaml** — candidate info, resume paths, preferences, screening
   templates, control flags (auto_mode, dry_run, rate limits).
2. **companies.yaml** — the ONLY URLs you may visit.
3. **logs/applications_log.json** — already-submitted applications (skip dupes).

---

## Workflow Per Company

### Phase 1 — Search & Filter

1. `browser navigate` to the company's `careers_url` using `profile="jobsearch"`.
2. `browser snapshot` to read the page structure.
3. Use search bars and filters to look for titles matching
   `job_preferences.target_titles`.
4. Apply experience-level, location, remote, job-type filters where available.

### Phase 2 — Evaluate Each Listing

For each result that looks potentially relevant:

1. Open the detail page. Read the full job description.
2. Compare against candidate skills, experience, and education in config.yaml.
3. NOT a match → log as `"skipped"` with a reason → go back.
4. IS a match → proceed to Phase 3.

### Phase 3a — Apply (auto_mode: true)

1. Click "Apply" (or equivalent).
2. Fill every form field from config.yaml:
   - Name, email, phone, location, URLs → `candidate`
   - Work auth, sponsorship → `candidate`
   - Education → `education`
   - Experience → `experience`
   - Skills → `skills`
3. Upload the right resume:
   - Software/SDE/Developer/Backend/Frontend/Full Stack/Platform → `resume.sde_path`
   - AI/ML/Machine Learning/Deep Learning/NLP/Computer Vision → `resume.ai_ml_path`
   - Data Engineer/Data Scientist/Data Analyst/Analytics/BI → `resume.data_path`
   - Otherwise → `resume.default_path`
   If the specific path is empty fall back to `resume.default_path`.
   Arm the file chooser with `browser upload` BEFORE clicking the upload button.
4. Screening questions:
   - Check `screening_answers.additional_qa` for pattern matches first.
   - Adapt `why_interested_template` to the specific company and role.
   - Generate contextual answers from candidate profile for anything else.
5. Cover letter (when required):
   - Base from `screening_answers.cover_letter_base`.
   - Customise opening for the specific company + role title.
   - Highlight 2–3 matching skills/experiences.
   - 250–400 words. Professional tone. No AI-sounding phrases.
6. Navigate every step of multi-step forms (Next/Continue/Review).
   Take a `browser snapshot` after each page loads, fill all fields, then advance.
7. Final page:
   - `dry_run: false` → Click Submit.
   - `dry_run: true` → STOP. Log as `"dry_run"`.
8. Screenshot the confirmation page →
   `screenshots/{company}_{title}_{timestamp}.png`

### Phase 3b — Queue for Approval (auto_mode: false)

1. Do NOT apply. Collect: job title, URL, company, description, match confidence.
2. Report to user via dashboard/chat. Log as `"queued"`.
3. When user approves, execute Phase 3a for that job.

---

## Logging

Append one JSON object per job to `logs/applications_log.json`:

```json
{
  "timestamp": "ISO-8601",
  "company": "Google",
  "job_title": "Software Engineer, Cloud",
  "job_url": "https://...",
  "resume_used": "resumes/sde_resume.pdf",
  "status": "applied | skipped | failed | needs_review | dry_run | queued",
  "screening_questions": [{"question": "...", "answer": "..."}],
  "notes": ""
}
```

---

## Safety Rules — STRICT

1. Max `max_per_company` applications per company per run (default 10).
2. Random delay between `delay_min_seconds` and `delay_max_seconds` on same site.
3. **CAPTCHA** → STOP, mark `"needs_review"`, alert user.
4. **Uncertain** about any field/step → STOP that application,
   mark `"needs_review"` with detailed note.
5. **URL restriction** — only career-page roots from companies.yaml and their
   direct subpages (job listings, application forms).
6. **No login** — sessions exist in Brave Profile 6. NEVER type passwords.
   If asked to log in → `"needs_review"`.
7. **No hardcoded selectors** — interpret pages via `browser snapshot` + refs.
8. **Always use** `profile="jobsearch"` for all browser commands.
9. Max 2 retries per action, then move on.

---

## Run Summary

After all companies, report:
- Total jobs found
- Total applied
- Total skipped
- Total failed / needs_review
- CAPTCHAs or issues encountered
SKILLEOF

ok "SKILL.md written"

###############################################################################
# STEP 11 — Install skill into OpenClaw's skill directory
###############################################################################
info "[Step 11] Installing skill into OpenClaw..."

mkdir -p "$SKILLS_GLOBAL"
SKILL_TARGET="$SKILLS_GLOBAL/job-auto-apply"
rm -rf "$SKILL_TARGET" 2>/dev/null || true
cp -r "$PROJECT_DIR/skills/job-auto-apply" "$SKILL_TARGET"

# Verify
if $OC skills list 2>/dev/null | grep -qi "job_auto_apply"; then
    ok "Skill 'job_auto_apply' is visible"
else
    warn "Skill installed but not visible yet — restart gateway or /new session"
fi

###############################################################################
# STEP 12 — AGENTS.md (standing orders in workspace)
###############################################################################
info "[Step 12] Writing AGENTS.md (standing orders)..."

mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/AGENTS.md" << 'EOF'
# Agent Standing Orders

## Program: Job Auto-Apply

**Authority:** Search career pages, evaluate job listings, fill and submit
applications using the browser tool and the candidate profile.

**Trigger:** On-demand ("run job applications") or daily cron (weekdays 9 AM).

**Approval gate:**
- `auto_mode: false` → queue all matches for user approval first
- `auto_mode: true`  → apply within rate limits automatically

**Escalation:**
- CAPTCHA → pause, alert user
- Login required → pause (session expired)
- Uncertain field → mark "needs_review", move on
- Browser unresponsive → halt, report

### Execution

1. Read config.yaml and companies.yaml from the job-auto-apply project directory.
2. Read logs/applications_log.json to skip duplicates.
3. For each company: Search → Evaluate → Apply (per job_auto_apply skill).
4. Log every action. Screenshot every confirmation.
5. Report summary when complete.

### Boundaries

- NEVER visit URLs outside companies.yaml
- NEVER type passwords or handle logins
- NEVER solve CAPTCHAs
- NEVER exceed rate limits
- NEVER submit in dry_run mode
- NEVER modify config.yaml or companies.yaml
EOF

ok "AGENTS.md written"

###############################################################################
# STEP 13 — Cron job (weekdays 9 AM)
###############################################################################
info "[Step 13] Creating cron job..."

$OC cron remove --name "daily-job-apply" 2>/dev/null || true

$OC cron add \
    --name "daily-job-apply" \
    --cron "0 9 * * 1-5" \
    --timeout-seconds 3600 \
    --message "Execute job auto-apply per standing orders. Read config.yaml and companies.yaml from ${PROJECT_DIR}. Activate the job_auto_apply skill. Process all 13 target companies. Log results. Save confirmation screenshots. Report summary when complete." \
    2>/dev/null \
    && ok "Cron: daily-job-apply → weekdays 9:00 AM" \
    || warn "Cron job may need manual creation. Run:\n  ${OC} cron add --name daily-job-apply --cron '0 9 * * 1-5' --timeout-seconds 3600 --message 'Run job auto-apply.'"

###############################################################################
# STEP 14 — README.md
###############################################################################
info "[Step 14] Writing README.md..."

cat > "$PROJECT_DIR/README.md" << 'EOF'
# Job Auto-Apply — OpenClaw + DeepSeek

Autonomous job-application bot. Visits 13 company career pages, finds
matching roles, applies using your existing Brave browser sessions.

## Quick Start

```bash
# 1. Edit config.yaml with your info
# 2. Place resume PDFs in resumes/
# 3. Open Brave Profile 6 → verify logged into all sites
# 4. Enable remote debugging: brave://inspect/#remote-debugging
# 5. Set dry_run: true for first test

openclaw dashboard
# In chat: "Run job applications"
```

## Control Flags (config.yaml)

| Flag              | Effect                                       |
|-------------------|----------------------------------------------|
| `auto_mode: true` | Apply automatically                           |
| `auto_mode: false`| Queue for approval on dashboard               |
| `dry_run: true`   | Everything except final Submit click          |
| `max_per_company` | Rate limit per company per run (default 10)   |

## Troubleshooting

```bash
openclaw doctor
openclaw gateway status
openclaw browser --browser-profile jobsearch status
openclaw skills list
openclaw cron list
```
EOF

ok "README.md written"

###############################################################################
# STEP 15 — Verify
###############################################################################
echo ""
info "=============================================="
info "  Verification"
info "=============================================="

echo ""
info "OpenClaw CLI:"
$OC --version 2>/dev/null || warn "CLI issue"

echo ""
info "Gateway:"
$OC gateway status 2>/dev/null || warn "Gateway not running"

echo ""
info "Skills:"
$OC skills list 2>/dev/null || warn "Could not list skills"

echo ""
info "Cron jobs:"
$OC cron list 2>/dev/null || warn "Could not list cron"

echo ""
info "Browser (jobsearch profile):"
$OC browser --browser-profile jobsearch status 2>/dev/null \
    || warn "Browser not attached — open Brave Profile 6 + enable remote debugging first"

###############################################################################
# STEP 16 — Done
###############################################################################
echo ""
info "=============================================="
info "  SETUP COMPLETE"
info "=============================================="
echo ""
echo "  Project: ${PROJECT_DIR}"
echo ""
echo "  BEFORE FIRST RUN:"
echo "    1. Edit config.yaml with your real info"
echo "    2. Put resume PDFs in resumes/"
echo "    3. Open Brave → Profile 6 (jobsearch)"
echo "    4. brave://inspect/#remote-debugging → enable it"
echo "    5. Set dry_run: true in config.yaml for testing"
echo ""
echo "  TO RUN:"
echo "    ${OC} dashboard"
echo "    → In chat: \"Run job applications\""
echo ""

info "Launching dashboard..."
$OC dashboard 2>/dev/null &

ok "All done!"
