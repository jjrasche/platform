# Implementer kickoff: iPad-native Luanti client via TestFlight

You are the implementer of the Eagle Crest Phase 0 iPad client. This document is your full scope. The reviewer is Jim's main Claude Code session in the platform repo; surface PRs/decisions to him for review.

## Mission

Get a Mineclonia game running on a vanilla iPad, downloaded from a TestFlight link by a non-technical parent, connecting to the existing Luanti server at `play.jimr.fyi:30000`. End-state: parent receives an email, taps a link, app installs, kid plays. No friction.

## Background — read first

- `platform/memory/project_ipad_native_client.md` — the epic, the rejected paths, why TestFlight won
- `platform/memory/project_eagle_crest_vision.md` — the cascade this rolls into
- `platform/memory/reference_luanti_admin.md` — server admin via mineysocket MCP

## Required environment

You need:
1. **A Mac** running recent macOS with Xcode 15+ installed.
2. **A physical iPad** for testing (any A12+ chip, iPadOS 14+).
3. **A USB-C cable** to wire the iPad to the Mac for the dev-cycle.
4. **Apple ID** (Jim's). Free is fine for the smoke-test step. **DO NOT** buy the $99 Developer Program until step 4 below.
5. **Cloned repos:**
   - `luanti-org/luanti` (upstream)
   - `luanti-eagle-crest-ios` (Jim's fork — create if doesn't exist; default branch tracks PR #15451)
6. **Server access:** `play.jimr.fyi:30000` is live (no action needed).

## Build phases — gate each before proceeding

### Phase 1 — Smoke test that PR #15451 actually runs (3-8 hours)

The single biggest unknown: does PR #15451 produce a runnable iPad binary today, or just a buildable iPhoneSimulator scheme?

1. Clone `luanti-org/luanti` master.
2. Fetch PR #15451 (`gh pr checkout 15451` or `git fetch origin pull/15451/head:ios-port`).
3. Rebase on current master. Resolve conflicts.
4. Open the Xcode project from the `build/` directory.
5. Build for iPhoneSimulator first. Confirm clean build.
6. Build for physical iPad device (USB tethered, free Apple ID signing).
7. Sideload via Xcode directly to Jim's iPad (no SideStore needed for direct dev install).
8. Launch the app on iPad. Connect to `play.jimr.fyi:30000`. Login as `jimrasche`.

**Decision gate:** does it run?
- **Yes, runs and renders Mineclonia world:** proceed to Phase 2.
- **Builds but crashes/won't connect:** debug. Common failure modes: ANGLE init errors, Metal shader compilation, network entitlements missing in `Info.plist`. Surface findings to reviewer.
- **Doesn't build:** stop. Surface compile errors to reviewer. Decide whether to invest the 2-4 weeks finishing the port from where sfence left off, or wait for upstream merge.

### Phase 2 — Polish for first TestFlight build (1-3 days)

Assuming Phase 1 ran:

1. **Branding:** App name should be "Eagle Crest" or similar — not "Luanti." Set in `Info.plist` (`CFBundleDisplayName`).
2. **Server pre-fill:** kids should NOT have to type a server address. Hardcode `play.jimr.fyi:30000` as the default in the connect dialog or skip the dialog entirely on first launch. Find the right spot in the Luanti C++ source — likely `src/client/clientlauncher.cpp` or the GUI startup path. Surface the change as an isolated commit on Jim's fork.
3. **Touch UI sanity check:** virtual joystick + dig/place buttons render correctly on iPad screen sizes. Test landscape and portrait.
4. **Audio:** Mineclonia ambient sounds work. Test with iPad muted (silent switch) and unmuted.
5. **Mod set bundle:** Mineclonia + curated mods baked into the binary (no in-app mod browser — Apple guideline 4.7 risk). Confirm the build's mod path is read-only.
6. **App icon + launch screen:** placeholder is fine for first beta. Use Mineclonia's logo if licensing permits, otherwise solid color + "Eagle Crest."

### Phase 3 — Apple Developer Program + TestFlight (1-2 days)

After Phase 2 produces a clean build that runs well on Jim's iPad:

1. **Jim buys $99/yr Apple Developer Program account.** Surface this as a gate to the reviewer — DO NOT spend his money without explicit go-ahead.
2. Configure Xcode signing with the paid Developer team.
3. Create App Store Connect record (no public listing yet — TestFlight only).
4. Archive build → upload via Xcode Organizer or `altool`.
5. Wait for Apple beta-app review (~24hr typical for first build).
6. Once approved, get the **public TestFlight link**.
7. Test the public link from a different Apple ID (Jim's wife's, or a fresh test ID) on a different iPad. Confirm install works without Jim's involvement.

### Phase 4 — Family rollout (ongoing)

1. Email the public TestFlight link to the first 5 families (Jim's kids' friends).
2. Watch for support questions. Common stumbling blocks expected: "what's TestFlight?", "do I need an Apple ID?" (yes, any Apple ID works).
3. Quarterly: re-upload a fresh TestFlight build before the 90-day expiry. Apple sends an automated reminder.

## Hard rules

- **No work in main checkout** — use git worktrees on Jim's fork.
- **Never push to luanti-org/luanti master directly** — if upstream contributions arise, open a PR to luanti-org and discuss with reviewer first.
- **Don't buy the $99 Apple Developer Program until reviewer says go.** Phase 1 smoke test must pass first.
- **Don't roll out to families until Jim says go.** Phase 3 review must complete first.
- **No sideloading via SideStore/AltStore for any user other than Jim's personal smoke test.** This is locked policy — see project memory.
- **All upstream-relevant code stays vanilla** — branding goes in fork. If you find a bug in Luanti core, file an upstream issue, don't carry a private patch indefinitely.
- **Match Jim's voice in any docs you write** — "claim" not "fact", "signal" not "event", quick volley mode in design discussion.

## Decision points to escalate to reviewer

- Phase 1 fail mode (doesn't build, won't run, crashes)
- Apple guideline 4.7 friction (if Apple flags Lua mod system during beta review)
- Anything that requires spending money beyond the $99 Apple Developer fee
- Any architectural deviation from "ANGLE → Metal via PR #15451"
- Any inability to pre-fill the server address (which would break the parent UX)

## Reporting cadence

After each phase:
- Git diff stat
- One-paragraph summary of what worked and what didn't
- The next decision the reviewer needs to make
- A built artifact (screenshot of the iPad running Mineclonia, .ipa file size, TestFlight link, etc.)

Do not silently bundle multiple phases into one report. Reviewer wants to gate each phase explicitly.

## Done criteria for the epic

- A non-technical parent receives an email
- They tap the TestFlight link on their kid's iPad
- They install the app (no Apple ID friction beyond the standard "trust this developer" tap)
- Kid launches it, sees the Mineclonia world, plays for at least 30 minutes without app crash
- Auto-update works the first time Jim pushes a new build

When that flow works end-to-end for one family, the epic is done. Phase 0 enrichment infrastructure is unblocked.
