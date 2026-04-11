
#!/usr/bin/env bash
###############################################################################
# setup-remaining.sh
# Run in Git Bash AFTER:
#   1. pnpm setup + pnpm link --global  (openclaw --version works)
#   2. openclaw onboard --install-daemon (gateway running)
#   3. export OPENROUTER_API_KEY="sk-or-..."
#
# This script does steps 5–16: model config, browser config, project folders,
# config.yaml, companies.yaml, skill, AGENTS.md, cron job, README, verify.
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

WIN_USER="${USERNAME:-$USER}"
PROJECT_DIR="$(pwd)/job-auto-apply"
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_JSON="${OPENCLAW_HOME}/openclaw.json"
WORKSPACE_DIR="${OPENCLAW_HOME}/workspace"
SKILLS_GLOBAL="${WORKSPACE_DIR}/skills"

info "=============================================="
info "  Job Auto-Apply — Remaining Setup (Steps 5–16)"
info "=============================================="
echo ""

# ─── Sanity checks ──────────────────────────────────────────────────────────
command -v openclaw &>/dev/null || fail "openclaw not found in PATH. Run: pnpm setup && pnpm link --global first."
[[ -n "${OPENROUTER_API_KEY:-}" ]]  || fail "OPENROUTER_API_KEY not set. Run: export OPENROUTER_API_KEY=\"sk-or-...\""

###############################################################################
# STEP 5 — Configure model + browser via direct JSON merge
###############################################################################
# openclaw config set works for flat keys, but nested objects like
# browser.profiles.jobsearch need a direct JSON edit [5].
# We use node to safely merge into the existing openclaw.json.
###############################################################################
info "[Step 5] Configuring model (DeepSeek) + browser (Brave Profile 6)..."

node -e "
const fs = require('fs');
const JSON5 = (() => { try { return require('json5'); } catch { return JSON; } })();

const cfgPath = process.argv[1];
let raw = '{}';
try { raw = fs.readFileSync(cfgPath, 'utf8'); } catch {}
// Strip single-line comments so plain JSON.parse doesn't choke
const stripped = raw.replace(/\/\/.*$/gm, '').replace(/,\s*([\]}])/g, '\$1');
let cfg;
try { cfg = JSON5.parse(raw); } catch { cfg = JSON.parse(stripped); }

// ── Env ──
if (!cfg.env) cfg.env = {};
cfg.env.OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;

// ── Model: DeepSeek primary, reasoner fallback, then Llama ──
if (!cfg.agents) cfg.agents = {};
if (!cfg.agents.defaults) cfg.agents.defaults = {};
cfg.agents.defaults.model = {
  primary:   'openrouter/deepseek/deepseek-chat',
  fallbacks: [
    'openrouter/deepseek/deepseek-reasoner',
    'openrouter/meta-llama/llama-4-maverick'
  ]
};
cfg.agents.defaults.models = {
  'openrouter/deepseek/deepseek-chat':     {},
  'openrouter/deepseek/deepseek-reasoner': {},
  'openrouter/meta-llama/llama-4-maverick': {}
};

// ── Browser: Brave + Profile 6 \"jobsearch\" ──
if (!cfg.browser) cfg.browser = {};
cfg.browser.enabled        = true;
cfg.browser.headless       = false;
cfg.browser.defaultProfile = 'jobsearch';
cfg.browser.executablePath = 'C:\\\\Program Files\\\\BraveSoftware\\\\Brave-Browser\\\\Application\\\\brave.exe';

if (!cfg.browser.profiles) cfg.browser.profiles = {};
cfg.browser.profiles.jobsearch = {
  driver:      'existing-session',
  attachOnly:  true,
  userDataDir: 'C:\\\\Users\\\\${WIN_USER}\\\\AppData\\\\Local\\\\BraveSoftware\\\\Brave-Browser\\\\User Data',
  color:       '#FB542B'
};
// Keep the default managed profile too
cfg.browser.profiles.openclaw = cfg.browser.profiles.openclaw || {
  cdpPort: 18800,
  color:   '#FF4500'
};

// ── Plugins: ensure browser is in the allow list if one exists ──
if (cfg.plugins && cfg.plugins.allow && !cfg.plugins.allow.includes('browser')) {
  cfg.plugins.allow.push('browser');
}

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log('  openclaw.json updated');
" "$OPENCLAW_JSON" "$WIN_USER"

ok "Model → openrouter/deepseek/deepseek-chat  |  Browser → Brave Profile 6 (jobsearch)"

###############################################################################
# STEP 6 — Restart gateway so browser config takes effect
###############################################################################
info "[Step 6] Restarting gateway to pick up browser config..."
openclaw gateway restart 2>/dev/null || openclaw gateway run &>/dev/null &
sleep 4
openclaw gateway status 2>/dev/null && ok "Gateway is running" || warn "Gateway may still be starting — check with: openclaw gateway status"

###############################################################################
# STEP 7 — Create project folder structure
###############################################################################
info "[Step 7] Creating project folders..."

mkdir -p "$PROJECT_DIR"/{skills/job-auto-apply,logs,screenshots,resumes}
echo '[]' > "$PROJECT_DIR/logs/applications_log.json"

ok "Project tree created at: $PROJECT_DIR"

###############################################################################
# STEP 8 — config.yaml  (candidate profile — edit this!)
###############################################################################
info "[Step 8] Writing config.yaml..."

cat > "$PROJECT_DIR/config.yaml" << 'EOF'
# ============================================================================
# Job Auto-Apply — Candidate Configuration
# Fill in ALL fields below.  The agent reads this for every application.
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
auto_mode: false          # true → apply immediately; false → queue for approval
dry_run: false            # true → everything except final Submit click
max_per_company: 10
delay_min_seconds: 30
delay_max_seconds: 60
EOF

ok "config.yaml written (edit it with your details)"

###############################################################################
# STEP 9 — companies.yaml  (hardcoded career URLs)
###############################################################################
info "[Step 9] Writing companies.yaml..."

cat > "$PROJECT_DIR/companies.yaml" << 'EOF'
# ============================================================================
# Target Companies — Career Page URLs
# The agent visits ONLY these URLs.
# ============================================================================

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

ok "companies.yaml written (13 companies)"

###############################################################################
# STEP 10 — Master skill:  SKILL.md
###############################################################################
info "[Step 10] Writing SKILL.md (agent instructions)..."

cat > "$PROJECT_DIR/skills/job-auto-apply/SKILL.md" << 'SKILLEOF'
---
name: job_auto_apply
description: >
  Autonomous job-application agent.  Searches target company career pages,
  finds matching roles, and applies using the browser tool + candidate
  profile from config.yaml.  All page interaction is adaptive via LLM
  reasoning — no hardcoded selectors.
---

# Job Auto-Apply Skill

You are an autonomous job-application agent.

## Files You Must Read Before Every Run

1. **config.yaml** — candidate info, resume paths, preferences, screening
   answer templates, and control flags (auto_mode, dry_run, rate limits).
2. **companies.yaml** — the ONLY URLs you may visit.
3. **logs/applications_log.json** — already-submitted applications (skip
   duplicates).

---

## Workflow Per Company

### Phase 1 — Search & Filter

1. `browser navigate` to the company's `careers_url`.
2. Take a `browser snapshot` to read the page structure.
3. Use the search bar / filters to look for titles from
   `job_preferences.target_titles`.
4. Apply any experience-level, location, remote, and job-type filters the
   site offers.

### Phase 2 — Evaluate Each Listing

For every result that looks like a potential match:

1. Open the detail page and read the full job description.
2. Compare it against the candidate's skills, experience, and education
   from config.yaml.
3. If NOT relevant → log as `"skipped"` with a reason → go back.
4. If relevant → proceed to Phase 3.

### Phase 3 — Apply

**If `auto_mode: true`:**

1. Click "Apply" (or equivalent).
2. Fill every form field from config.yaml:
   - Name, email, phone, location, URLs → `candidate`
   - Work auth / sponsorship → `candidate`
   - Education → `education`
   - Experience → `experience`
   - Skills → `skills`
3. Upload the right resume:
   - Title contains Software / SDE / Developer / Backend / Frontend /
     Full Stack / Platform → `resume.sde_path`
   - Title contains AI / ML / Machine Learning / Deep Learning / NLP /
     Computer Vision → `resume.ai_ml_path`
   - Title contains Data Engineer / Data Scientist / Data Analyst /
     Analytics / BI → `resume.data_path`
   - Otherwise → `resume.default_path`
   If the specific path is empty, fall back to `resume.default_path`.
   Use `browser upload <path>` after arming the file chooser.
4. Screening questions:
   - Check `screening_answers.additional_qa` for pattern matches first.
   - Adapt `why_interested_template` to the specific company/role.
   - For anything not in config, generate a contextual answer from the
     full candidate profile.
5. Cover letter:
   - Base from `screening_answers.cover_letter_base`.
   - Customise opening for the company + role.
   - Highlight 2–3 matching skills/experiences.
   - 250–400 words, professional tone, no AI-sounding phrases.
6. Navigate every step of multi-step forms (Next / Continue / Review).
   Take a snapshot after each page loads, fill all fields, then advance.
7. Final page:
   - `dry_run: false` → Click Submit.
   - `dry_run: true`  → STOP. Log as `"dry_run"`.
8. Screenshot the confirmation → `screenshots/{company}_{title}_{ts}.png`.

**If `auto_mode: false`:**

1. Collect job title, URL, company, description snippet, match confidence.
2. Report to the user. Wait for approval before applying.
3. Log as `"queued"`.

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
  "screening_questions": [ { "question": "...", "answer": "..." } ],
  "notes": ""
}
```

---

## Safety Rules (STRICT)

1. Max `max_per_company` applications per company per run (default 10).
2. Random delay between `delay_min_seconds` and `delay_max_seconds`
   between applications on the same site.
3. **CAPTCHA** → STOP, mark `"needs_review"`, alert user.
4. **Uncertain** about any field/step → STOP that application,
   mark `"needs_review"` with a detailed note.
5. **URL restriction** — only career-page roots from companies.yaml and
   their direct subpages (job listings, application forms).
6. **No login** — sessions already exist in Brave Profile 6.  NEVER type
   passwords.  If asked to log in → mark `"needs_review"`.
7. **No hardcoded selectors** — interpret each page dynamically via
   `browser snapshot` + refs.
8. **Browser profile** — always use `profile="jobsearch"`.
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
rm -rf "$SKILL_TARGET" 2>/dev/null
cp -r "$PROJECT_DIR/skills/job-auto-apply" "$SKILL_TARGET"

# Verify
openclaw skills list 2>/dev/null | grep -qi "job_auto_apply" \
  && ok "Skill 'job_auto_apply' visible to OpenClaw" \
  || warn "Skill installed but not yet visible — restart gateway or start a /new session"

###############################################################################
# STEP 12 — AGENTS.md  (standing orders)
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

1. Read config.yaml and companies.yaml from the project directory.
2. Read logs/applications_log.json to skip duplicates.
3. For each company run:  Search → Evaluate → Apply  (per job_auto_apply skill).
4. Log every action.  Screenshot every confirmation.
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

# Remove existing job with same name if present (idempotent re-runs)
openclaw cron remove --name "daily-job-apply" 2>/dev/null || true

openclaw cron add \
  --name "daily-job-apply" \
  --cron "0 9 * * 1-5" \
  --timeout-seconds 3600 \
  --message "Execute job auto-apply per standing orders. Read config.yaml and companies.yaml from the job-auto-apply project directory (${PROJECT_DIR}). Activate the job_auto_apply skill. Process all 13 target companies. Log results to logs/applications_log.json. Save confirmation screenshots. Report summary." \
  2>/dev/null \
  && ok "Cron job 'daily-job-apply' → weekdays 9 AM" \
  || warn "Cron job creation needs manual step. Run:\n  openclaw cron add --name daily-job-apply --cron '0 9 * * 1-5' --timeout-seconds 3600 --message 'Execute job auto-apply per standing orders.'"

###############################################################################
# STEP 14 — README.md
###############################################################################
info "[Step 14] Writing README.md..."

cat > "$PROJECT_DIR/README.md" << 'EOF'
# Job Auto-Apply — OpenClaw + DeepSeek

Autonomous job-application bot.  Visits 13 company career pages, finds
matching roles, and applies using your existing Brave browser sessions.

## Usage

```bash
# Open the dashboard
openclaw dashboard

# Tell the agent (in chat or dashboard):
"Run job applications"

# Or let the weekday 9 AM cron do it automatically
openclaw cron list
```

## First-Time Checklist

1. Edit `config.yaml` — fill in every field
2. Place resume PDFs in `resumes/`
3. Open Brave Profile 6 → verify you're logged into all 13 sites
4. Enable remote debugging: `brave://inspect/#remote-debugging`
5. Set `dry_run: true` for a test run, then set `false` for real

## Control Flags (in config.yaml)

| Flag              | Effect                                      |
|-------------------|---------------------------------------------|
| `auto_mode: true` | Apply to everything automatically            |
| `auto_mode: false`| Queue matches on dashboard for your approval |
| `dry_run: true`   | Do everything EXCEPT click Submit            |
| `max_per_company` | Rate limit per company per run (default 10)  |

## Logs & Screenshots

- `logs/applications_log.json` — every action logged
- `screenshots/` — confirmation page captures

## Troubleshooting

```bash
openclaw doctor                              # health check
openclaw gateway status                      # gateway running?
openclaw browser --browser-profile jobsearch status  # browser connected?
openclaw skills list                         # skill loaded?
openclaw cron list                           # cron active?
```
EOF

ok "README.md written"

###############################################################################
# STEP 15 — Verify everything
###############################################################################
echo ""
info "=============================================="
info "  Verification"
info "=============================================="

echo ""
info "OpenClaw version:"
openclaw --version 2>/dev/null || warn "CLI not in PATH"

echo ""
info "Gateway status:"
openclaw gateway status 2>/dev/null || warn "Gateway not running — start with: openclaw gateway run"

echo ""
info "Installed skills:"
openclaw skills list 2>/dev/null || warn "Could not list skills"

echo ""
info "Cron jobs:"
openclaw cron list 2>/dev/null || warn "Could not list cron jobs"

echo ""
info "Browser profile:"
openclaw browser --browser-profile jobsearch status 2>/dev/null || warn "Browser not attached yet — open Brave first, enable remote debugging"

###############################################################################
# STEP 16 — Open dashboard
###############################################################################
echo ""
info "=============================================="
info "  SETUP COMPLETE"
info "=============================================="
echo ""
echo "  Project directory:  $PROJECT_DIR"
echo ""
echo "  BEFORE YOUR FIRST RUN:"
echo "    1.  Edit config.yaml with your real info"
echo "    2.  Put resume PDFs in resumes/"
echo "    3.  Open Brave Profile 6 (jobsearch)"
echo "    4.  Go to brave://inspect/#remote-debugging  → enable it"
echo "    5.  Set dry_run: true for your first test"
echo ""
echo "  THEN:"
echo "    openclaw dashboard"
echo "    → In the chat, type: \"Run job applications\""
echo ""

info "Launching dashboard now..."
openclaw dashboard 2>/dev/null &

ok "Done. Good luck with the applications!"
