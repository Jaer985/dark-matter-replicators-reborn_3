# DMR — Roadmap

_Estado del fork: Post 4.6 (Jaer985) — Base: Factorio 2.1 (solo 2.1 desde v4.0)_
_Última publicada en portal: **4.7.1** (2026-10-24, 36 releases; 4.7.0 quedó sustituida). Gates sobre el zip: data stage 0 errores / 0 warnings, mapa headless creado con `control.lua` cargado y 0 errores, 9/9 suites. Descripción y FAQ del portal al día; anuncio y changelog de Discord verificados (con cabeceras de idioma)._
_4.5.1: Replicadores auto-replicables (6,32/12,64/25,28/50,56/101,12 s) · techo de 1 MJ en la clase combustible (spoilage y semillas fuera del escalón de duplicación) · tier del replicador = max(cadena, pack) + suelo 2 para máquinas y militar (tier 1 vanilla 92 → 40) · cobre fundido 53,6 → 12,5 s · laboratorio de replicación researching_speed 2,0 · pestaña: subgrupo propio para la cadena de energía._
_Pendiente inmediato: gate test en juego de 4.5.1 (replicador auto-replicable, tamaño del picker, pestaña) y, después, **4.6.0**: escalera del refinador por calidad de entrada + niveles de calidad de otros mods._

> El antiguo `roadmap.txt` del upstream (nihilistzsche / Honktown) está congelado en la era 0.17/0.18 y ya no aplica. Este documento es la fuente viva de planes para el fork moderno.

---

## ✅ Cerrado recientemente

- **v4.7.1** (2026-10-24, publicado) — Refinador de calidad: máquina de crafteo + autodetección de receta
  - La 4.6.x/4.7.0 no refinaba: una assembling-machine construye su inventario de entrada desde los
    ingredientes de su receta, así que con receta vacía tenía **0 huecos** y `can_insert=false` (medido en
    motor: `len=0`, `inserted=0`). La 4.7.0 lo resolvió como contenedor (20 huecos, sin energía), pero el
    autor quiere crafteo: **4.7.1 vuelve a la máquina de crafteo** con sus recetas, 1 MW y barra real.
  - **Autodetección**: `control.lua` mantiene la receta apuntando al escalón que corresponde a la calidad
    actual del item. Eliges la receta UNA vez por item; tras un acierto el item sube y el script cambia solo
    a "refine to rare", luego epic, luego legendary.
  - **Exploit cerrado**: el gate real en 2.1 es `quality_min`/`quality_max` (y acepta NOMBRE de calidad, no
    nivel). Verificado en motor: una pieza normal en la receta legendaria → `insert = 0`; en la de uncommon → `1`.
  - Ritmo: 1 s por intento en tier 1 … 5 s en tier 5 (`lib/refiner-logic.cycle_seconds`), probabilidades
    5 / 2,5 / 1,25 / 1 % y 1 % de pérdida.
  - Pitfall registrado: en runtime `LuaRecipePrototype` expone **`energy`**, no `energy_required`.
  - Gates: data stage 0/0, mapa headless 0 errores, 9/9 suites.

- **v4.5.1** (2026-10-24, publicado al portal) — Replicación de todo el paquete de 4.4/4.5 + el gate test del autor
  - **Replicadores auto-replicables**: los cinco tiers vuelven a ser objetivos (`dmrsa-repl-dmrsa-replicator-1..5`), a 6,32 / 12,64 / 25,28 / 50,56 / 101,12 s, cada uno en su tier. La whitelist de `target-mapper` (intención v4.2, `repltech_recipe(device3-5, upgrade=true)` del upstream) era **código muerto**: `is_own_machine` la anulaba por nombre. Al abrirla aparecieron otros dos cierres: el clamp C5 repreciaba cada replicador por su propia parts bill (3.695-15.612 s → techo de 3.600 s lo borraba) y el bloque de "recycler loop" hacía lo mismo. Medido: 254 recetas (antes 249), 0 exclusiones por techo.
  - **Suelo de la clase combustible**: `TimingModel.is_fuel_class()` = quemable **y** `fuel_value >= 1 MJ`. Antes/después: 18 → 16 recetas con `allow_productivity`; fuera spoilage (250 kJ) y semilla de árbol (100 kJ).
  - **El tier del replicador = la escalera del tiempo**: categoría = `floor(max(cadena, pack))`, con suelo 2 para máquinas y militar. Causa raíz: la categoría salía solo del cost-solver, así que todo lo desbloqueado por ciencia verde/militar caía en el replicador simple; y `oil-processing`/`electronics` son techs *trigger* (sin unit) → pack 1.0. Vanilla+SA: tier 1 **92 → 40 recetas**. `PACK_LEVELS` de logistic alineado a 2.
  - **Cobre fundido**: 53,6 → 12,5 s (la tabla de fluidos tenía `molten-iron` y no `molten-copper`; misma lava, mismo foundry).
  - **Laboratorio de replicación**: `researching_speed = 2.0` (no tenía ninguno), módulos de velocidad siguen apilando.
  - **Menú de recetas por CATEGORÍA y por estructura** (`lib/item-class.lua`, nuevo): clasifica leyendo el prototipo (tipo de entidad de `place_result`, tipo de item, `fuel_value`, receta de smelting, subgrupo `raw-resource`) en vez del nombre. 13 categorías: machines · power · science · modules · ores · plates · intermediates · chemicals · logistics · military · fuels · organic · darkmatter. Antes: 104 recetas en "General" y 65 en "Replication resources" (con `iron-chest` como "elemento puro" y `copper-cable` como "objeto con forma"). Los items planetarios ya no se vuelcan en "resources".
  - **Pestaña de crafteo**: subgrupo propio `dmrsa-power` (synthesizer → anillo → cámara → bobina, en orden de construcción) y la fila de recursos renombrada a "Dark matter"/"Materia oscura".
  - Tests: `test_mirror` y `test_economy_invariants` afirmaban las reglas viejas (replicadores = loop, logistic = tier 1); actualizados. 9/9 suites PASS.

- **v4.5.0** (2026-10-22, publicado al portal) — Bobina de aniquilación (`dmrsa-annihilation-coil`): `burner-generator` 2×2 que quema materia oscura directamente en electricidad, sin calor, agua, intercambiadores ni turbinas. Mismo balance: 25 GJ → 41,6667 MW × 600 s, `effectivity = 1.0`, categoría de combustible privada. Tech propia tras `dmrsa-annihilation` (75 unidades). Locale EN/ES con paridad de claves.

- **v4.4.0** (2026-10-22, publicado al portal) — Bucle de energía de materia oscura + timing model v3
  - Anillo acelerador (250 MW, 25 tenemut + 1 conducto → 1 materia oscura en 200 s) y Cámara de aniquilación (reactor, 25 GJ = 600 s a 41,6667 MW, sin bonus de vecinos, materia oscura solo se quema ahí).
  - Investigación de duplicación (tiers 3/4/5): +100/+200/+300 % acumulativo (2/3/4 items por ciclo) sobre recetas de combustible y sobre la colisión del anillo.
  - Timing model v3: tiempo = 6,32 s × 2^(tier-1) × complejidad (1 + 0,02 × pasos, tope 1,50), techo 200 s aplicado después del multiplicador de dificultad. Ammonia/holmium 25 s, hierro fundido 12,5 s (antes los tres a 200 s).
  - Refinador: recetas seleccionables otra vez (el picker estaba vacío desde 4.1.0: `hidden` en vez de `hide_from_player_crafting`), 1 MW, probabilidades ×5, pérdida 5 % → 1 %.

- **v4.3.1** (2026-10-17, publicado) — Solo texto: descripción del mod al día (no cambia gameplay).

- **v4.3.0** (2026-10-16, publicado) — Modo sin mineral + sintetizador de materia oscura
  (petición del portal, hilo de evil_star)
  - Nuevo ajuste `dmrsa-tenemut-source` (3 modos): Ore patches (default, sin cambios) / Ore patches + synthesis / Synthesis only. El último quita el tenemut del worldgen por completo: sin autoplace spec, sin autoplace-control, sin inyección en los planetas (data-updates bloques 1+2).
  - Nueva máquina **Dark Matter Synthesizer** (`prototypes/entities/synthesizer.lua`): 1 MW, 4 s por tenemut, `ingredients = {}` (solo electricidad), categoría propia `dmrsa-synthesis`, receta de construcción propia. Tech nueva `dmrsa-tenemut-synthesis` en `technologies.lua` (prereq `electronics`, solo automation science → sin candado circular: no se necesita tenemut para investigar lo que produce tenemut).
  - Nuevo ajuste `dmrsa-tenemut-research-required` (default ON): al desactivarlo los techs de replicación usan los packs vanilla de su tier en lugar del pack DMR — `make_research_unit` + ambos `add_research_pack` + red de seguridad contra listas de ingredientes vacías (bug "sin coste" de v4.2) + fallback por tier para los techs de materiales.
  - Guardas anti-exploit: `hide_from_player_crafting = true` (una receta sin ingredientes craftable a mano = items infinitos gratis), `allow_productivity = false`, máquina con 0 slot de módulos y `allowed_effects = { "consumption" }` (también bloquea beacons): la electricidad ES el coste.
  - El prototipo `resource` se MANTIENE en todos los modos por compatibilidad de saves (las partidas ya generadas conservan sus parches y siguen cargando); el ajuste solo cambia lo que genera un mapa NUEVO.
  - Tests: `dmr-tests/test_tenemut_source.lua` 48 checks + test_mirror 82 + test_cost_bands 257 + run_tests 54 + test_refiner 48 + test_planet_routing 14 + test_step_filter PASS. Zip `dark-matter-replicators-reborn_4.3.0.zip` (builder `research/build_430.py`). Gate test pendiente (usuario, PC de juego).
  - Nota para la idea futura del reactor "dark energy" (`research/futures-dark-energy.md`): con el sintetizador ya no hace falta el parche de ore para alimentar la cadena scoop → dark matter → reactor; el diseño debe apoyarse en él (y decidir si el scoop sigue siendo item de research o pasa a máquina extractora).

- **v3.6.4** (2026-08-11) — Eligibility rule + auto-hide categories
  - target-mapper: items only replicable if produced by recipe OR minable OR whitelisted. Phantom/spawn-only items (no recipe, not minable) no longer generate junk research — covers mod internals (factorissimo factory-*) and future mods without per-mod lists.
  - data-final-fixes PASS 5: empty category subgroups auto-hidden.
  - Tests: 17/17 step+eligibility + 9/9 cost-solver. Receipt 16/16.

- **v3.6.3** (2026-08-11) — Step filter + replication-2 packs
  - Hybrid filter in target-mapper: name patterns + explicit list (bearing balls, projectiles/warheads, roboport parts, robot sub-parts, small alien artifacts, processor components) — Bob's intermediates no longer pollute replication lists.
  - replication-2: automation + logistic only (chemical es tier 3).
  - Test: test_step_filter.lua 7/7 + run_tests.lua 9/9 + receipt 14/14.

- **v3.6.2** (2026-08-11) — Settings locale fix
  - Fixed "Unknown key: mod-setting-name.replication-penalty". Added missing name (EN/ES) + 3 base-stat descriptions. All 26 settings now have name+description with parity.

- **v3.6.1** (2026-08-11) — Hotfix idle_animation (portal crash)
  - Fixed "Animation speed has to be greater than 0" — idle_animation `animation_speed = 0` → `0.01` (Factorio exige >0). Publicado tras el 3.6.0 que no cargaba con Combat Mechanics Overhaul + Bottleneck Lite.

- **v3.6.0** (2026-08-09) — Release mayor (salto desde 3.5.19 publicada)
  - Acumula 3.5.20→3.5.25: chemical antes de planetas, science tiers, scrap→fulgora, MACHINE_EFFICIENCY names, category subgroups, placeable locale fix, research difficulty, pack order, icon HD, idle animation, lab validation.
  - factorio_version se mantiene 2.0 (compat hacia atrás; dual-compat 2.1 activo).
  - Receipt 7/7 PASS.

- **v3.5.25** (2026-08-09) — Replicator idle animation (RDD flow, closes v3.6.0)
  - `idle_animation` added: dimmed (0.55 tint) static frame when no recipe/input; animated sprite while working. No new assets.

- **v3.5.24** (2026-08-09) — Icon HD fix (RDD flow)
  - Drop `icon_mipmaps` from copied icon layers + nil-safe `icon_size` per layer in get_tech_icons. Fixes top-left-corner rendering for large/custom icons (inherited upstream 0.8.0). Receipt 6/6 PASS.

- **v3.5.23** (2026-08-09) — Research pack order setting (RDD flow)
  - New `dmrsa-research-pack-order` startup setting (DMR Item First default / Science Pack First). Cosmetic, applies to individual + grouped techs. Receipt 10/10 PASS.

- **v3.5.22** (2026-08-09) — Lab inputs validation (RDD flow)
  - PASS 4 extended: lab accepts 6 SA packs (4 planetary + space + promethium).
  - Defensive warns if any pack missing or lab/inputs nil. Receipt 8/8 PASS.

- **v3.5.21** (2026-08-09) — Category subgroups + placeable locale fix (RDD flow)
  - Recipes grouped by category (16 subgroups: ore, element, shape, alloy, chemical, organic, module, module-advanced, science, military, military-advanced, life, exotic, magic, alien, general) in crafting menu — addresses sp518 "subgroups for replication".
  - Fixed "Unknown key: item-name.X" for placeable items (place_result → entity-name locale, 93 base items).
  - Receipt 12/14 (2 script false-negatives, code verified).

- **v3.5.20** (2026-08-09) — MACHINE_EFFICIENCY names fixed (RDD flow)
  - SA category names corrected: `metallurgic`→`metallurgy`, `electromagnetic`→`electromagnetics`, `cryogenic`→`cryogenics`, `organic-or-egg`→`organic` (verified vs space-age/prototypes/recipe.lua). Foundry and SA machines now apply intended multipliers instead of falling to 1.0.
  - Added `captive-spawner-process` (1.5x) + `hand-crafting` (1.0). Receipt 14/14 PASS.

- **v3.5.19** (2026-08-09) — Science pack tier forced (RDD flow)
  - Science pack replication tier now FORCED absolute (not just floor): cost-solver could push chemical-science-pack to tier 4-5, making its research use matter-conduit instead of dark-matter-transducer (tier 3 pack). Now chemical=3 always, planetary=4, space/cryo=5.
  - Receipt verified (1 script false-negative on split, code confirmed correct).

- **v3.5.18** (2026-08-09) — Scrap to Fulgora (RDD flow)
  - `scrap` classified to the Fulgora planetary replicator (was falling to generic tier 1). Receipt 7/7 PASS.

- **v3.5.17** (2026-08-09) — Chemical before planets + science tiers (RDD flow)
  - `dmrsa-replication-3` visible with SA (Chemical Replicator unlocks after logistics, before planets). Tier 4 now requires rep-3 + planetary techs.
  - t3_packs = chemical only; t4_packs = planetary (metallurgic/electro/agri).
  - Science pack replication tiers: automation/logistic=1, military=2, chemical/prod/util=3, planetary=4, space/cryo/promethium=5 (override by name, not cost chain).
  - `get_tier_from_tech` mapping updated to match.
  - Receipt 11/11 PASS.

- **v3.5.16** (2026-08-09) — Research difficulty setting (RDD flow)
  - New `dmrsa-research-difficulty` startup setting: Easy (Fast, default) / Medium (1.5x count, 2x time) / High (3x count, 5x time). Applied to ALL replication techs (individual, grouped, tier, planetary).
  - `dmrsa-grouped-tech-cost-multiplier` default 5.0 → 10.0 (grouped at least 10x per unlockable).
  - Receipt 13/13 PASS.

- **v3.5.15** (2026-08-09) — moon-eneas crash fix (spidertron-unit removed)
  - Declared `? moon-eneas` optional dependency to force load order: DMR data-final-fixes runs AFTER moon-eneas's, so PASS 1 strips the missing `spidertron-unit` prereq before assignID.
  - Generalizes to any mod that deletes techs: add optional dependency to force order.
  - Receipt 8/8 PASS.

- **v3.5.14** (2026-08-09) — Module/Military tier split (RDD flow)
  - Modules `*-module`/`*-module-2` → tier 3, `*-module-3` → tier 4 (new `module-advanced` category)
  - Basic weapons/ammo → tier 3, endgame ordnance (uranium/artillery/rocket/cluster) → tier 5 (new `military-advanced` category)
  - New locales EN/ES. Receipt 15/15 PASS.

- **v3.5.13** (2026-08-09) — Asteroid chunk name fix
  - `carbonaceous-asteroid-chunk` → `carbonic-asteroid-chunk` in cost-solver BASE_RESOURCE_COSTS and target-mapper whitelist. The carbon chunk was falling through to low tier; now maps to tier 4.

- **v3.5.12** (2026-08-09) — Target blacklist
  - Added TARGET_BLACKLIST: wires, remotes, planners, blueprints, selection tools excluded from replication.
  - Added filled-barrel exclusion (fill-*-barrel / *-barrel patterns). Empty barrel stays replicable.

- **v3.5.11** (2026-08-09) — Cost-solver fallback tier fix (mod portal report)
  - Fixed cycle/unknown fallbacks assigning tier 1/2 to overhaul-mod and SA items. Now use unlock-tech tier via get_tier_from_tech.
  - Relaxed ingredient-tier+1 cap when ingredients resolve to tier 1 (degraded by cycles) so items can reach true tier.

- **v3.5.10** (2026-08-09) — Planetary grouped tech parameter count
  - Removed redundant literal `planet_suffix` parameter from planetary grouped tech `localised_name`. Template has 2 placeholders, code was passing 3 parameters.

- **v3.5.9** (2026-08-09) — Tier coverage gaps for endgame items
  - Added `promethium-asteroid-chunk` to BASE_RESOURCE_COSTS tier 5. Previously fell through to tier 1 fallback.
  - Added FLUID_TIER_OVERRIDES for fluids with no recipe (fusion-plasma → tier 5).

- **v3.5.8** (2026-08-09) — Cryogenic fluid routing
  - Fixed `name == "fluoroketone"` → `string.find(name, "fluoroketone")` in aquilo branch. Real internal names are `fluoroketone-cold` and `fluoroketone-hot`, so the exact match never triggered.
  - Added `fluorine` to aquilo branch. Fluorine is a SA cryogenic fluid that was being routed to generic tier 3 chemical.

- **v3.5.7** (2026-08-09) — Audit cleanup + Space Age coverage
  - Extended MACHINE_EFFICIENCY to cover all 8 SA recipe categories (farming, brewing, metallurgic, electromagnetic, cryogenic, organic-or-egg, crushing, crafting-with-fluid-or-recycling). Previously these fell back to neutral 1.0x.
  - Removed unused `localized` field from repltypes.lua (dead code; display names come from locale file).
  - Fixed malformed `order = "f[dark-matter]"` to standard `"z"`.

- **v3.5.6** (2026-08-09) — Replicator item description fix
  - Replaced "Mirrors [entity-description]" placeholder text in [item-description] with the actual tier descriptions. Previously the cursor/in-hand description showed the literal placeholder.

- **v3.5.5** (2026-08-09) — Replicator categorization + tier subgroup locales
  - Fixed replicator tier 1-5 items using vanilla `production-machine` subgroup. Now in custom `dmrsa-replicators`.
  - Added localized names for `dmrsa-replication-tier-1` through `-5` subgroups in en and es-ES.

- **v3.5.4** (2026-08-09) — LocalisedString parameter fix
  - Fixed `"parameter-0"`, `"parameter-1"` literal rendering in dynamic recipes and individual techs. Root cause: `"?"` was being passed as a positional parameter, but Factorio 2.x treats `"?"` as a KEY (for fallback selection). Fixed by precomputing `loc_prefix` from `target.type` and using a single-parameter LocalisedString. Now displays "Replication: <item name>" as intended.

- **v3.5.3** (2026-08-09) — Settings UX + Localization overhaul
  - Fixed `dmrsa-use-machine-efficiency` description (said "Disabled" but default is `true`)
  - Fixed `order` conflict: `replication-in-space` was colliding with `replstats-speed-base`
  - Added `dmrsa-log-level` name + description in en and es-ES (was missing entirely)
  - Rewrote all 10 replicator entity descriptions + replication lab (were pre-v3.5.x lore text)
  - Added `dmrsa-tenemut` item description (was missing)
  - Added `item-subgroup-name` and `recipe-category-name` sections in both locales (2 + 4 entries)
  - Added names and descriptions for the 5 tier technologies (`dmrsa-replication-1` through `-5`) that were displayed as raw keys in the tech tree
  - 17 critical localization checks pass; full EN/ES parity verified

- **v3.5.2** (2026-08-09) — Hardening de data-final-fixes PASS 3
  - Tier 3 con SA ya no pierde unlocks: reasigna al placeholder oculto `dmrsa-replication-3` en vez de descartar
  - Warning defensivo cuando un orphan tech no matchea ningún pattern (tier ni planet)
  - 2 fixes de bajo riesgo, ninguna regresión esperada

- **v3.5.1** (2026-08-09) — Bugfixes de tier classification + cost-solver
  - `get_ing_count()` para recipes en formato 2.0+ `normal.ingredients`
  - `get_tier_from_tech()` — fallback heurístico corregido (5+ science packs → T3)
  - `data-final-fixes` PASS 3 — `planet_match` para techs agrupados huérfanos (vulcanus, fulgora, gleba, aquilo)
  - Fallback `dmrsa-use-machine-efficiency` corregido a `true` (alineado con default)
  - Nil-safety en `raw-resources.lua` para `tenemut-near-spawn`
  - Limpiado: 4 categorías muertas (`device2`-`device5`), branch muerta `tier > 5`, hardcoded `gprefix`
  - Categorías activas: 14 (ore, element, shape, alloy, chemical, organic, military, module, life, exotic, magic, alien, science, general)

- **v3.5.0** (2026-07-19) — Refactor mayor
  - Dual compat Factorio 2.0 / 2.1 (category string vs categories array)
  - Category-tier system: categoría = piso, cost-solver solo empuja hacia arriba
  - 7 → 14 categorías de replicación
  - Machine efficiency multipliers (setting `dmrsa-use-machine-efficiency`)
  - Smart prerequisite cleanup en grouped techs

- **v3.3.6** (2026-07-15) — Original techs como prereqs seguros
- **v3.3.5** (2026-07-08) — Fix crash "no lab will accept all the science packs" con Space Age

---

## 🔴 v3.5.x — Patch series

### v3.5.2 — ✅ Released 2026-08-09 (superseded por v3.7.0/v4.0)
- [x] Fix tier 3 reassignment en PASS 3 con SA (unlocks antes discarded, ahora van a `dmrsa-replication-3` placeholder)
- [x] Warning defensivo en PASS 3 cuando un orphan no matchea ningún pattern
- [x] Test runtime con Space Age puro + Krastorio 2 — cubierto por gates 3.6.0/4.0.0
- [x] Auditar PASS 1 y PASS 2 — absorbido por A4/A5/A6 (v3.7.0)

### v3.5.3 — ✅ Released 2026-08-09
- [x] Settings UX + localization overhaul (todos los items arriba)

### v3.5.4 — ✅ Released 2026-08-09 (superseded por v3.6.0+)
- [x] Test runtime con Space Age puro + Krastorio 2 (carry-over de v3.5.2) — cubierto por los gates 3.6.0/4.0.0
- [x] Auditar PASS 1 y PASS 2 (carry-over de v3.5.2) — absorbido por A4/A5/A6 (v3.7.0 PASS 0 + PASS 6)
- [x] Verificar machine efficiency con space-age machines — ✅ v3.5.20: nombres SA corregidos (metallurgy/electromagnetics/cryogenics/organic)

---

## 🟡 v3.6.0 — Quality of Life

- [x] **Power drain configurable de replicators** — ✅ YA EXISTE desde upstream: `replstats-energy-base` (256 kW) + `replstats-energy-factor` (2.5), localizados EN/ES. Roadmap item obsoleto (verificado 2026-08-09).
- [x] **Validación runtime de que el lab acepta los inputs definidos** — ✅ v3.5.22: PASS 4 extiende sa_packs a 6 (4 planetary + space + promethium) y añade warning defensivo si falta alguno o el lab es nil.
- [x] **Reordenar science packs en el replication selector** — ✅ v3.5.23: setting `dmrsa-research-pack-order` (DMR Item First / Science Pack First), helper en ambos flujos, locale EN/ES.
- [x] **Bug de iconos en alta resolución** — ✅ v3.5.24: `icon_mipmaps` eliminado de layers copiados + `icon_size` nil-safe por layer. Heredado upstream 0.8.0.
- [x] **Replicators que se apaguen visualmente** — ✅ v3.5.25: `idle_animation` con tint oscuro (0.55) usando el mismo sprite sheet frame 0. Sin assets nuevos. Cierra v3.6.0.

---

## 🟢 v3.7.0 — Robustez de balance multi-mod (CANDIDATE FROZEN 2026-08-11, A+B+C aprobado)

Objetivo: que DMR siga balanceado con cualquier modlist de overhaul (Bob's/Angel's/K2/SE) — ni overpowered ni roto. Verificado contra el modlist real del usuario (Bob's 14 mods, Angel's storage, factorissimo-2, KS_Power, combat-mechanics-overhaul, quality, AAI).

### Bloque A — Anti-overpowered
- [x] **A1: Tier dinámico para ores de mods** — ✅ IMPLEMENTADO 2026-08-11: `MOD_ORE_TIERS` en `lib/cost-solver.lua` (tin/lead/zinc/nickel/silver/quartz/graphite/sulfur→2, bauxite/rutile/cobalt/chrome/manganese→3, gold/thorium/tungsten/titanium/platinum→4, gem/iridium/osmium/neodymium→5), coste escalado tier^1.5. Tests: 9 ores Bob's en run_tests 23/23 PASS.
- [x] **A2: military-advanced extendido** — ✅ IMPLEMENTADO 2026-08-11: patrones sniper/laser-rifle/gatling/plasma/turret-[3-9]/armor-mk[3-9]/mech-/tank-[2-9] en `get_item_category` (`prototypes/recipes/dynamic-generator.lua`). Sin cambios al cap ingredient_tier+1.
- [x] **A3: MACHINE_EFFICIENCY para categorías de mods** — ✅ IMPLEMENTADO 2026-08-11: 18 entradas explícitas (bob-assembling-1..6, furnaces, electrolysis, distillery, air-pump, void, petrochem, electronics, barrelling) + fallback por substring en el lookup. `lib/cost-solver.lua`.

### Bloque B — Robustez estructural
- [x] **B1: Step filter + eligibility para fluidos** — ✅ IMPLEMENTADO 2026-08-11: loop de fluidos en target-mapper aplica `is_step_item` + eligibility (`is_produced_by_recipe` OR minable OR `CostSolver.is_known_resource`). Nuevo `CostSolver.is_known_resource()` expuesto. Tests: test_step_filter 21/21 PASS (water/crude-oil/steam kept; gas-ammonia/phantom excluded).
- [x] **B2: Fixtures reales de Bob's en dmr-tests** — ✅ IMPLEMENTADO 2026-08-11: 9 ores (bob-tin→2 ... bob-gem→5), bob-endgame-tech (gold pack→5), bob-sniper-rifle (tier 5 vía tech), phantom fluid. run_tests 23/23 + test_step_filter 21/21.
- [x] **B3: Auditoría colisión `tungsten-ore`** — ✅ RESUELTO 2026-08-11: bobores NO redefine `tungsten-ore` con SA activo (`if not mods["space-age"]` en `create_autoplace`). Con SA → Vulcanus (correcto); sin SA → tier 3 genérico vía BASE_RESOURCE_COSTS. Sin colisión ni crash. Documentado, sin fix necesario.
- [x] **A4 (nuevo): Re-attach prereqs originales (PASS 6)** — ✅ IMPLEMENTADO 2026-08-11: el generador corre en data-updates ANTES de que Bob's defina sus unlock-recipe → 118 items sin prereq de su tech original. PASS 6 en data-final-fixes reconstruye recipe_tech_map con datos finales y re-añade el prereq faltante. VERIFICADO contra dump real: 118 re-attached, 0 ciclos. Pitfall clave: resolver por `data.raw.recipe[item]` (nombre exacto), NUNCA vía recipe_map reconstruido — las recipes dmrsa-repl-* (0 ingredients) contaminan el map y crean ciclos self-prereq.
- [x] **A5 (nuevo): Deps opcionales Bob's en info.json** — ✅ IMPLEMENTADO 2026-08-11: `? bobplates` etc. (15 mods) fuerzan que DMR data-final-fixes corra DESPUÉS de los de Bob's (patrón moon-eneas). Sin esto, el PASS 6 vería datos incompletos.
- [x] **B4 (nuevo): Steps combat/mech + parameter-N** — ✅ IMPLEMENTADO 2026-08-11: bob-robot-brain-combat*, bob-robot-tool-combat*, bob-mech-* (brain/leg/leg-segment/frame/hip/knee/foot/armor-plate) en STEP_EXPLICIT; `parameter%-%d+` excluido (placeholder de recipes parametrizadas de Factorio 2.0, KS_Power). test_step_filter 29/29.
- [x] **Fix science pack advanced-logistic** — ✅ IMPLEMENTADO 2026-08-11: `bob-advanced-logistic-science-pack` era forzado a tier 1 (patrón "logistic" matcheaba "advanced-logistic"). Ahora `advanced%-logistic` se matchea primero → tier 3. Evidencia del dump log.
- [x] **A6 (nuevo, riesgo alto): Mover generate() a data-final-fixes (PASS 0)** — ✅ IMPLEMENTADO 2026-08-11: causa raíz de tiers Y prereqs. El generador corría en data-updates ANTES de que Bob's definiera recipes/unlocks → dump probó 118 prereqs perdidos + 367 items under-tiered (bob-destroyer-robot asignado 1 real 5, solar-panel 1→4). generate() ahora corre en data-final-fixes PASS 0 con datos COMPLETOS (requiere deps A5 para ordenar DMR después de Bob's). Los unlocks baseline/planetary se attachan en el mismo PASS 0. PASS 6 queda como red de seguridad. data-updates.lua conserva autoplace/surface conditions.
- [x] **B5 (nuevo): Gem ores individuales** — ✅ IMPLEMENTADO 2026-08-11: bob-amethyst/diamond/emerald/ruby/sapphire/topaz-ore → tier 5 (el patrón "gem" no los matcheaba, caían al fallback tier 1 — dump: asignado 1, real 5). MOD_ORE_TIERS ampliado. run_tests 29/29.

### Bloque C — QoL
- [x] **C1: Auto-detección de mods overhaul** — ✅ IMPLEMENTADO 2026-08-11: `OVERHAUL_MOD_NAMES` en `settings.lua` (bobplates/bobassembly/bobtech/bobores/boblogistics/bobmodules/bobwarfare/bobpower/bobmining/angelssmelting/angelsrefining/angelsindustries/angelspetrochem/Krastorio2/SpaceExtension) → default `dmrsa-grouped-tech-cost-multiplier` 10.0→15.0. Descripciones locale EN/ES actualizadas.
- [x] **D1 (nuevo): Research difficulty — tabla única + Very Hard** — ✅ IMPLEMENTADO 2026-08-11: `helpers.get_research_difficulty_values()` es la fuente única de los 3 ejes (cost/time/cap) para que siempre matcheen. Easy: 25/5s/600s (histórico, respeta settings replresearch-*). Medium: 50/15s/1000s. High: 100/30s/1800s. Very Hard (nueva dificultad): 200/45s/3200s. El cap de 600s hardcodeado ahora escala con dificultad. `get_research_difficulty_multipliers()` queda como alias derivado (backward compat). Tests 34/34.
- [x] **D2 (nuevo): Refresh de descripciones** — ✅ IMPLEMENTADO 2026-08-11: 4 descripciones contradecían el comportamiento real (dmrsa-replication-3 / replicator-3 decían que tier 3 estaba gated por planetas — FALSO desde v3.5.17; replication-penalty decía "added" pero es multiplicador; item-multiplier con texto upstream obsoleto). Lore de scoop/transducer/conduit modernizado; space-lock pulido. Paridad EN/ES verificada con auditoría de keys (0 faltantes).
- [x] **D3 (nuevo): Lore atmosférico completo** — ✅ IMPLEMENTADO 2026-08-11: reescritura total del lore (items, entidades, techs 1-5 y planetarias) como narrativa coherente con el mod actual: tenemut descubierto en un mundo remoto, el scoop como "primera máquina en tocar el vacío", el transductor dando "intención" a la materia, el conducto construyendo a escala nanométrica, replicadores planetarios sintonizados con la naturaleza de cada mundo (corazón geotérmico, tormentas electromagnéticas, frescura biológica, frío absoluto). Números reales preservados (3x/5x verificados contra prototipos). Paridad EN/ES 0 claves faltantes, 0 restos del lore anterior.

### Flujo
1. Candidate frozen → review por riesgo → implementar A1→A3→B1→B2→B3→C1 — ✅ TODOS IMPLEMENTADOS 2026-08-11
2. Tests: dmr-tests (lua5.2) — run_tests 23/23 + test_step_filter 21/21 ✅
3. Receipt por release → gate test en juego (Bob's + SA + K2) → portal

---

## 🟢 v3.7.0+ — Features mayores (ordenar por valor)

- [x] **v4.0 — Árbol espejo + Factorio 2.1 (IMPLEMENTADO, GATE TEST SUPERADO y PUBLICADO al portal 2026-08-14)** — rediseño del sistema de techs/tiempos:
  - **factorio_version → 2.1** (drops 2.0, elimina dual-compat `dmrsa_is_v21()`, recipes usan `categories = {...}` directo)
  - **Sistema: árbol espejo con umbral 1** — cada tech original del juego genera su tech de replicación ("Replication: Logistic System" desbloquea requester-chest/buffer-chest/etc.). Grouped por categoría eliminado; categorías quedan solo como subgroups visuales.
  - **Tier de cada espejo = science level de su tech original** (automation=1, military=2, chemical/prod/util=3, planetary=4, space/cryo=5) — corrige los 25 offenders endgame en tier 3 (dump-verificado: requester-chest 3→5, mech-armor 4→5...)
  - **Cadena de progresión: máquina → materials-N → espejo** — 5 techs nuevas `replication-materials-N` (una por tier, pack = tenemut/scoop/transducer/conduit) que desbloquean los materiales base del tier (88 items sin tech original) y son prereq de las techs espejo de ese tier. Filosofía: no replicas sin conocer los materiales.
  - **Tenemut replicable SOLO a tier 5** (2026-08-14): excepción en target-mapper anti-loop + force tier 5 en el generador — "dominio de la materia oscura". El resto de items dmrsa- (scoop/transducer/conduit/lab/replicadores) NO se replica.
  - **Renaming parcial (2026-08-14)**: solo `matter-conduit` → "Nanophase Conduit" (EN) / "Conducto nanofase" (ES). El resto de materiales mantiene su nombre (scoop/transducer/tenemut) — el renaming completo no convenció y se descartó.
  - **Descartado (2026-08-14)**: generación de iconos/imágenes con IA (Gemini/Canva) — los resultados no cuadran con el estilo Factorio (cartoon/3D). También descartadas las referencias de lore para IA y la investigación de vías free (el coder ya respondió la tarea, sin más acción).
  - **Exclusiones (144 items)**: armas, armaduras, capsules de combate, vehículos, equipo de vehículo, equipo personal EXCEPTO solar/baterías. Se quedan: munición (uso masivo aliens), fuel cells, seeds, raw-fish.
  - **Números (dump 3.7.1, Bob's+SA)**: 945 items → 144 excluidos → 801 replicables → 417 techs espejo + 5 materials + 4 planetary = ~426 techs
  - **Settings**: `require-original-tech` (prereq tech original ON/OFF); sample-based (opción A) como modo futuro
  - **Fixes 2.1 aplicados**: `__base__/` require de assembler-pictures (assembler2pipepictures ya no es función global), tree-depth clamp anti "Non-contiguous levels", deps opcionales Angel's en info.json (load-order), cadenas de techs `-N` normalizadas a UNA tech espejo por cadena
  - **Respaldo**: `backups/dark-matter-replicators-reborn_3.7.1-source-backup.tar.gz` (punto de reversión)
- [ ] **Compatibilidad Yuoki Industries (PAUSA registrada 2026-08-14 — se retoma cuando Yuoki esté actualizado a 2.1 y en la modlist)** — análisis previo: 275 items, 112 máquinas con place_result. YA implementado: `? Yuoki` en info.json (load-order), blacklist `YUOKI_EXCLUDED` en target-mapper (10 inserters → cubiertos por Bob's inserters, 1 bunker storage, 8 basements), 4 faction signs excluidos (y_greensign/y_rwtechsign/ypfw_trader_sign/ye_science_blue). Pendiente decisión usuario item por item: procesado (16: y-crusher, y-dirtwasher, y-mining-drill, y-atomic-constructor, y_crystalizer, y_smelter, y_trockner...), refinado (5: y-water-gen, y_hppump, y_mixer_emu, y_water_mixer), mastercrafted (8: y_boiler4_mc, y_steam_turbine_mc, y_mc_*), ultimate (6: y-alien-infuser, y-fame, y-stargate, y_trade_ultimate), sueltos (y_c22, y_cg33, y_sc11, y_sc44, y_pc22, y_rc22, y_bc22, y_block_cold/heat, y_steinmehl, yi_graphite, y-seg-p, y_bg-1). NOTA: el filtro universal `place_result` se REVERTIÓ — mataba items de uso masivo (chests, pipes, lamps, poles, belts) que deben seguir replicables; las máquinas Yuoki se manejan per-item.
- [x] **v4.2.0 (2026-08-22) — Fix de baseline inflado (dump 4.1.0, modlist 138 mods)** — `materials-1` desbloqueaba 108 items (vs 16 del diseño). Causa raíz: el mirror asumía item↔recipe-name 1:1; los outputs de proceso de Angel's/planetaris (angels-gas-*, angels-mineral-sludge, geodes, crystals) no tienen recipe homónima → caían al baseline. 
  - **Fix 1 (mirror)**: los outputs heredan la tech de su recipe productora del MISMO mod (guardas: no-minable, mismo prefijo de mod, excluye recycling/barreling) → materiales-1 108→30, espejo 1328→1497 techs.
  - **Fix 2 (cost-solver)**: `MOD_ORE_TIERS` ahora es override **UNIVERSAL** (piso en todos los retornos de solve_cost, no solo el fallback de recursos) + tabla ampliada (angels-ore1..9→2, fluorite/manganese→3, chrome/thorium→4, platinum→5, planetaris gems/metales, sphalerite/tetrahedrite→2, vaterite→3, gold-ore→4).
  - **Pitfall Lua documentado en skill**: `-` es cuantificador lazy en patterns → los patrones con guiones deben escaparse `%-`; el override elige el match MÁS LARGO ("angels-platinum-ore" contiene "tin").
  - Tests: 143 checks (9 fixtures nuevos de ore-path en run_tests).
  - **Fix 3 (audit profundo 9 subagentes, 2026-08-22)**: equipos Bob's versionados (-equipment-2..6, 13) ahora excluidos; mis-ruteos corregidos: spaceship-scrap→espacio (NO fulgora), foundry/lava→vulcanus, carbon→space-platform, burner-pumpjack→baseline; factory-circuit-connector + bob-spidertron-cannon excluidos. (Los robots de combate que Fix 3 excluyó se REVIERTEN al mismo día por decisión B5 — ver abajo.) Tests 171 checks.
- [x] **Quality support (IMPLEMENTADO 2026-08-16 como Quality Refiner)** — diseñado con brainstorming balanceado y fiel: el replicador normal NO produce calidad (setting `dmrsa-replicator-quality` default "Normal only"; las replication recipes llevan `quality = "normal"`); la calidad llega por el **Refinador DMR** (`dmrsa-refiner`), una máquina dedicada que sube items replicables +1 grado (nunca salta): chance decreciente por grado (1%→uncommon, 0.5%→rare, 0.25%→epic, 0.1%→legendary), energía ×3 de la repl recipe (v4.2: era ×10, inoperable con la reescala — ahora 4MW), 5% de pérdida del item, y reintento con el mismo item el resto. Solo items replicables (arma/vehículos fuera — el refiner refina lo que la red domina). Tech propia `dmrsa-replication-refining` (materials-5 + quality vanilla). Sin modules en el refiner (la probabilidad ES el balance). Placeholder gráfico: assembler-1 2.x con tint violeta/obsidiana (dimensiones reales del dump, no memoria). Solo existe con mod de calidad activo. Tests 41/41 (test_refiner.lua). (Los items quality como targets quedaron DESCARTADOS técnicamente: el engine expande calidad DESPUÉS de los data stages — inviable en data-final-fixes.)
- [x] **REBALANCE B2 — Escala de costos (IMPLEMENTADO 2026-08-22, REFINADO + REFINO ORIGINAL)**: tiempos = clamp( min(vanilla, solver) × CT(3-7x) × máquina×por-tier (1.5-3.5x), bandas FIJAS 2.7-16/5.3-32/10.6-64/20-120/33.3-200 ) con clamp sobre el LOTE de fluidos; **speed_factor 1.6**; **kW 1/3/8/15/30 MW** (misma energía/recipe); planetarios 40/80 MW; refiner ×3 + 4MW; cross-tier recursivo confirmado; cap de dificultad inactivo. **Refino original (estudio upstream 2.0.4 — research/dmr-original-mod-study.md)**: replicadores 1-5 replicables (tier propio); rareza de ores dinámicos (mining_time×2 al coste); research SIN ×item_count (materials-1 250→10 reps); quitado productivity de allowed_effects (exploit 0-ingredientes, incl. planetarios); penalty +0.5 FIJO (suma, fiel al original — el setting dmrsa-cost-calculation-method quedó sin efecto y marcado legacy en locale EN/ES). 171 tests PASS.
  - ⏳ **CIERRE DEL PAQUETE B2 (pendiente si el usuario quiere)**: revisar el multiplicador de máquina por tier con más datos (¿1.5-3.5x es el spread correcto?) y el comportamiento planetario en gate test real. También anotado del estudio original: equipo personal (original replica mech-armor), science packs t3-5, módulos t4-5 — decisiones del usuario actuales, no tocar sin pedir.
- [x] **REBALANCE B1 — Separar techs espejo por nivel en cadenas saturadas (DECIDIDO 2026-08-22 = opción C, IMPLEMENTADO)**: generar espejos por tier SOLO en las cadenas saturadas (automation, logistics, logistic-system, bob-robo-modular, angels-metallurgy, angels-advanced-chemistry, angels-nitrogen-processing) — las 10 candidatas se redujeron a 7 tras el dump (bob-oil-processing no existe, angels-oil-processing y bob-electronics no tienen niveles). Resolviendo los niveles huecos: verificados — todos los niveles de las 7 cadenas tienen ≥1 item replicable (sin huecos → sin riesgo "Non-contiguous").
  - **IMPLEMENTADO 2026-08-22 (v4.2)**: 7 cadenas separadas (las 10 candidatas se redujeron a 7 tras el dump: bob-oil-processing no existe, angels-oil-processing y bob-electronics no tienen niveles). Espejos 466→492 (+26). Cada mirror-N gateado por el tier del COST-SOLVER de sus items (no por la science level de la tech original) — asm-6 detrás de replication-4, belts rojas/azules separadas. Efecto colateral documentado: `angels-advanced-chemistry-1` mezcla 6 items tier1 + 1 tier3 → el mirror queda tier 3 (max) — la chem básica de Angel's se retrasa a materials-3 (aceptado, progresión química).
- [ ] **Compatibilidad explícita con PyMods / otros frameworks de scripting** — detectar vía `script.on_load` si hay mods Python activos
- [ ] **Replicación de OmniMatter + recipe tenemut-from-omnite** (pendiente upstream)
- [ ] **Cost calculator por crafting difficulty** — actualmente solo `normal`; ofrecer `expensive` con multiplicadores
- [ ] **Scenario standalone sin ores** (item upstream 0.8.1) — start con grid, replicators y techs; útil para testing rápido
- [x] **Bucle de energía de materia oscura (IMPLEMENTADO v4.4.0)** — el item `dmrsa-dark-matter` ya no está huérfano: lo produce el **Anillo acelerador** (250 MW × 200 s = 50 GJ por unidad, 25 tenemut + 1 conducto de nanofase) y lo consume la **Cámara de aniquilación** (`type = "reactor"`, 41,6667 MW de calor durante 600 s por unidad, calor → intercambiadores y turbinas vanilla; sin bonificación de vecinos porque la materia metaestable se aniquila consigo misma). Investigación de duplicación (`dmrsa-duplication-3/4/5`) con `change-recipe-productivity`: +100 %/+200 %/+300 % → el anillo pasa de 0,50× a 2,00×. Decisión pendiente (ya no bloqueante): si el scoop pasa de item de research a máquina extractora.

---

## ✅ v4.6.0 — Refinador de calidad automático (CERRADA y publicada 2026-10-24)

Implementado tal como se aprobó: la máquina ya no tiene recetas que elegir.

- **`control.lua`** (primer y único script de runtime del mod): registra los refinadores con `on_built`/
  `on_removed` y recorre **solo** los registrados cada 30 ticks (0,5 s). Sin escaneo del mapa, sin coste
  si no hay ninguno.
- **Receta fija vacía** (`dmrsa-refine-cycle`, `fixed_recipe`): la máquina sigue necesitando energía y
  animándose, pero no hay picker — el bug del menú vacío (4.1.0 → 4.3.1) no puede repetirse.
- **`lib/refiner-logic.lua`**: escalera desde `data.raw.quality` ordenada por `level` (huecos incluidos),
  probabilidad por posición (5 / 2,5 / 1,25 / 1 %, suelo 1 %), 1 % de pérdida, y **nunca salta un
  escalón**. `cycle_seconds` = un segundo por tier (log2 sobre la escalera 6,32 s → 1-5 s).
- **Exploit cerrado**: `ingredients[].quality` NO filtra la entrada en 2.1 (el filtro real es
  `quality_min`/`quality_max`); el autor lo reprodujo metiendo una pieza común en el escalón legendario.
  Sin recetas por escalón no hay nada que elegir.
- Eliminadas ~800 recetas `dmrsa-refine-*` por item y el generador (`lib/refiner-generator.lua`).
- Tests: `test_refiner_logic.lua` (27 checks: escalera, no-skip, probabilidades, ritmo por tier, roll,
  240 ciclos esperados). 9/9 suites PASS.
- Gates sobre el zip 4.6.0: data stage exit 0 / 0 errores / 0 warnings · mapa headless creado con
  `control.lua` cargado (checksum en el log) y 0 errores.

---

## 🔧 Mejoras técnicas pendientes (backlog)

- [ ] **Modelo de coste 3.7.1 como opción (señal del portal, 2026-10-24)** — existe un mod de terceros
  `dark-matter-replicators-reborn-cost-revert` (creado el 2026-10-24, 4 descargas) que revierte la fórmula de
  tiempo de replicación a la de **3.7.1**. No se pudo inspeccionar el zip (la descarga del portal pide sesión),
  así que el diff exacto está pendiente. Lo que cambió entre 3.7.1 y 4.x: el solver recursivo con CT 3-7× +
  multiplicador de máquina 1,5-3,5× + bandas fijas 2,7-16 / 5,3-32 / 10,6-64 / 20-120 / 33,3-200 se sustituyó
  en 4.4.0 por el modelo cerrado (6,32 s × 2^(tier-1) × complejidad, techo 200 s) y se añadió la clase
  combustible por valor de combustión + el clamp C5 de arbitraje.
  Propuesta: ajuste de arranque `dmrsa-cost-model` = **v4 (forma cerrada, por defecto)** / **3.7.1 (bandas
  clásicas)**, para que ese mod deje de ser necesario y los jugadores que prefieren el modelo viejo se queden
  en el principal. Coste real: reinyectar la ruta antigua en `lib/timing-model.lua` detrás del flag + fixtures
  de ambos modos. Decisión del autor pendiente.
- [x] **Suite de tests de cost-solver** — DMRL: `dmr-tests/` (fuera del source dir, no se empaqueta). Harness mockea `data.raw`/`settings`, carga los módulos reales de lib/, fixtures cubren los bugs de tier v3.5.9-3.5.19. Correr: `cd dmr-tests && lua5.2 run_tests.lua`. Factorio usa Lua 5.2 (goto en cost-solver).
- [ ] **Ampliar fixtures** — añadir casos SA reales (foundry metallurgy, holmium, tungsten) y mods (Bob's cycles con tech)
- [ ] **Documentar el patrón de orphan techs** — el `planet_match` de PASS 3 es un patrón nuevo que debería estar en una nota para futuros mantenedores
- [ ] **Refactor `data-final-fixes.lua`** — 5 PASS en `prototypes/fixes/` (generate, prereqs, orphans, lab-inputs, empty-categories)
- [x] **Audit de `repltypes.lua`** — ✅ v4.5.1: reescrito a las 13 categorías aprobadas y el `general`/`shape`/`element` por nombre quedó sustituido por `lib/item-class.lua` (clasificador estructural).
- [ ] **Pasada de `gprefix` en `target-mapper.lua`** — la sustitución de prefijo sigue mereciendo una revisión de consistencia (el `_2` ya se eliminó en changelog).
- [x] **Localization ES-ES** — al día (paridad de claves EN/ES verificada 2026-10-19; sin claves muertas, sin CRLF)

---

## 📋 Procedimiento de release (pipeline real 2026-08, ver skill dmr-github-publishing)

1. Gate test en juego (Factorio 2.1, modlist real) → vaciar errores del log
2. Bump `info.json` version + entrada ACUMULADA en `changelog.txt` (todo lo no publicado desde la última versión del portal — consultar la API, hoy 4.3.1)
3. Build zip con la convención (`dark-matter-replicators-reborn_X.Y.Z.zip`) + `check-no-private-data.py` (privacy CLEAN)
4. Docs en una pasada: `mod-portal-description.md` actualizado (settings defaults, balance B2, features)
5. GitHub push: clonar → sync → push (el source dir NO es repo git; el token de GitHub para Jaer985 vive en el `.env` del perfil Hermes — ver skill dmr-github-publishing)
6. Subir al mod portal (upload del zip + descripción)

---

## 🎯 Prioridad inmediata (estado 2026-10-24, tras publicar 4.5.1)

1. **Gate test 4.6.0 en juego**: meter un item en el refinador y verlo subir de nivel (ritmo 1-5 s por tier), el 1 % de pérdida, que no salta escalones y que el inventario de salida lo recoge un inserter.
2. **Refinador automático — observaciones del gate test**: si el ritmo o la probabilidad se sienten mal en partida, se ajustan en `lib/refiner-logic.lua` (un número cada uno).
3. **Cierre de B2** — validar con datos reales el spread de máquinas (1,5-3,5×) y el comportamiento planetario (40/80 MW); necesita el gate test, no se puede verificar headless.
4. **Backlog técnico** — fixtures SA reales (foundry metallurgy, holmium, tungsten), documentar el patrón orphan-tech, refactor de `data-final-fixes.lua` en `prototypes/fixes/`, pasada de `gprefix` en `target-mapper.lua`.
5. **Aparcado / futuro** — Yuoki (cuando esté en 2.1), PyMods (`script.on_load`), OmniMatter + tenemut-from-omnite, coste `expensive`, escenario standalone sin ores; Darkstar Utilities: línea borrada el 2026-10-24 (no existe en el portal ni en GitHub; fósil del upstream 0.17).
