# Junto — Profile Page & Badge System Design Brief

**Audience:** Claude Design (or any designer working on the trust surface).
**Goal:** make a stranger's profile communicate enough trust signal to answer *"do I want to go on a real-world outdoor activity with this person?"*

---

## 1. Junto in 60 seconds

Junto is a geolocated outdoor-sports activity coordination app. A user creates an activity (hike, ski tour, climbing session, paragliding, kayak, cycling, etc.) at a specific time and location; other users discover it on a map and ask to join. The product is built around outdoor / mountain sports in France, with users who often don't know each other before showing up at a trailhead together.

### Three pillars
1. **Find / join** — map-based discovery, filters, alerts. Strong already; not the focus here.
2. **Organize** — coordination layer once people are committed: meeting points, transport (carpool), gear, presence validation, peer review. UI work pending separately.
3. **Trust** — the bet that you can show up and meet a stranger who'll be reliable, prepared, and at the level they claim. **This document is about pillar 3.**

The whole product depends on the trust pillar working. If users don't believe the signals they see on a profile, they won't take the leap of joining a stranger's activity.

---

## 2. The trust pillar — what it actually has to do

When a user opens a stranger's profile, they're answering: **"Should I commit a day of my life to going outside with this person?"**

Components of that decision:
- **Reliability** — will they show up, be on time, not bail at the last minute?
- **Behavior** — are they pleasant to be with under stress (weather, fatigue, danger)?
- **Skill / level** — do they actually have the sport experience they claim?
- **Engagement** — are they a real, active member of the community or a ghost account?
- **Specific experience for this activity** — have they done THIS sport before, recently?

The profile page is the surface that has to address all five. It does so via:
- A **reliability score** at the top (single number tied to history of show-ups and no-shows).
- A **badge card** with three sections that communicate distinct trust signals.

---

## 3. Profile page anatomy

| Block | Purpose |
|---|---|
| **Hero** (avatar, display name, reliability ring + tier, age, sports list) | At-a-glance identity + reliability summary |
| **Badge card** (3 sections, deep-dive) | Detailed trust signals — the substance of this brief |
| **Activity history** (sport-by-sport list, optional) | Concrete completed activity record |

Screenshots provided separately show the current state of the hero and the badge card.

---

## 4. Reliability score (separate from badges)

- Shown as a ring on the hero with a tier label (e.g. *"Très fiable"*, *"Fiable"*, etc.) and the numeric score.
- Computed Bayesian-smoothed from the user's history: validated presences, late leaves, no-shows, peer testimony.
- One number, summarizes "do they show up?". Highest-density signal in the profile.
- **Not a badge** — it's the headline, badges qualify it.

---

## 5. The badge card — three sections, three categories of evidence

The card has three sections, each carrying a fundamentally different *type* of evidence. They should not be merged — each answers a different question.

### Section A — **Peer signals** (vouched + warning)

The most direct trust evidence: testimony from people who actually did activities with this user.

**Vouched (positive traits)** — surfaced when ≥5 peers have voted on the trait.
- `punctual` — *Ponctuel* — arrives on time, doesn't keep groups waiting.
- `prepared` — *Préparé* — brings the right gear, knows the route, has the conditioning.
- `conciliant` — *Conciliant* — flexible under group friction, not insistent on their plan.
- `prudent` — *Prudent* — manages risk soundly, doesn't push past safety limits.

**Warnings (negative flags)** — surfaced at ≥5 votes (amber) or ≥15 (red).
- `unprepared` — *Pas préparé* — chronically shows up under-equipped or unfit.
- `aggressive` — *Agressif* — abrasive interpersonal behavior in groups.
- `reckless` — *Imprudent* — takes safety risks others didn't consent to.

**Each peer signal carries:**
- Vote count (5–50+)
- Recency of the most recent vote
- Decay rule on warnings: ~1 vote/month decays automatically with no new flags.

**Trust weight:** highest. Real humans who spent a day with this person said this.

### Section B — **Junto-given awards** (algorithmic)

Computed server-side from completed activity counts. Each award has bronze/silver/gold tiers. Awards surface only when at least bronze is reached.

| Award ID | French label (gold tier) | What it counts | Bronze / Silver / Gold |
|---|---|---|---|
| `joined` | Pilier | Activities joined that someone else organized | 5 / 20 / 50 |
| `created` | Bâtisseur | Activities created (ie. organized themselves) | 5 / 20 / 50 |
| `polyvalent` | (varies) | Distinct sports practiced | 3 / 5 / 8 |
| `aventurier` | (varies) | Multi-day activities completed | 1 / 3 / 5 |
| `aquatique` | (varies) | Outings in water sports (with min distinct sports) | 25 / 50 / 100 |
| `montagne` | (varies) | Outings in mountain sports | 25 / 50 / 100 |
| `route` | (varies) | Outings in road sports (cycling, etc.) | 25 / 50 / 100 |
| `air` | (varies) | Outings in air sports (paragliding, etc.) | 10 / 25 / 50 |

Bronze/silver/gold each have a different French label per award (e.g. joined: *Membre / Régulier / Pilier*).

**Trust weight:** medium. Tells you "this user engages with the platform across these dimensions". Less direct than peer testimony but still concrete behavior. Gold tier means commitment over time.

### Section C — **Sport experience** (per-sport, concrete)

Per-sport row surfaces when the user has ≥3 completed activities in that sport.

For each sport row:
- Total completion count
- Self-declared level (1–4 dots: débutant / intermédiaire / avancé / expert)
- Peer level votes (over / right) — peers who did activities with the user vote on whether the user is at the right level for that sport. Net positive votes = "level confirmed by peers".
- Date of most recent activity + average frequency (e.g. *"2 sorties/mois en moyenne"* or *"1 sortie tous les 4 mois"*)

**Trust weight:** highest *for sport-specific decisions*. If you're considering joining their hiking activity, their hiking row is the strongest signal — count, recency, and peer-corroborated level all together.

---

## 6. The four popups (current state)

Each row in the badge card is tappable and opens a modal with the full evidence. The four popup types map to the three categories above:

| Popup | Triggered by | Carries |
|---|---|---|
| **Vouched** | Tapping a positive peer trait | Trait, count, peer-testimony recency, description of trait meaning |
| **Warning** | Tapping a negative peer flag | Flag, severity (amber/red), description, decay note |
| **Award** | Tapping a Junto-given award row | Award name, tier, concrete count (e.g. *"23 activités rejointes"*), tier progression hint |
| **Sport** | Tapping a sport row | Sport, count, last activity, frequency, peer level votes |

**Where the current popups fall short** (per Scott's read):
- They're competent but not engaging. Visual hierarchy doesn't lead with the trust signal — it leads with the *category framing* (e.g. tier chip on awards) instead of the *evidence* (e.g. concrete count).
- Recency, which decays trust, is buried in small footer text.
- Peer count (the actual testimony number) is shown as a small chip, not as the focal element.
- The four popup types share visual scaffolding but don't share a clear *decision-time grammar* — what should the user see first, second, third?

---

## 7. Design principles for the trust pillar

Pulled from how Scott talks about the product:

1. **Evidence-forward, not gamification.** Bronze/silver/gold are necessary tiers but they shouldn't be the headline of an award popup. The headline should be the underlying behavior the algorithm detected.
2. **Concrete > abstract.** "23 activités rejointes" beats "Tier: Silver". Numbers, dates, frequencies are trust currency.
3. **Recency is part of the signal.** A peer vouch from 2 years ago isn't worth a peer vouch from last month. The design should make staleness visible.
4. **Peer testimony > algorithm > self-declaration**, in that epistemic order. Visual prominence should reflect this.
5. **No social scoring.** Junto explicitly avoids star ratings, leaderboards, kudos. The reliability score is the only single-number trust metric. Badges describe behavior; they don't rank users.
6. **French-first.** All copy, all sport names, all trait labels are written in French. English is fallback.
7. **Visual aesthetic.** Clean, minimal, dark-theme-compatible (most Junto users on dark mode). Lucide icons rather than emoji where possible. Avoid heavy ornament — outdoor app, not a game app.

---

## 8. What's currently shipped (so designer knows the floor)

- Reliability ring + tier label on profile hero ✓
- Badge card with three sections ✓
- All four popup types implemented (modal + content) ✓
- Tier colors: bronze `#B87333`, silver `#9DA9B5`, gold `#E0B040`
- Severity colors: amber `#D49A3F`, red `#C0392B`
- Lucide-react-native icons available; sport-icon set in `constants/sport-icons.ts` (returns emoji per sport key)
- React Native + Expo, dark/light theme via `useColors`
- French + English i18n keys all in place under `badges.*`

The **information architecture** of the badge card is settled and shouldn't be reworked. The three sections stay distinct. What needs design rework: the **popups** specifically — the deep-dive surface where users go to evaluate the evidence behind each row.

---

## 9. Out of scope

- Reliability score visual (already final).
- Hero block (already final — separate session if needed).
- Activity history list.
- Adding new badge types or restructuring categories.
- Animation. Junto is a static-feel app; no shimmer, no motion.

---

## 10. What good looks like

When a user is deciding whether to join a stranger's hiking activity tomorrow, they should be able to:
1. Glance at the profile hero → see reliability tier.
2. Scan the badge card → see if peers vouch for the user, and how recently; see if the user actually does outdoor activities at all; see specifically how much hiking the user has done.
3. Tap the *hiking* sport row → see in one popup: "47 hiking outings, last one 8 days ago, ~2/month, peer-confirmed expert level". That should be enough to decide.
4. Tap a vouched trait → see "12 peers have vouched they're prudent; most recent: 6 days ago. Means: manages risk soundly."

If the popups answer those questions cleanly, the trust pillar works.
