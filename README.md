# MI-12 — Garry's Mod Addon

**Bombin Addons** family — same menu system and plane-logic framework as the AN-71.

> ⚠️ **Placeholder / WIP** — model, sounds, and special ability not yet implemented.

## Structure
```
lua/
  autorun/
    npc_mi12_heli.lua                  ← server spawner + NPC trigger loop
    client/
      cl_npc_mi12_heli_menu.lua        ← Q-menu control panel
  entities/
    ent_mi12_heli/
      shared.lua                       ← tuning constants (both realms)
      init.lua                         ← server-side flight logic
      cl_init.lua                      ← client damage FX + net receivers
      cl_trailsystem.lua               ← rotor / exhaust trail renderer
```

## TODO
- [ ] MI-12 model + rigging
- [ ] Engine / rotor sound assets
- [ ] Special ability implementation
- [ ] Trail emission-point tuning to match MI-12 mesh
- [ ] Gib models
