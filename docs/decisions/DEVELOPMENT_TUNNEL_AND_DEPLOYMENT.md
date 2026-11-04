# Deployment context and public-ingress decision (2026-10-27)

**Status:** Working architecture note; not a production deployment plan.

- **Current reality:** Patchwrit Phoenix is developed locally and **is not yet publicly deployed**. A temporary `cloudflared` quick tunnel allows remote Fly Machines to call back into the local Phoenix endpoint during development. The tunnel is not the intended public ingress.
- **Risk interpretation:** While active, a tunnel exposing the Phoenix origin may also expose unauthenticated `/analyses` pages and billable analysis actions. Short-lived/unguessable URLs reduce exposure but do not constitute authentication. This is a development exposure to manage, not proof that the application has been launched publicly.
- **Near-term option:** Deploy Phoenix using Fly's provided `*.fly.dev` hostname and HTTPS; a purchased domain is **not required** to deploy or receive callbacks.
- **Later:** Buy a Patchwrit domain and configure permanent DNS/HTTPS.
- **Before public access:** Restrict analysis creation and other billable operations, including LiveView websocket routes. Separate worker callback ingress from browser access where practical.
- **Scope decision:** Do not block hackathon tribunal work on domain purchase or a full account system. Revisit ingress/security when switching from local development to a reachable hosted service.

Related: [API review PR #27](https://github.com/Patchwrit/patchwrit-api/pull/27), finding A001.
