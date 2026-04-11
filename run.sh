#!/usr/bin/env bash
###############################################################################
# fix-models.sh — Fix all broken model configurations
# Run from: ~/Downloads/project/APPLY/
###############################################################################
set -euo pipefail

OPENCLAW_REPO="$(pwd)/openclaw"
OPENCLAW_JSON="${HOME}/.openclaw/openclaw.json"
OC="pnpm --dir ${OPENCLAW_REPO} openclaw"

echo "[INFO] Fixing model configuration..."

# Load .env if present
if [[ -f ".env" ]]; then
    set -a
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        val="${val%\"}" ; val="${val#\"}"
        export "$key=$val"
    done < ".env"
    set +a
fi

node -e "
const fs = require('fs');
const cfgPath = process.argv[1];

let raw = '{}';
try { raw = fs.readFileSync(cfgPath, 'utf8'); } catch {}
const stripped = raw.replace(/\/\/.*$/gm, '').replace(/,(\s*[\]}])/g, '\$1');
let cfg;
try { cfg = JSON.parse(stripped); } catch { cfg = {}; }

// ── Env: ensure all API keys are present ──
if (!cfg.env) cfg.env = {};
if (process.env.OPENROUTER_API_KEY)   cfg.env.OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
if (process.env.DEEPSEEK_API_KEY)     cfg.env.DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;
if (process.env.GROQ_API_KEY)         cfg.env.GROQ_API_KEY = process.env.GROQ_API_KEY;

// ── models.providers: configure DeepSeek direct API ──
// This is REQUIRED for deepseek/* model refs to work
if (!cfg.models) cfg.models = {};
if (!cfg.models.providers) cfg.models.providers = {};
cfg.models.providers.deepseek = {
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: '\${DEEPSEEK_API_KEY}',
    api: 'openai-completions',
    models: [
        {
            id: 'deepseek-chat',
            name: 'DeepSeek V3 Chat',
            contextWindow: 131072,
            maxTokens: 8192
        },
        {
            id: 'deepseek-reasoner',
            name: 'DeepSeek R1 Reasoner',
            reasoning: true,
            contextWindow: 131072,
            maxTokens: 8192
        }
    ]
};

// ── agents.defaults: fix model + fallbacks with CORRECT IDs ──
if (!cfg.agents) cfg.agents = {};
if (!cfg.agents.defaults) cfg.agents.defaults = {};

cfg.agents.defaults.model = {
    // Primary: DeepSeek direct (uses YOUR DEEPSEEK_API_KEY, no OpenRouter credits needed)
    primary: 'deepseek/deepseek-chat',
    fallbacks: [
        // Fallback 1: Groq with a CURRENT model (llama-3.3-70b-versatile is alive)
        'groq/llama-3.3-70b-versatile',
        // Fallback 2: OpenRouter DeepSeek (if you add credits later)
        'openrouter/deepseek/deepseek-chat-v3-0324',
        // Fallback 3: OpenRouter free tier
        'openrouter/deepseek/deepseek-chat-v3-0324:free'
    ]
};

cfg.agents.defaults.models = {
    'deepseek/deepseek-chat': {},
    'deepseek/deepseek-reasoner': {},
    'groq/llama-3.3-70b-versatile': {},
    'openrouter/deepseek/deepseek-chat-v3-0324': {},
    'openrouter/deepseek/deepseek-chat-v3-0324:free': {}
};

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log('Model config fixed successfully');
" "$OPENCLAW_JSON"

echo "[INFO] Restarting gateway..."
$OC gateway restart 2>/dev/null || true
sleep 5

echo "[INFO] Testing model probe..."
$OC models status 2>/dev/null || echo "[WARN] Run 'pnpm openclaw models status' manually to verify"

echo ""
echo "=============================================="
echo "  MODELS FIXED"
echo "=============================================="
echo ""
echo "  Primary:    deepseek/deepseek-chat (YOUR DeepSeek API key, no OpenRouter)"
echo "  Fallback 1: groq/llama-3.3-70b-versatile (fast, current model)"
echo "  Fallback 2: openrouter/deepseek/deepseek-chat-v3-0324 (needs credits)"
echo "  Fallback 3: openrouter/deepseek/deepseek-chat-v3-0324:free (free tier)"
echo ""
echo "  Make sure your .env file has a real DEEPSEEK_API_KEY value."
echo "  Get one free at: https://platform.deepseek.com/api_keys"
echo ""
echo "  Reload the dashboard and try chatting again."
echo ""
