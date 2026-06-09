# Clicky × AG-CTO — Run & Test Runbook

End-to-end diagnosis loop: **Clicky (Mac app) → Worker → AgentGateway**.
Default = fully local (no tunnel, repeatable).

## URLs
| Service | URL |
|---|---|
| AgentGateway (diagnose brain) | http://localhost:3000/api/diagnose |
| Local Worker (`wrangler dev`) | http://localhost:8787/diagnose |
| Deployed Worker | https://clicky-proxy.mihirsanghavi.workers.dev |

Branch (both repos): `feature/ag-cto-diagnose-bridge`

---

## Terminal 1 — AgentGateway (:3000)
```bash
cd ~/Documents/GitHub/agentgateway-v2
npm run dev -- -p 3000
```
- Uses the key in `agentgateway-v2/.env.local` (`ANTHROPIC_API_KEY`, `AGCTO_LLM_MODEL`).
- Offline/no-key instead: `AGCTO_LLM_STUB=1 npm run dev -- -p 3000`
- Check: `curl -s localhost:3000/api/diagnose | python3 -m json.tool` → `model.configured: true`

## Terminal 2 — Local Worker (:8787)
```bash
cd ~/Documents/GitHub/clicky/worker
npx wrangler dev --port 8787
```
- Wait for `Ready on http://localhost:8787`.
- Reads `AGENTGATEWAY_DIAGNOSE_URL = http://localhost:3000/api/diagnose` from `wrangler.toml`.
- The missing chat/TTS secret warnings are fine — `/diagnose` needs none.

## Terminal 3 — Worker logs (tail)
Local Worker prints requests in Terminal 2. To tail the **deployed** Worker instead:
```bash
cd ~/Documents/GitHub/clicky/worker
npx wrangler tail
```

## Xcode — point the app at the local Worker, then run
1. **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables → +**
2. Name: `CLICKY_DIAGNOSE_URL`  Value: `http://localhost:8787/diagnose`
3. Close → **Cmd + R**

(Only `/diagnose` goes local; chat/TTS/transcription still use the deployed Worker. Untick the env var to revert.)

---

## Test
Hold **Control + Option** and say:
> "diagnose this — access denied calling Bedrock in us-east-1."

Trigger phrases (anything else → normal Claude companion):
`diagnose` · `what's wrong` · `debug this` · `why is this failing` · `help me fix` · `what's causing`

Expect:
- 🔊 spoken diagnosis
- Xcode console: `🩺 AG-CTO diagnosis: source=… backend=…`
- Terminal 2: a `POST /diagnose` line
- Terminal 1: the request landing

## Demo use cases

Say each line to Clicky (hold **Control + Option**). Each leads with a trigger
phrase so it routes to AG-CTO. With Bedrock/a real model the answers are live;
with `AGCTO_LLM_STUB=1` they're deterministic `[stub]` text (the loop still proves
out). The point of each: a screen-only assistant guesses, AG-CTO names the
*systems it would inspect*.

**1. Cloud IAM / model access (AWS Bedrock)**
> "**diagnose this** — AccessDeniedException calling InvokeModel on Bedrock in us-east-1."
- Would inspect: Bedrock model-access state · the IAM role policy
- Expect: model access not enabled and/or missing `bedrock:InvokeModel`; fix names both.

**2. Provider account flag (ElevenLabs)**
> "**what's wrong** — ElevenLabs returns 401 detected_unusual_activity, free tier disabled."
- Would inspect: ElevenLabs billing/subscription · which key is wired in
- Expect: the flag overrides credit balance → upgrade to paid, drop the VPN, don't make another free account.

**3. Deploy / secret confusion (Cloudflare)**
> "**debug this** — wrangler deploy doesn't list my secrets, did they save?"
- Would inspect: the `wrangler deploy` output · `wrangler secret list`
- Expect: deploy omits secrets by design; verify with `secret list`; `secret put` overwrites — no delete needed.

**4. Runtime / infra (Postgres)**
> "**why is this failing** — psql FATAL: remaining connection slots are reserved for superuser."
- Would inspect: `pg_stat_activity` · `max_connections` · the pooler config
- Expect: connection-pool exhaustion → add PgBouncer / raise limits / fix a connection leak.

**5. Show the learning (recall from memory)**
Run #1, then say a **reworded** version:
> "**diagnose** bedrock invoke model access denied in us-east-1, can't reach the model."
- Expect: `source: memory` (recalled) with `recall.similarity` — proves the KB learned; no second model call.

## Manual checks (no app)
```bash
# Worker → AgentGateway hop
curl -sX POST localhost:8787/diagnose -H 'content-type: application/json' \
  -d '{"signal":"diagnose this: AccessDeniedException InvokeModel Bedrock us-east-1"}'

# what the KB has learned
curl -s localhost:3000/api/diagnose | python3 -m json.tool
```

## Gotchas
- **"out of credits" spoken** = the diagnose call errored → check the env var is exactly `http://localhost:8787/diagnose` and that you rebuilt after setting it.
- Both local servers stop when you close their terminals; just re-run the commands.
- Don't run `xcodebuild` from the CLI (invalidates TCC permissions) — build via Xcode `Cmd+R`.
