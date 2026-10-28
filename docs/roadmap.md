# Roadmap

Status: v0.1.1 (API namespace `uz`, falls back to `fb` on older apps); v0.1.0 (seen wild species per area with types and caught state, trainers' species, notes, types overview, panel and screen, data per run or per game). Builds on Uzume plugin API v1 and `uzume.soullink-core` 0.4; see the [Uzume roadmap](https://github.com/phabioo/uzume/blob/main/docs/roadmap.md) and [`docs/guides/plugin-api.md`](https://github.com/phabioo/uzume/blob/main/docs/guides/plugin-api.md). Design and open points: [architecture.md](architecture.md).

## Done in 0.1.0

- Wild encounters per zone from the core's `encounters()`, with counts and shiny flag; trainer species per battle.
- Caught detection by owned-species census around wild battles.
- Panel tab with the current area first; screen with all areas, filters (all, not visited, visited, has notes), area details and notes.
- Seen types overview. Names and types from the game at runtime.
- Store per run (key includes the run id) or per game; merge on conflicts.

## Next

- Verify with the real game: zone grouping, `battle()` foes, catch detection, panel layout.
- Group zones by location if the real data calls for it.
- Items and hidden-item spots seen, if the core reports them.
- Export the notes as text.
