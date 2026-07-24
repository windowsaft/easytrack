# Translating EasyTrack

EasyTrack is built to be translated by anyone — you don't need to know Dart or
build the app. All the text lives in plain JSON files, one per language, under
[`lib/l10n/`](../lib/l10n).

- **`app_en.arb`** — English, the **source** language. Every other language is
  translated from this one. It also carries a short description of each string
  (the `@key` entries) so you know the context.
- **`app_de.arb`** — German.
- **`app_<code>.arb`** — one file per language, named with its
  [ISO 639-1 code](https://en.wikipedia.org/wiki/List_of_ISO_639_language_codes)
  (`fr` for French, `es` for Spanish, `it` for Italian, …).

> A self-hosted **Weblate** instance is planned, which will let you translate in
> a web browser with no Git at all. Until then, the pull-request flow below is
> the way in — and it stays valid afterwards for anyone who prefers editing files
> directly.

## Correct an existing language

1. Open the file for that language (e.g. `lib/l10n/app_de.arb`) on GitHub.
2. Click the pencil (✏️) to edit, fix the wording, and propose the change as a
   pull request. That's it.

## Add a new language

1. Copy `lib/l10n/app_en.arb` to `lib/l10n/app_<code>.arb` (e.g. `app_fr.arb`).
2. Change the first line to your language: `"@@locale": "fr"`.
3. **Delete every `"@key": { … }` block** — those are descriptions for
   translators, not translations. Keep only the real `"key": "value"` lines.
4. Translate each **value** (the right-hand side). Leave the **keys** (left-hand
   side) exactly as they are.
5. Open a pull request. The maintainers add the language to the app's supported
   list, and it appears in the in-app language picker.

## What to watch for

**Leave the keys alone.** Only translate the text on the right:

```json
"commonSave": "Save",        →   "commonSave": "Enregistrer"
```

**Placeholders in `{curly braces}` must stay** — they're filled in with a number
or word at runtime. Keep them, move them where your language needs them:

```json
"searchAddedFood": "{name} added"   →   "searchAddedFood": "{name} ajouté"
"weightLast": "Last {value} kg"     →   "weightLast": "Dernier {value} kg"
```

**Plurals** use ICU syntax — translate the words inside `one{…}` and `other{…}`,
and add the plural categories your language needs (some have `few`, `many`, …):

```json
"backupEntryCount": "{count, plural, one{{count} entry} other{{count} entries}}"
→
"backupEntryCount": "{count, plural, one{{count} entrée} other{{count} entrées}}"
```

**Casing is handled for you.** Many labels are shown in ALL CAPS in the app, but
you write them in normal case — the app upper-cases them where the design needs
it. Write `"Settings"`, not `"SETTINGS"`.

**Leave these untranslated:** brand and product names (`EasyTrack`, `Open Food
Facts`, `BLS 4.0`, `USDA`), licence identifiers and DOIs in the data-source
credits, and unit symbols (`kcal`, `g`, `ml`, `kg`, `cm`) — they're the same in
every language and aren't in the files.

## Testing your translation (optional)

If you have Flutter installed, you can see it live:

```bash
flutter gen-l10n   # regenerates the localisation code from the .arb files
flutter run        # then pick your language in Settings → Language
```

If a placeholder is malformed, `flutter gen-l10n` will tell you which key. You
don't need to run this to contribute — the maintainers check every PR.
