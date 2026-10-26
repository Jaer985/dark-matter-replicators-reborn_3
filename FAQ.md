# FAQ - Dark Matter Replicators Reborn

*New here? Read 1, 2, 7 and 9 first — that is what gets a factory running.*

### 1. What exactly does this mod do?
It adds replicators that produce items using electricity alone — no ingredients, no fluids, just power. Recipes are generated dynamically for almost any item, including items from other mods. Research is where the mod's own materials come in: a single **Replication Lab** consumes tenemut, the Dark Matter Scoop, the Dark Matter Transducer and the Nanophase Conduit as science packs while it unlocks replication technologies, and in the endgame the **Accelerator Ring** spends tenemut to manufacture dark matter — 25 GJ per unit, the densest fuel the replication network itself can make, and one that only the Annihilation Chamber and the Annihilation Coil will burn.

### 2. Where does Tenemut ore spawn?
It depends on your startup settings:
*   **Without Space Age**: It spawns on Nauvis, similar to uranium.
*   **With Space Age**: By default, it spawns on Nauvis to allow seamless early-game progression. However, you can change its primary spawning planet (to Vulcanus, Fulgora, Gleba, or Aquilo) and choose whether to spawn it on other planets in the startup settings.
*   **Not at all**: The separate **Tenemut source** setting can remove tenemut from world generation entirely (`Synthesis only`). See question 7.

Whichever planet carries it also decides the tier at which you can *replicate* tenemut — see question 9.

### 3. How is the energy cost of replication calculated?
Two numbers, both automatic:
*   **How much** power a recipe draws: derived from the item's own recipe chain — deeper and rarer items cost more, ores cost more the rarer they are, and machines cost more than plates.
*   **How long** it takes: a base time that doubles with each tier, scaled by how many distinct items the target's recipe chain contains, and capped at 200 seconds for normal items. A short list of large structures takes longer — up to one hour — and anything that would need more than an hour is not replicable at all.

The two multiply into the energy per item, so the only real decision is *which tier you run it on*. Higher tiers are faster and draw far more power per second; lower tiers are the cheapest per item. The old "Raw ingredients / Recursive steps" balance option is retired and no longer changes anything.

### 4. Can I replicate fluids or replicate items in space?
By default, replicating items on space platforms is disabled, but you can enable it via the "Replication in space" startup setting. Replicated fluids are delivered in configurable batches (25 units by default).

### 5. How can I make my own mod compatible with DMR?
**You almost certainly don't have to do anything.** DMR reads the finished game data and, at its own `data-final-fixes` stage, generates a replication recipe for every item that is *produced by a recipe*, *minable*, or explicitly whitelisted. If your item is craftable in a normal assembling machine and is unlocked by a technology that can be researched, it will be replicable — no per-mod list, no helper call, no opt-in.

There is **no** public helper API in this fork (older documentation mentioning `repltech_recipe`, `repltech_item`, `repltech_ore` or `lib/repltech.lua` refers to the upstream mod, not to Dark Matter Replicators Reborn — that file does not exist here, and DMR needs nothing from you).

Two things are worth knowing:
*   **Create your recipes in `data.lua` or `data-updates.lua`.** DMR's generator runs in `data-final-fixes`, so it sees everything defined before that stage. If your mod defines its recipes in `data-final-fixes` itself, list DMR as an optional dependency in *your* `info.json` (`? dark-matter-replicators-reborn`) — that pins DMR's final-fixes *after* yours. That is exactly how DMR orders itself against Bob's, Angel's, Space Age and moon-eneas.
*   **Do not name anything `dmrsa-…`.** That prefix is DMR's, and the generator uses prefix rules to decide whether an item belongs to the same mod as its recipe.

What **will not** be replicated, by design: weapons, armour, vehicles, vehicle and personal equipment (solar panels and batteries are the exception), wires, remotes, planners, filled barrels, internal sub-parts such as bearings, robot brains or warheads, DMR's own machines, and anything whose replication would take more than an hour.

### 6. Where should I report bugs or compatibility issues?
If you encounter a bug, startup crash, or mod compatibility issue, please post it on our [GitHub Issues Tracker](https://github.com/Jaer985/dark-matter-replicators-reborn_3/issues) or under the Discussions tab on the Factorio Mod Portal. When reporting, please include any error messages, your startup logs, and a list of other active mods to help us identify and resolve the issue quickly.

### 7. Can I play without tenemut ore? How do I get tenemut from electricity?
Yes. A startup setting called **Tenemut source** has three modes:
*   **Ore patches** (default): today's behaviour — tenemut ore generates in the world and there is no synthesizer machine.
*   **Ore patches + synthesis**: tenemut ore still generates, and the Dark Matter Synthesizer is also available.
*   **Synthesis only**: no tenemut ore is placed on any planet — the Dark Matter Synthesizer becomes the only way to obtain tenemut.

In the two modes that include synthesis, the **Dark Matter Synthesizer** is unlocked early by a technology that requires **automation science packs only** (prerequisite: electronics). It consumes no items at all — only electricity: 1 MW of continuous power, 4 seconds per tenemut. Because the recipe is energy-only, it deliberately never accepts productivity modules, so a steady 1 MW grid feed is all you need.

**The chain can never deadlock in this mode.** The technology that unlocks the synthesizer is cheap and has no tenemut, no dark matter and no DMR material pack in its cost, so `Synthesis only` is always playable from a fresh map.

This setting only affects **new worlds**: an existing save keeps the tenemut patches already on its map, so switching to "Synthesis only" never removes ore you already have.

### 8. How does the research work?
Each original technology spawns a **"Replication: \<tech\>"** mirror tech. To unlock a mirror you need (a) the original technology and (b) the `Raw material replication (Tier N)` tech of that tier. Those five materials techs are the only ones that require a DMR material pack — tenemut (tier 1), the Dark Matter Scoop (tier 2), the Dark Matter Transducer (tier 3) and the Nanophase Conduit (tiers 4 and 5). Mirrors follow *your* tech tree, which is why a modded item only becomes replicable once its technology is researched.

### 9. At what tier can I replicate Tenemut itself?
At the tier where tenemut appears: **tier 1** when it spawns on Nauvis or when `Tenemut source` includes synthesis, otherwise the tier of the lowest planet that carries it (Vulcanus 4.0, Fulgora 4.2, Gleba 4.4, Aquilo 4.6). There is no hardcoded "tier 5" rule any more — tenemut is an endgame-tier material when it lives on the outer planets, and an early one when it is on Nauvis.

### 10. What should I build first?
Build the **Replication Lab** and a **tier 1 replicator** as soon as `Dark matter replication` finishes; the lab eats the tier's DMR material as a science pack, so keep a stack of tenemut next to it. Do not rush tier 2 — a tier-N replicator can already make every item of tiers ≤ N, and tier 1 is the cheapest per item.

### 11. Why does energy matter, and how much power do I need?
Power *is* the cost. Tiers draw 1 / 3 / 8 / 15 / 30 MW, the planetary replicators 40 / 80 MW, and the Accelerator Ring alone takes **250 MW**. Replication is a way to trade a bigger grid for a smaller mine — plan the power plant before the replicator.

### 12. What is the endgame? What am I working toward?
The **fuel-duplication** research line (`Fuel Duplication (Tier 3/4/5)`, gated behind `Advanced replication`) adds productivity to every fuel replication recipe *and* to the ring's collision recipe: +100% at tier 3, +200% at tier 4, +300% at tier 5, cumulative — at tier 5 the Accelerator Ring turns 50 GJ of electricity into 100 GJ of burnable matter. It only pays in a high-efficiency burner, though: measured against a plain boiler or furnace the line returns 0.80× of the fuel's burn value even at tier 3, and 2.00× at tier 5 only in a 2.5× heating tower. The real endgame loop is the ring plus the **Annihilation Chamber**, which burns the unit and returns its full 25 GJ as heat on any planet — no burner efficiency needed.

### 13. How do I get dark matter?
Research `Dark matter collision` (it needs the tier-5 raw materials and production science), build the **Accelerator Ring**, and feed it 25 tenemut + 1 Nanophase Conduit per unit — 250 MW for 200 seconds. The **Annihilation Chamber** (from `Annihilation power`) burns that dark matter back into heat for the vanilla exchangers and turbines. Dark matter is the densest fuel the replication network can make — 25 GJ per unit — and it burns nowhere else: only the Annihilation Chamber and the **Annihilation Coil** can use it, and no vanilla reactor will accept it. The coil is the same ledger in a 2x2 machine: a burner-generator that turns one unit into 41.7 MW of electricity for ten minutes, with no heat pipes, no water and no exchangers behind it (research `Annihilation coil`, after `Annihilation power`).

### 14. What happens if I turn tenemut off mid-save?
Nothing is removed. The setting decides what a **new** map generates (and whether the Synthesizer exists); an existing map keeps its patches. Switching *to* `Synthesis only` on an old save leaves your ore in place — it only stops new maps from placing any.

### 15. Why can't I replicate \<item\>?
Weapons, armour, vehicles, vehicle equipment and personal equipment are excluded by design (solar panels and batteries are the exception); so are wires, remotes, planners, filled barrels, DMR's support machines (refiner, synthesizer, Accelerator Ring, Annihilation Chamber, Annihilation Coil) and internal sub-parts such as bearings, robot brains or warheads. Anything with no producing recipe and no ore patch is not a target either, and neither is anything whose replication would take more than an hour. The five replicator tiers are the exception: once their mirror tech is researched you can replicate a replicator instead of building it (each tier is priced on its own rung: 6.3 s, 12.6 s, 25.3 s, 50.6 s, 101.1 s). If the item is a science pack or comes from another overhaul, check that its technology is researched — mirrors follow *your* tech tree.

### 16. What are the DMR material packs, exactly?
Tenemut, the Dark Matter Scoop, the Dark Matter Transducer and the Nanophase Conduit are **items (instruments), not machines**. They are built from each other and consumed as science packs by the replication technologies, and tenemut is also the Accelerator Ring's raw input. Losing them from a save means losing research, not production.

### 17. Which settings should I touch?
Only two are worth changing on a first playthrough: `Tenemut source` (leave it on `Ore patches`) and `Research difficulty` (leave it on Easy (Fast)). `Require DMR material packs for research` (on by default) is the biggest difficulty knob — turning it off removes the tenemut/scoop/transducer/conduit research packs and lets vanilla science carry every replication tech.

### 18. Does the mod change my UPS, and is it multiplayer-safe?
One entity per replicator, no per-tick scripts for replication at all, and one generator pass at load — a factory of a few hundred replicators is fine, a few thousand is not. There are no runtime globals that depend on the mod's settings, so multiplayer desync is not a concern.

### 19. How is the replication menu organised?
Recipes inside a replicator are grouped by **category**, decided from the prototype itself (not from the item's name): **Machines · Power · Science packs · Modules · Ores · Plates & alloys · Intermediates · Fluids & chemicals · Logistics · Military · Fuels · Organic · Dark matter**. Planet-only items sit in their category too, not in a separate pile. Which replicator offers a recipe is decided by the same ladder its time uses — the science pack that unlocks it, plus the difficulty of its ingredient chain — so the tier-1 Simple Replicator is the red-science machine, and machines or military hardware start at tier 2.

### 20. How does the Quality Refiner work now?
Pick the refining recipe **once** for the item you want to improve, put the item in, and the machine does the rest: each attempt can move it one quality level up (5 % → uncommon, 2.5 % → rare, 1.25 % → epic, 1 % → legendary), destroy it (1 %), or leave it as it is. When a step succeeds the machine notices the item's new quality and switches its own recipe to the next step, so you never reselect anything. It is a normal crafting machine — 1 MW, real progress bar — and the time per attempt follows the item's tier: 1 s at tier 1 up to 5 s at tier 5. The recipes lock the input quality (a normal item cannot be pushed through the legendary step), and the ladder comes from the game's quality prototypes, so quality mods that add levels get refined too.
