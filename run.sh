#!/usr/bin/env bash
###############################################################################
# fix-and-go.sh
#
# Fixes:
#   1. Detects your ACTUAL OpenClaw workspace path
#   2. Copies job_auto_apply skill to the correct location
#   3. Adds skills.load.extraDirs as a fallback
#   4. Copies AGENTS.md to the correct workspace
#   5. Configures browser for Brave Profile 6 "jobsearch"
#   6. Adds the cron job
#   7. Restarts gateway
#   8. Prints dashboard URL
#
# Run from: ~/Downloads/project/APPLY/
#   cd ~/Downloads/project/APPLY && bash fix-and-go.sh
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_REPO="${SCRIPT_DIR}/openclaw"
PROJECT_DIR="${SCRIPT_DIR}/job-auto-apply"
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_JSON="${OPENCLAW_HOME}/openclaw.json"
WIN_USER="${USERNAME:-$USER}"

# OpenClaw command
OC="pnpm --dir ${OPENCLAW_REPO} openclaw"

info "=============================================="
info "  Fix & Go — Skill + Browser + Cron Setup"
info "=============================================="
echo ""

###############################################################################
# STEP 1 — Find the REAL workspace path
###############################################################################
info "[1/8] Detecting workspace path..."

WORKSPACE=$($OC config get agents.defaults.workspace 2>/dev/null | grep -v '^\s*>' | grep -v 'openclaw@' | grep -v 'ELIFECYCLE' | grep -v '🦞' | tail -1 | tr -d '[:space:]' || echo "")

# If empty or failed, use the default
if [[ -z "$WORKSPACE" || "$WORKSPACE" == *"undefined"* || "$WORKSPACE" == *"null"* ]]; then
    WORKSPACE="${OPENCLAW_HOME}/workspace"
    warn "Could not detect workspace, using default: $WORKSPACE"
else
    # Convert Windows path to Unix if needed
    if [[ "$WORKSPACE" == *"\\"* ]]; then
        WORKSPACE=$(echo "$WORKSPACE" | sed 's|\\|/|g' | sed 's|C:|/c|')
    fi
    # Expand ~ if present
    WORKSPACE="${WORKSPACE/#\~/$HOME}"
    ok "Workspace detected: $WORKSPACE"
fi

SKILLS_DIR="${WORKSPACE}/skills"

###############################################################################
# STEP 2 — Copy skill to the workspace skills directory
###############################################################################
info "[2/8] Installing job_auto_apply skill..."

mkdir -p "${SKILLS_DIR}/job-auto-apply"

if [[ -f "${PROJECT_DIR}/skills/job-auto-apply/SKILL.md" ]]; then
    cp -f "${PROJECT_DIR}/skills/job-auto-apply/SKILL.md" "${SKILLS_DIR}/job-auto-apply/SKILL.md"
    ok "Copied SKILL.md to ${SKILLS_DIR}/job-auto-apply/"
else
    fail "SKILL.md not found at ${PROJECT_DIR}/skills/job-auto-apply/SKILL.md"
fi

###############################################################################
# STEP 3 — Also add extraDirs as a belt-and-suspenders fallback
###############################################################################
info "[3/8] Adding skills.load.extraDirs fallback..."

# Convert project skills dir to Windows-style path for the JSON config
PROJECT_SKILLS_WIN="C:\\\\Users\\\\${WIN_USER}\\\\Downloads\\\\project\\\\APPLY\\\\job-auto-apply\\\\skills"

node -e "
const fs = require('fs');
const cfgPath = process.argv[1];
let raw = '{}';
try { raw = fs.readFileSync(cfgPath, 'utf8'); } catch {}
const stripped = raw.replace(/\/\/.*$/gm, '').replace(/,(\s*[\]}])/g, '\$1');
let cfg;
try { cfg = JSON.parse(stripped); } catch { cfg = {}; }

// Add skills.load.extraDirs
if (!cfg.skills) cfg.skills = {};
if (!cfg.skills.load) cfg.skills.load = {};

const extraDir = 'C:\\\\Users\\\\${WIN_USER}\\\\Downloads\\\\project\\\\APPLY\\\\job-auto-apply\\\\skills';
if (!cfg.skills.load.extraDirs) {
    cfg.skills.load.extraDirs = [extraDir];
} else if (!cfg.skills.load.extraDirs.includes(extraDir)) {
    cfg.skills.load.extraDirs.push(extraDir);
}

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log('  extraDirs added');
" "$OPENCLAW_JSON"

ok "skills.load.extraDirs set"

###############################################################################
# STEP 4 — Copy AGENTS.md to workspace (standing orders)
###############################################################################
info "[4/8] Writing AGENTS.md to workspace..."

mkdir -p "$WORKSPACE"

cat > "${WORKSPACE}/AGENTS.md" << 'AGENTSEOF'
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

When I say "run job applications" or "apply to jobs":

1. Use the `exec` tool to read the file `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\config.yaml`
2. Use the `exec` tool to read the file `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\companies.yaml`
3. Use the `exec` tool to read `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\logs\applications_log.json` to skip duplicates
4. For each company: Search → Evaluate → Apply (per job_auto_apply skill)
5. Use `browser` tool with `profile="jobsearch"` for ALL browser actions
6. Log every action to `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\logs\applications_log.json`
7. Save screenshots to `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\screenshots\`
8. Report summary when complete

### File Paths (Absolute)

- Config: `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\config.yaml`
- Companies: `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\companies.yaml`
- Log: `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\logs\applications_log.json`
- Screenshots: `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\screenshots\`
- Resumes: `C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\resumes\`

### Boundaries

- NEVER visit URLs outside companies.yaml
- NEVER type passwords or handle logins
- NEVER solve CAPTCHAs
- NEVER exceed rate limits (max 10 per company)
- NEVER submit in dry_run mode
- NEVER modify config.yaml or companies.yaml
AGENTSEOF

ok "AGENTS.md written to ${WORKSPACE}/AGENTS.md"

###############################################################################
# STEP 5 — Ensure browser config is correct for Brave Profile 6
###############################################################################
info "[5/8] Configuring browser for Brave Profile 6 (jobsearch)..."

node -e "
const fs = require('fs');
const cfgPath = process.argv[1];
const winUser = process.argv[2];

let raw = '{}';
try { raw = fs.readFileSync(cfgPath, 'utf8'); } catch {}
const stripped = raw.replace(/\/\/.*$/gm, '').replace(/,(\s*[\]}])/g, '\$1');
let cfg;
try { cfg = JSON.parse(stripped); } catch { cfg = {}; }

// Browser config
if (!cfg.browser) cfg.browser = {};
cfg.browser.enabled = true;
cfg.browser.headless = false;
cfg.browser.defaultProfile = 'jobsearch';
cfg.browser.executablePath =
    'C:\\\\Program Files\\\\BraveSoftware\\\\Brave-Browser\\\\Application\\\\brave.exe';

if (!cfg.browser.profiles) cfg.browser.profiles = {};
cfg.browser.profiles.jobsearch = {
    driver: 'existing-session',
    attachOnly: true,
    userDataDir: 'C:\\\\Users\\\\' + winUser + '\\\\AppData\\\\Local\\\\BraveSoftware\\\\Brave-Browser\\\\User Data',
    color: '#FB542B'
};

// Ensure gateway.mode is local
if (!cfg.gateway) cfg.gateway = {};
cfg.gateway.mode = 'local';

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log('  Browser + gateway.mode updated');
" "$OPENCLAW_JSON" "$WIN_USER"

ok "Browser → Brave Profile 6 (jobsearch), gateway.mode → local"

###############################################################################
# STEP 6 — Restart gateway to pick up all changes
###############################################################################
info "[6/8] Restarting gateway..."

$OC gateway restart 2>/dev/null || true
sleep 5

# Check if running
if $OC gateway status 2>/dev/null | grep -qi "running\|online\|listening"; then
    ok "Gateway is running"
else
    info "Starting gateway fresh..."
    $OC gateway run &>/dev/null &
    sleep 5
    ok "Gateway started in background"
fi

###############################################################################
# STEP 7 — Add cron job (now that gateway is running)
###############################################################################
info "[7/8] Adding cron job..."

$OC cron remove --name "daily-job-apply" 2>/dev/null || true
sleep 2

$OC cron add \
    --name "daily-job-apply" \
    --cron "0 9 * * 1-5" \
    --timeout-seconds 3600 \
    --message "Execute job auto-apply per standing orders. Use the job_auto_apply skill. Read config.yaml and companies.yaml from C:\Users\Annanya\Downloads\project\APPLY\job-auto-apply\. Use browser with profile jobsearch. Process all 13 companies. Log results. Report summary." \
    2>/dev/null \
    && ok "Cron job added: daily-job-apply (weekdays 9 AM)" \
    || warn "Cron job failed — you can add it from the dashboard chat instead"

###############################################################################
# STEP 8 — Verify and print dashboard URL
###############################################################################
echo ""
info "[8/8] Final verification..."
echo ""

info "Skills check:"
$OC skills list 2>/dev/null | grep -i "job_auto_apply" && ok "job_auto_apply skill is READY" || warn "Skill may need a gateway restart"

echo ""
info "Gateway:"
$OC gateway status 2>/dev/null || warn "Check gateway manually"

echo ""
info "Dashboard URL:"
$OC dashboard --no-open 2>/dev/null || warn "Get URL manually: pnpm openclaw dashboard --no-open"

echo ""
info "=============================================="
info "  ALL DONE — What To Do Now"
info "=============================================="
echo ""
echo "  1. Open the Dashboard URL in your browser"
echo ""
echo "  2. BEFORE your first run, prepare Brave:"
echo "     a. Open Brave Browser → switch to Profile 6 (jobsearch)"
echo "     b. Go to: brave://inspect/#remote-debugging"
echo "     c. Toggle 'Discover network targets' ON"
echo "     d. Keep Brave open and running"
echo ""
echo "  3. Fill in your config:"
echo "     Edit: ${PROJECT_DIR}/config.yaml"
echo "     Put resumes in: ${PROJECT_DIR}/resumes/"
echo "     Set dry_run: true for first test"
echo ""
echo "  4. In the OpenClaw dashboard chat, type:"
echo '     "Run job applications"'
echo ""
echo "  5. The agent will:"
echo "     → Read your config.yaml and companies.yaml"
echo "     → Open Brave Profile 6 via the browser tool"
echo "     → Visit each of the 13 career sites"
echo "     → Search for matching jobs"
echo "     → Apply (or queue for approval if auto_mode: false)"
echo ""
ok "You're ready to go!"
