# Victoria 3 Mechanics Study — Replication Reference for SwiftHistoria Living World

Distilled from the official Paradox wiki (vic3.paradoxwikis.com) — Economy,
Politics, Warfare, Diplomacy, Events, AI — with a final section mapping each
system to the lightweight implementation in `NativeLivingWorldEngine.swift` /
`NativeLivingWorldTick.swift`.

---

## 1. Economy

### 1.1 Buildings & production methods
- Buildings are the productive unit: they employ pops, consume input goods,
  produce output goods, and pay wages/dividends. Subsistence farms employ pops
  not hired elsewhere (the "default" building every state has).
- **Production methods** toggle per-building: they change inputs/outputs
  (e.g. a farm can use no fertilizer → less grain, or adopt fertilizer → more
  grain but an input good is required).
- Buildings have a **cash reserve**: when profitable they save; when
  unprofitable they dip into reserves, cut wages, and finally fire workers.

### 1.2 Goods
- Categories: **Staple** (grain, wood, iron…), **Luxury** (luxury clothes 60,
  luxury furniture 60, coffee…), **Industrial** (iron 40 base, steel 60,
  tools, engines, electricity), **Military** (small arms, artillery, tanks),
  plus **Prestige goods** (e.g. British-calico).
- Every good has a **base price** (grain 20, wood 20, iron 40 in the wiki
  examples). Prices are expressed in £ per unit.

### 1.3 Market & price discovery (the core formula)
All trades flow through one **national market**; there is no direct
producer→consumer matching. Producers always sell their full output; buyers
always fill their orders; only *prices* adjust.

```
price = base × [ 1 + 0.75 × clamp( (BUY − SELL) / min(BUY, SELL), ±1 ) ]
```

- BUY = total buy orders, SELL = total sell orders across the market.
- Bounds: price ∈ **[base × 0.25, base × 1.75]** (−75% … +75% of base).
- Worked example (wiki): wood base 20; 100 buy / 120 sell orders →
  price = 20 × (1 − 0.15) = **17** (15% below base).
- Asymmetry note (wiki): excess sell orders create extra economy value
  (max +20.87% at −39.56% price); excess buy orders destroy value.

### 1.4 Market access
- Per-state **market access = infrastructure / infrastructure usage** (75%
  base impact scaling). Low access reduces the state's effective orders on
  the national market and widens the local price deviation. This is how
  backwards regions stay poor despite the national market.

### 1.5 Employment, wages, GDP
- Buildings hire from qualifying pops; wages are set by buildings and rise
  when they compete for labor or earn better profits.
- Pops earn wages + dividends; dependents earn a fraction.
- GDP is the sum of the value of all goods and services produced (buildings'
  output valued at market prices).

### 1.6 Treasury: taxes, debt, interest, bankruptcy
- Budget is **weekly**: income from taxes (per-capita head taxes at level 0–5,
  proportional taxes, tariffs) minus expenses (government wages, buildings'
  goods purchases, military).
- **Gold reserve**: surplus accumulates as cash up to a limit; deficit drains
  it. Once empty, deficit automatically takes **loans** against national
  credit; loans charge **weekly interest** (base rate modified by
  modifiers like Financial Prudence −20% or Declared Bankruptcy +50%).
- Surpluses auto-pay loan principal. **Default** triggers when interest can't
  be paid; **declaring bankruptcy** erases debt but cancels construction,
  wipes building cash reserves, and spikes interest rates.

### 1.7 Standard of living (SoL), needs, strata
- SoL 1–99 displayed in bands (e.g. Wealthy 40–49). Driven by pop **wealth**,
  which grows at `0.2 × (income − 1.02 × next-level needs cost)` — pops level
  up when income exceeds the cost of the next needs package.
- **Needs** are packages of goods per 10k pops per wealth level: simple food →
  basic needs → luxury needs as wealth rises (luxuries have demand multipliers).
- **Strata** (lower/middle/upper) set expected SoL from profession + literacy;
  SoL below expectation breeds **radicals**; above breeds **loyalists**.

---

## 2. Politics

### 2.1 Interest groups (IGs)
- Every pop is attracted to IGs (Industrialists, Landowners, Trade Unions,
  Armed Forces, Intelligentsia, Devout, …) by profession, wealth, religion,
  literacy.
- **Clout** = share of national political strength (0–100%). Classification:
  **powerful / influential / normal / marginalized**. Marginalized when
  clout < **4%**; influential again above **5%**. IGs in government (and the
  ruler's IG) can never be marginalized.
- **Approval**: −2 … +2 scale (Strongly Disapprove → Strongly Approve),
  driven mainly by stances on laws and by loyalists/radicals. Angry IGs add
  to revolution chance; happy ones legitimize the government.

### 2.2 Government & legitimacy
- Government = coalition of IGs in power. **Legitimacy 0–100** with levels
  (e.g. Alarmed <25, Low 25–49, Moderate 50–74, High ≥75) — computed from
  the share of governed clout, whether government includes >50% of total
  clout, size of the coalition, and approval of member IGs.
- Low legitimacy slows law enactment and weakens authority.

### 2.3 Laws & enactment
- Law categories: power structure, economy, human rights, migration…
- Enactment is a **weekly roll** with four outcomes: **advance / stall /
  debate / fail**; success chance driven by government support and legitimacy.
  An IG in government (or a popular movement) must sponsor the law.

### 2.4 Elections & voting
- With suffrage laws, elections occur on a cycle (e.g. every 4 years):
  campaign journal entry → interest-group attractiveness decides votes →
  new government forms from the result (parties are IG coalitions).

### 2.5 Radicals & loyalists, movements
- Radicals (below expected SoL, discriminated, recent war losers) reduce
  government stability and feed **political movements**; sustained movements
  can launch revolutions (civil war splitting the country's forces).

---

## 3. Warfare (abstract, no unit control)

### 3.1 Fronts
- On war start, a **front is auto-created at every land border** between the
  belligerent sides. Fronts merge/split as countries join or borders open.
- Players never move units; they assign **generals** (each leading an army
  blob) to a front with one of three stances: **Advance** (attack),
  **Defend** (hold), **Stand Ground** (avoid battles, deny objectives).

### 3.2 Battles
- Generals on opposing fronts with aggressive stances trigger **battles**:
  offensive/defensive values (e.g. Skirmish Infantry 25 offense / 25
  defense) sum by unit type + general trait/advantage rolls → casualties →
  attacker advances (progress toward occupation) or is repelled.
- Battles run over days/weeks with advance-bar progression; losing side
  retreats. Occupation = controlling enemy territory toward **war goals**.

### 3.3 Naval invasions
- Require admirals + flotillas; take prep time, create a new front on
  landing; vulnerable during embarkation.

### 3.4 War exhaustion & peace
- Both sides accumulate **war exhaustion** (casualties, occupied territory,
  blockade). High exhaustion forces acceptance of peace; a side at 100% can
  be forced to capitulate to all war goals.
- **Peace deals** transfer the wargoal (states, treaties, humiliation,
  reparations). Losing wargoals awards **infamy** to the victor.

### 3.5 Infamy
- Infamy (0–100+) from starting plays/conquering: makes you a pariah,
  enables other countries to join coalitions against you, and at 100+
  triggers great-power intervention rights.

---

## 4. Diplomacy

### 4.1 Relations & pacts
- **Relations −100…+100** (hostile → cordial → amicable); drift and event
  driven. Pacts: **Alliance, Defensive Pact, Trade Agreement,
  Non-aggression Pact, Duel** (great powers), **Treaties** (custom
  obligations like debt takeover, port access).
- **Subjects**: puppet/dominion/protectorate/tributary with obligations.

### 4.2 Diplomatic plays (the crisis system)
- Demands are pressed via a **play**: initiate → **escalation stages**
  (opener → diplomatic maneuvering → crisis → ultimatum → war).
- **Maneuvers** (by rank) let you add wargoals or **sway** third countries
  into your side by offering promises (obligations, territory, recognition).
- Backing down at ultimatum grants the demanded wargoal without war (plus
  infamy); refusing → war with all committed participants.

---

## 5. Events & content

- Three kinds: **story events** (narrative chains with options),
  **currency events** (resource rushes like gold/oil), **journal entries**
  (long-running national goals with progress bars, e.g. Expand the Oil
  Industry → completion events grant modifiers like +33% Oil Extractors
  Throughput for 5 years).
- Events have **trigger conditions** (state/country predicates) and fire
  either immediately (`is_triggered_only`) or via weighted MTTH
  (mean-time-to-happen) pulses. Options apply scoped effects; chains via
  "triggered by completing X".
- Feel: common dispatch-level events should be frequent and mild; story
  chains rare and consequential.

---

## 6. AI countries

- AI reads the same state: **AI strategies** (country-level postures,
  e.g. acquire states, protect regions, industrialize) combined with
  **attitudes** toward other countries (cautious, domineering, belligerent,
  protective) driven by relative power, relations, infamy, borders.
- Attitudes gate actions: no war declaration unless attitude + strength
  favor it; alliances proposed when attitudes and threat align.
- AI builds per strategy: agrarian → industry focus per literacy/laws;
  it keeps taxes near balance and adjusts by treasury trend.

---

## 7. Lightweight replication guidance (as implemented)

| Vic3 system | Living World implementation | Fidelity notes |
|---|---|---|
| Market price formula | `LWMarket.resolveDay` — daily drift `imbalance × base × 2%` clamped to **base ±75%** (same bound as Vic3's closed-form price) | Vic3 computes the price directly from order ratio; LW moves price toward the bound by imbalance — same bounds, simpler dynamics |
| Goods | 9 goods across staple/luxury/industrial/military categories with base prices 20–80 | Matches category structure; no prestige goods |
| Buildings & inputs | `LWBuildingType` input→output chains (steel needs minerals+lumber, etc.), staffing, infrastructure efficiency | No per-building cash reserves; country treasury absorbs P&L |
| Treasury | Daily `taxes (pop × taxLevel × 0.02) − (fixed + spendingLevel)`, deficits become debt and radicals | No weekly cadence (daily instead); no interest yet — debt is interest-free |
| SoL | Drifts toward `8 + spending×6 + min(10, revenue×0.02) − radicals×4` | Proxy for wealth-driven SoL; strata recorded |
| Interest groups | Six IGs with clout/approval/inGovernment; clout derived from industrialization | No laws/enactment/elections yet — hooks exist (`government.electionDueDay`, `enactedReforms`) |
| Radicals | Grow on deficits, crises, lost wars; drag SoL and stability | Matches Vic3 direction (below-expected SoL → radicals) |
| Fronts & war | One front per war with `progress −100…100`, push = strength ratio × intensity × mobilization; exhaustion accrues both sides; peace at exhaustion >70 or \|progress\| >80 with transfer of treasury + infamy +8/+12 | Vic3's multi-front general battles abstracted to front progress; no unit types |
| Relations & pacts | −100…100 symmetric-ish (adjustRelation mirrors 50%), alliances feed front strength (+10% per ally) and auto-join | Diplomatic plays abstracted to instant declarations + infamy |
| Infamy | +12 declaration, +8 victory; gates AI aggression (expansionists stop at 60) | No coalitions yet |
| Events | Daily flavor 30% (mild), weekly crisis 2% (moderate), war/peace/alliance records (rare, severe) | Vic3 MTTH replaced with seeded daily rolls; chains = future work |
| AI brains | 4 strategy brains (Balanced/Expansionist/Turtle/Opportunist) reading fiscal balance, threats, relations | Vic3 attitudes simplified to strategy + threat heuristics |

### Daily tick order (implemented in `LivingWorldTick.advanceDay`)
1. Brains issue orders (per country, sorted by code — deterministic).
2. Production: outputs supply the market, inputs demand, wages paid.
3. Treasury: taxes − spending; deficits → debt + radicals; SoL drift.
4. Price discovery (bounded).
5. Diplomacy drift (pacts nudge relations).
6. Wars: front math, exhaustion, peace evaluation.
7. Order execution: taxes/spending adjust, construction, wars, alliances.
8. Procedural events (daily/weekly/rare).
9. History append + presentational cap (400).

### What to cut (done) vs add later
- **Cut**: per-building cash reserves, unit types, naval invasions,
  law enactment rolls, elections, subjects, diplomatic play escalation
  stages, prestige goods, interest on debt.
- **Next additions by value**: (1) interest on debt + bankruptcy, (2)
  law enactment with IG approval, (3) election cycle using
  `electionDueDay`, (4) multi-front wars, (5) MTTH-style event chains.

All randomness is seed-derived (`LWRNG` on FNV-1a), so the tick order above
is reproducible — verified by `LivingWorldEngineTests`.
