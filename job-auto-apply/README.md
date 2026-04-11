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
