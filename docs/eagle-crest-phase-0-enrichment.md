# Eagle Crest Phase 0 — After-school enrichment runbook

The pivot (2026-05-05): don't go for the charter first. Run as after-school enrichment for one school year. **No charter. No certified teacher. No facility.** Just kids playing Mineclonia for an hour a day with the Socratic companion logging standards-tagged interactions.

The data IS the charter application.

## Why this de-risks everything

Traditional charter school path:
- Apply to GVSU (months of paperwork, no certainty)
- Recruit certified teacher willing to stake career on unproven model
- Lease facility
- Recruit families before any evidence the model works
- M-STEP scores in year 1 determine whether GVSU non-renews in year 3

Phase 0 enrichment path:
- Run for one school year, no institutional risk
- Collect per-interaction assessment granularity for participating kids
- Compare M-STEP growth vs peers
- If kids show measurably better growth → walk into GVSU year 2 with statistical evidence
- If they don't → know before any institutional risk

## What this requires (infrastructure)

### Platform's deliverables (this repo)

- [x] Luanti server deployed (play.jimr.fyi:30000) — done
- [x] MCP admin server (luanti-admin) — done
- [ ] Voice infrastructure stack — see `project_voice_infra_needed.md` in memory
  - vLLM endpoint on GEX44 with 7B model
  - Streaming TTS (Piper or Coqui)
  - Whisper STT (or expectation of on-device)
- [ ] Per-pod data isolation — when multiple families participate, each family's interactions stay in their own engine instance
- [ ] Backup runbook for student data — interactions are sensitive PII
- [ ] Parent dashboard hosting (HTTP endpoint behind Caddy) — when parent-facing front-end is built

### Agent-platform's deliverables (different repo)

See `agent-platform/docs/prompts/socratic-companion-build.md`. Summary:
- Socratic companion AgentDomain
- Standards-tagged question generation
- Per-student memory continuity
- Voice loop integration

## Pilot structure

### Participants
- 3-5 families to start (Jim's twins + neighbors' kids)
- Multi-age range (target 6-13yo to test pod dynamics)
- Run from one home or shared neighborhood space (not a facility)

### Cadence
- 1 hour/day, 3-5 days/week
- One school year (Sept 2026 → June 2027 if launched on that calendar)
- Mid-year checkpoint (December) — review data, decide if Phase 1 (charter) prep starts

### Hardware per kid
- $30 Onn 4K Plus stick (per Eagle Crest hardware notes) running browser-based Luanti client
- TV they already own
- Phone-as-controller (per `agent-platform/docs/prototypes/luanti-controller.html`)
- One headset/mic for voice loop ($20-40 range)

Total: ~$100/kid one-time. Cheaper than the original $200/kid estimate because we're using the family's existing TV.

### What gets measured
- Time-on-task per kid per day
- Standards-tagged interactions per kid per session
- Mastery trajectory per standard per kid (derived from interaction stream — see student memory schema)
- Kid satisfaction (qualitative, kids report)
- Parent satisfaction (qualitative, monthly check-ins)
- M-STEP growth comparison at end of year (against same-school peers who didn't participate)

## Validation gate (before launch)

Before recruiting families and shipping hardware, do the manual validation step:

1. Jim's kids play Mineclonia for 3 hours
2. Manually map their interactions to Michigan content expectations
3. Confirm the mapping is real
4. If unstructured play doesn't produce standards-aligned interactions, the Socratic companion's job is to INJECT them — that's the architectural commitment

This is an afternoon's work. Don't skip it. The Detroit housing development downstream depends on this validation being real.

## What NOT to do in Phase 0

- **Don't pursue charter authorization.** That's Phase 1 (year 2+).
- **Don't recruit a certified teacher.** Not needed for enrichment. Save the recruitment problem for Phase 1.
- **Don't lease a facility.** Run from homes.
- **Don't build the parent recruitment funnel.** Use existing relationships (Jim's neighbors, friends-of-friends).
- **Don't fundraise.** Hardware is sub-$1K total at 5 families × $100/kid.
- **Don't optimize the dashboard.** Manual reports + per-kid transcripts are enough for year 1.

## What to push hard on

- **Validation gate (manual standards mapping).** Single biggest risk reducer.
- **Companion memory continuity.** This is what makes the experience feel like a tutor instead of a chatbot. If memory doesn't work, kids disengage by week 4.
- **Voice loop latency.** <500ms or kids don't talk to the AI. Test ruthlessly.
- **Parent dashboard granularity.** Data nerds parents are the conversion funnel. They see the dashboard, they see their kid mastered fractions on Tuesday and struggled with area on Wednesday, they want to know why their kid is in 7-hour traditional school when 1 hour of this works.

## Year-end deliverable (for Phase 1 charter application)

After one year of Phase 0:
- Statistical comparison: participating kids' M-STEP growth vs school-year peers
- Sample of standards-tagged interaction transcripts (anonymized)
- Per-kid mastery trajectories with timeline
- Parent + kid testimonials
- Cost analysis: total Phase 0 cost / # kids / # standards practiced

If the comparison is favorable, this packet IS the GVSU charter application. No charter applicant has ever shown up with per-interaction assessment granularity. The data is unprecedented.

If the comparison is unfavorable, you've saved $5M+ and 3 years of effort by not pursuing the charter blindly.

## Connected docs

- `~/.claude/projects/.../memory/project_eagle_crest_vision.md` — full cascade (game→school→community→sovereignty)
- `~/.claude/projects/.../memory/project_voice_infra_needed.md` — what platform provisions
- `agent-platform/docs/prompts/socratic-companion-build.md` — agent-platform's build kickoff
- `agent-platform/docs/roadmap-eagle-crest.md` — earlier roadmap (predates Phase 0 pivot; consult but the pivot supersedes the charter-first ordering)
