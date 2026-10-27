# Architecture

At a glance: the tracker polls the `pokemon.core` interface of `uzume.soullink-core`, records only what the game reported as seen (ids, counts, notes), stores it per run or per game in `fb.store`, and shows it in a panel tab and a screen. Names and types are read from the game at runtime and never stored.

## Layout

- `src/`: modules, listed in `src/modules.txt`. `tools/bundle.lua` generates the committed `plugin/main.lua` (`--check` fails when stale); the Uzume sandbox has no `require`, the bundler defines one.
- `plugin/`: `manifest.json` (requires `uzume.soullink-core` `>=0.4.0`, games: the two ORAS title ids), generated `main.lua`, `i18n/en.json` (source) and `de.json`.
- `tests/`: `lua5.4 tests/run.lua` runs every `tests/test_*.lua` against `tests/support/fb_mock.lua` (fake `fb`: store with revisions and conflicts, run, ui validator, events, `fb.call`) and `tests/support/fake_core.lua` (fake `pokemon.core` with synthetic ids and names such as "Demomon 21"). Synthetic data only.

## Modules

| Module | Role |
|---|---|
| `corelink` | Protected `fb.call` wrapper for `pokemon.core`. Failures and "not_ready" answers are nil and never cached; names, types and zone names are cached in memory once known. One log warning at most. |
| `data` | The stored data and its rules (record, caught, notes, limits, sanitize, merge). Pure. |
| `census` | Owned-species census (team, then one box per step) and the catch detection built on it. |
| `tracker` | Store, polling, events, view model, actions. |
| `views` | Panel and screen trees from a view model. |
| `util` | Helpers. |

## What is tracked

Only what the interface reports during play; nothing is read ahead, so no spoilers.

- **Wild encounters:** `encounters()` entries (new `seq` only) are recorded in the entry's `zone` as species/form with a count and a shiny flag. The core's `encounter` event triggers an immediate poll, otherwise the tracker polls about three times per second.
- **Trainer species:** while `battle()` reports an active trainer battle, each foe species/form is recorded once per battle in the current zone. Only the foes the interface lists are recorded; if the core lists a trainer's whole team before it is sent out, that would show more than the player has seen (open point).
- **Caught:** a wild species counts as caught when the owned count of that species/form (team and all boxes) is higher after the battle than before it. A census runs at the start of each wild battle and again at the end, 4 s later and 12 s later (the game adds the creature late), at most one box per tick. If the census before the battle could not be taken there is no guess. Without box support only the team is counted. Eggs are ignored.
- **Visited:** the current zone from `location()` is marked visited.
- **Notes:** free text per zone, saved at once; the view does not redraw for 3 seconds after typing.
- **Seen types:** for every species seen anywhere in the scope, `species_info()` gives its types; the overview counts species per type.

## Data and scope

Store key `tracker.run-<run id>` when `fb.run.current()` has an id (a run started with "Play run", or the run view), else `tracker.game-<game code>`; without either nothing is stored and the views show an empty state. A randomized run needs no special handling: it is keyed by the run, so every person's tracker data is separate, and the data never includes seeds or settings.

Value: `{ v = 1, areas = { ["z<zone>"] = { zone, visited, notes, wild = { ["s<species>f<form>"] = { species, form, n, caught, shiny } }, trainers = { same keys = { species, form, n } } } } }`. Everything is keyed by ids. Limits: 1000 areas, 200 species per kind and area, notes up to 2000 bytes (the store allows 256 KiB per value).

Changes are written at most every 2 seconds, notes at once. A stale write (another PC saved first) is never overwritten: the plugin reads the stored version, merges it with its own (union of areas and species, larger counts, caught/visited/shiny if either says so, both notes when they differ) and writes again. The `store.changed` event merges the same way.

## Views

- **Panel** (about 300 px): the current area first (visited badge, wild species with types and caught/seen count, trainers' species, notes field), then "Types seen" as chips and a button to the screen.
- **Screen:** filter chips (all, not visited, visited, has notes), a table of areas (area, seen, caught, trainers, notes) with the selected area's details below, and the types overview. The table lists the core's encounter areas (`areas()`, game order) plus any other zone with data, at most 500 rows; areas with the same name get their zone id appended.
- Names and types come from `name("species"|"type", id)` and `species_info()`; zone names from `areas()` / `zone_info()`. While the game text is not loaded the views show "Species 21", "Type 3", "Zone 5" and rebuild every 5 seconds until the names arrive.
- In the run view (no game) the screen shows the run's stored data from the store; names are not available there and appear as zone and species numbers.

## Open points

- The area key is the raw zone id from `location()`. A location with several zones (for example a route with buildings) shows as several rows; grouping by location needs the real data to judge.
- Whether `battle().foes` lists only the opposing creatures that are out, not a trainer's whole party, is to be checked with the real game.
- The core has no catch event, so catches come from the census heuristic above (a gift or trade of the same species right after a wild battle would count as caught).
- Zone names in the run view need the core to run; without a game they are numbers.
