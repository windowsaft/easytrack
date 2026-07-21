# UI spec — Verlauf & Profile (design handoff)

> **Update (2026-07-21):** the design rework from `Calories Tracker App Design.zip`
> (turn 7) has since been implemented — Profil direction 7a (with the original
> three-`StatTile` "DEINE ZIELE" overview kept per request), a built **Verlauf**
> screen (kcal-vs-Ziel bars, adherence/deviation tiles, macro-split, water/
> activity, weight-trend card), extra Gewicht range chips, a coral safety-factor
> row and a rounded ÜBERNEHMEN button. The "blank placeholder" notes below are
> historical.

A snapshot of the **current** layout, elements, data and settings for the
**Verlauf** and **Profile** areas, so the UX/visuals can be reworked in a design
pass. Everything below is what the code renders today (2026-07-20); "Gaps" call
out what is missing or provisional.

The app is **German, dark-only, phone-first** (drawn for ~360–380 px wide). The
four bottom-nav destinations are **Tagebuch · Rezepte · Verlauf · Profil**, with
a raised centre "+" button between them.

---

## Design language (shared tokens)

Source of truth: `lib/core/ui/app_theme.dart` and the shared widgets in
`lib/core/ui/widgets/` (`bold_controls.dart`).

**Palette (hex):**

| Token | Hex | Use |
|---|---|---|
| `bg` | `#0C0D0A` | screen background (near-black) |
| `surface` | `#15170F` | cards, list rows |
| `surfaceAlt` | `#22251A` | tile-icon backgrounds, gauge track |
| `bar` | `#12140C` | bottom action bars |
| `selectedRow` | `#191C11` | a row reached-from / selected (with a 3 px lime left border) |
| `lime` | `#C6FF3A` | **primary accent** (calories, CTAs, selection) |
| `coral` | `#FF5A3C` | burned calories / "safety factor" / delete |
| `water` | `#3FB6E6` | hydration |
| `carbs` | `#F2A93B` · `protein` `#FF5A3C` · `fat` `#7C9CFF` | macro accents |
| `text` | `#F2F3EC` · `textMute` `#8A8F7C` · `textFaint` `#6A7058` | text tiers |
| `stroke`/`strokeDashed` | `#22251A`/`#2C3020` | hairlines, dashed "empty" borders |

**Type:** two families. **Anton** (single weight) for every numeral and section
heading; **Space Grotesk** (300–700) for body. Cards & rows are **square (radius
0)** by design — the squareness is the signature. Header icon buttons use radius
14. Screen horizontal padding is **20 px**; stacked rows sit **2 px** apart.

**Shared widgets** used across these screens: `BoldHeader` (overline + Anton
title + optional leading/trailing 44×44 icon buttons), `SectionHeader` (Anton
heading + optional right caption), `StatTile` (label + big Anton value + coloured
3 px left border), `BoldListRow` (icon · label/subtitle · value/trailing ·
chevron), `BoldChip` (pill, lime when selected), `BoldToggle` (44×26 lime
switch), `PrimaryButton` (lime), `OutlineActionButton`, `DashedActionChip`,
`TileIcon` (42 px rounded icon tile).

---

## PROFIL  (`lib/features/profile/profile_screen.dart`)

Top-level tab. Scrolling `ListView`, top inset only (the nav bar owns the
bottom). No back button (it is a root tab).

**1. Header** — `BoldHeader`, title **"PROFIL"**. No leading/trailing.

**2. Identity card** (`_IdentityCard`) — full-width `surface` card, tappable →
opens *Körperdaten* (edit). Contents:
- 66 px circular avatar, lime 2 px border, Anton **"ET"** monogram (no real
  avatar/photo system exists).
- Title **"Dein Profil"** (Grotesk 19/700).
- Subtitle: **"LOKAL · KEIN KONTO"** until a weight exists, then **"AKTUELL {kg}
  KG"**.
- Trailing `edit` icon.

**3. "DEINE ZIELE"** — `SectionHeader` with a right caption **"BERECHNET"** or
**"MANUELL"** (whether the calorie target is auto-computed or user-set). Below,
a row of three `StatTile`s:
- **KALORIEN** — `{kcal}` + suffix " kcal", accent **lime**. From today's target
  (fallback 2000).
- **WASSER** — `{litres}` + " L", accent **water**. From target water (fallback
  2000 ml).
- **FAKTOR** — `{0,80}` (activity safety factor), accent **coral**.

**4. "MEHR"** — `SectionHeader`, then `BoldListRow`s:
- **Körperdaten & Ziel** (icon `straighten`) — "Kalorienziel aus Größe, Gewicht
  & Alter berechnen" → *Körperdaten* screen.
- **Gewicht** (icon `monitor_weight`) — "Verlauf erfassen und den Trend
  verfolgen" → *Gewicht* screen.
- **Einstellungen** (icon `settings`) — "Ziele, Sicherheitsfaktor, Anzeige" →
  *Einstellungen* screen.
- **Datenquellen & Lizenzen** (icon `description`) — "BLS 4.0 · CC BY 4.0" →
  native license page.

**Data sources:** `currentTargetProvider` (kcal/water/isAuto),
`safetyFactorProvider`, `latestWeightProvider`.

**Gaps / notes for design:** the identity card is a placeholder monogram — there
is no name, no avatar, no streak, no weight-goal progress (the handoff had these
but they were dropped as un-backed data). "DEINE ZIELE" duplicates numbers that
also live in Einstellungen. This screen is functional-but-plain and is the main
target for a visual pass.

### Sub-screen: Körperdaten  (`profile_edit_screen.dart`, title "DEIN KÖRPER")

Own screen with a back button; bottom sticky preview bar. Feeds the Mifflin–St
Jeor TDEE calc.
- **GESCHLECHT** — two `BoldChip`s: *Männlich* / *Weiblich*.
- Row of three number fields: **Alter** (Jahre) · **Größe** (cm) · **Gewicht**
  (kg).
- **AKTIVITÄT** — five selectable rows (`_ActivityRow`), each a label + hint +
  an Anton **"×{factor}"** on the right, lime left-border when selected:
  Kaum Bewegung ×1.2 · Leicht aktiv ×1.375 · Mäßig aktiv ×1.55 · Sehr aktiv
  ×1.725 · Extrem aktiv ×1.9.
- **ZIEL** — three `BoldChip`s: *Abnehmen* / *Halten* / *Zunehmen*; when not
  "Halten", a rate field appears (kg pro Woche).
- **Sticky bottom bar** (`_PreviewBar`): live **"{kcal} kcal — EMPFOHLENES
  ZIEL"** + lime **"ÜBERNEHMEN"** button. Disabled until inputs are complete.

### Sub-screen: Einstellungen  (`settings_screen.dart`, title "EINSTELLUNGEN")

Own screen with back button. Grouped `BoldListRow`s (each group has a small
Anton `_GroupHeader`):
- **ZIELE** — Tageskalorien `{n} kcal` · Makro-Verteilung `{c}/{p}/{f} g` ·
  Wasserziel `{n} ml` · Glasgröße `{n} ml`. Each opens a minimal number/edit
  sheet.
- **AKTIVITÄT** — Sicherheitsfaktor (highlighted row, Anton value, opens a
  factor sheet) · "Aktivität erhöht Budget" (`BoldToggle`).
- **EINHEITEN & ANZEIGE** — Einheiten `Metrisch` (static) · Design `Dunkel`
  (static). *Both are display-only, not yet changeable.*
- **PRODUKTDATEN** — Region (`Deutschland`/`DACH`/`Weltweit`, opens a chooser
  sheet) · Produktdatenbank (Open Food Facts install/update state; tap
  downloads/updates the pack).
- **DATEN & RECHTLICHES** — Datenquellen (opens a sheet with the BLS CC BY 4.0
  and OFF ODbL attributions) · Lizenzen (native license page).

**Gaps:** Units and theme are inert placeholders. The edit sheets are
deliberately plain ("not yet designed" per the handoff) — prime candidates for a
design pass.

### Sub-screen: Gewicht  (`lib/features/weight/weight_screen.dart`, title "GEWICHT")

Own screen with back + a header "+" (add weight). This is the closest thing to a
"Verlauf" that exists today.
- **Summary row**: big Anton **current weight** + " kg" on the left; on the
  right, the signed **change over the selected range** (e.g. "−1,4" / "90 TAGE").
- **Range chips**: *30 Tage* / *90 Tage* / *Alle* (`BoldChip`, three across).
- **Trend chart** (fl_chart `LineChart`, 220 px): scattered raw weigh-ins (faint
  dots) + a smoothed lime trend line with a faint fill. Placeholder text when
  fewer than two points in range.
- **EINTRÄGE** list: one row per day (weekday-date · signed delta from the
  previous entry · Anton kg), swipe-left to delete, tap to edit.
- **Add/edit sheet**: a day stepper (‹ date ›, capped at today) + a kg field +
  SPEICHERN.
- **Empty state**: icon + "Noch kein Gewicht erfasst" + a full-width CTA.

---

## VERLAUF  (`lib/features/shell/home_shell.dart` → `_Placeholder`)

**Currently a blank placeholder.** The third nav tab renders only: a centered
`insights` icon, the Anton title **"VERLAUF"**, and the note *"Auswertungen
folgen, sobald mehr Tage erfasst sind."* There is **no real screen** here yet —
this is the biggest greenfield for design.

**What data already exists to build it from** (all local, already in the DB /
providers):
- **Diary history** — `diary_entries` (per-day, per-meal kcal + protein/carbs/fat
  snapshots). Day summaries via `daySummaryProvider(day)`; a day carries
  `consumed` (kcal + macros), `budgetKcal`, `remainingKcal`, water total,
  activity kcal.
- **Targets over time** — `targets` is history-preserving (a row per change), so
  "eaten vs target" is honest for any past day.
- **Water** — `water_log` per day.
- **Activity** — `activity_entries` per day (kcal burned × safety factor).
- **Weight** — `weight_log` + the `WeightSeries` domain (change, min/max, moving
  average) already powering the Gewicht screen's chart.

**Suggested scope for a Verlauf design** (not yet built — for the design pass to
shape): a period switcher (Woche/Monat), a calories-vs-target trend, macro split
over time, adherence/streak, water & activity summaries, and a weight-trend card
that reuses the Gewicht chart. The chart style to match is the Gewicht
`LineChart` (lime line, faint fill, faint dotted scatter, minimal axes).

**Design constraints to honour:** dark-only; square cards; Anton for all
numbers/headings; lime = primary/calories, coral = burn, water = hydration,
carbs/protein/fat = `#F2A93B`/`#FF5A3C`/`#7C9CFF`; 20 px screen padding; top-inset
only (nav bar owns the bottom); German copy.

---

## Recent QC changes already applied (context for the design pass)

- Hydration meter: no "+" button; 8 cups/row, size from Settings, an empty
  buffer row appears when a row fills.
- Meal rows: a full swipe opens search directly (no button tap).
- Rezepte: the centre "+" button creates a recipe on that tab (no header add).
- Quick-Eintrag: now also takes carbs/protein/fat.
- Meal detail: back arrow removed (FERTIG exits).
