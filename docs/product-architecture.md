# Bugpocalypse Editor: Product and Architecture Specification

Status: approved for implementation (v1.0)  
Date: 2026-09-04  
Repositories:

- `Bugpocalypse`: game code, Godot project, authored content, and assets
- `bugpocalypseEditor`: macOS SwiftUI content editor

## 1. Product summary

Bugpocalypse Editor is a local, single-user macOS application for visually
authoring the Bugpocalypse campaign. Its first complete milestone lets the
developer create and save a full world and its missions without manually
editing JSON.

The editor works directly against a selected game checkout. JSON under
`godot/assets` remains the source of truth; the editor is a safe, visual client
for those files rather than a separate content database.

Feature priority is:

1. World authoring and exploration simulation
2. Mission authoring and timeline preview
3. Reusable formation and path authoring
4. Background authoring

Animation and VFX authoring are not part of this specification. Existing game
code and asset conventions remain responsible for them until a future need
justifies a separate design.

## 2. Success criteria

The first product milestone is complete when the developer can:

1. Open an arbitrary local Bugpocalypse checkout.
2. Create, edit, rename, validate, and save a world.
3. Place cells visually on the isometric grid.
4. Simulate discovery, scouting, mission completion, and star progression.
5. Create a mission cell and have a correctly named draft mission created
   automatically in `godot/assets/missions`.
6. Configure a complete mission without opening its JSON.
7. Create and reuse formations and paths from separate content files.
8. Preview mission geometry and timing with real enemy sprites when available.
9. Save deterministic JSON directly into `godot/assets`.
10. Launch the selected mission in the game for authoritative playtesting.

## 3. Current system

### Game runtime

- The game is a Swift 6.3 package built on SwiftGodot and targets macOS 14 and
  iOS 17.
- Godot uses a `640 x 360` design viewport.
- Shipping definitions currently live under:
  - `godot/assets/worlds`
  - `godot/assets/missions`
  - `godot/assets/backgrounds`
- Source art lives under top-level `assets`. Runtime sprite art is packed into
  `godot/assets/textures/textures.1.png` and `textures.plist`.
- Missions currently support formation spawns and camera zoom events.
- Existing formations are line, slotted line, V, staggered grid, and arc.
- Existing paths are straight, sine, and normalized waypoints.
- Definition structs are mostly game-internal and `Decodable` only.
- Validation exists, but is distributed between loaders and runtime factories.
- Enemy identifiers are accepted through a string switch with several aliases.

### Editor

- The editor repository currently contains the default SwiftUI/SwiftData macOS
  application template.
- App Sandbox is enabled in the template and user-selected files are read-only.
- There is no game-package dependency or domain implementation yet.

### Repository state

The game repository may contain unrelated uncommitted code and asset changes.
Editor implementation and automated migrations must only touch explicitly
targeted content and package files. They must never clean or rewrite unrelated
worktree changes.

## 4. Product decisions

- The only expected user is the game developer/owner.
- macOS is the only required editor platform.
- App Sandbox will be disabled. The app needs local repository, Trash, command,
  and Godot launch access.
- Save writes directly to canonical locations under `godot/assets`; there is no
  separate export or staging operation.
- Structurally invalid documents cannot be saved.
- JSON is deterministic, pretty-printed, sorted by key, and newline-terminated.
- Editor and game schemas move in lockstep. Forward and backward compatibility
  are not required.
- Raw JSON editing is not included.
- External changes always produce a Reload Disk Version / Keep Editor Version
  choice; the editor never silently overwrites them.
- Deleting content checks references, asks for confirmation, and moves the file
  to macOS Trash.
- IDs are changed only through a repository-wide Rename operation.
- Enemy choices come from a shared Swift catalogue.
- Enemy aliases are read during the initial migration and rewritten to a single
  canonical identifier. New aliases are not authored.
- Native preview covers geometry and timing. Combat remains authoritative in
  Godot.
- Draft content is playable by the game.

## 5. Architecture

### 5.1 Package boundary

Add a Foundation-only product and target to the existing game package:

```text
Bugpocalypse/BugpocalypseSwift
├── BugpocalypseContent (new library product)
│   ├── public Codable definitions
│   ├── content status and references
│   ├── stable enums and catalogues
│   ├── structured diagnostics and validation
│   ├── deterministic JSON coding
│   └── pure formation/path/timeline geometry
└── BugpocalypseSwift (existing runtime product)
    ├── depends on BugpocalypseContent
    └── adapts definitions to SwiftGodot

bugpocalypseEditor
├── local package dependency on BugpocalypseContent
├── repository/document services
├── editor feature modules
└── SwiftUI/CoreGraphics preview renderers
```

`BugpocalypseContent` must not import SwiftGodot, SwiftUI, AppKit, or SwiftData.
Public model types should conform to `Codable`, `Equatable`, and `Sendable`
where applicable.

The editor references this package from the selected sibling/local game
checkout. A third repository is unnecessary.

### 5.2 Shared models

Replace optional-field bags with typed sum types while preserving concise JSON.
Formation, path, timeline action, cell kind, reward, objective, and completion
variants each have type-specific payloads.

Example Swift direction:

```swift
public enum FormationDefinition: Codable, Equatable, Sendable {
    case line(LineFormation)
    case slottedLine(SlottedLineFormation)
    case v(VFormation)
    case staggeredGrid(StaggeredGridFormation)
    case arc(ArcFormation)
    case freeform(FreeformFormation)
}
```

All top-level authored documents contain:

- `schemaVersion`
- stable `id`
- `authoringStatus`: `draft` or `ready`

The v1 implementation migrates the current schema from version 1 to version 2.
Version 2 is the only version written afterward. An exact schema mismatch fails
clearly because the editor and game are updated together.

### 5.3 Draft and ready content

Every world, mission, formation, path, and background has an authoring status.
Both statuses are loadable and playable by the game.

Validation has two classes:

- **Structural errors** mean the document cannot be interpreted safely: illegal
  values, duplicate IDs, broken references, invalid override fields, or invalid
  topology. They always block Save.
- **Readiness issues** mean content is legal but unfinished: placeholder names,
  an empty mission timeline, no useful rewards, or incomplete balancing. They
  appear as warnings on drafts and block saving a document as `ready`.

New draft documents always receive structurally valid defaults. The schema does
not become a collection of optional fields merely to support drafts.

Drafts are clearly marked in the sidebar, canvas, inspector, and world cells.
The game may play them normally; authoring status is informational outside the
editor.

### 5.4 Repository access

The editor opens one game checkout at a time. A valid root contains:

- `godot/project.godot`
- `godot/assets`
- `BugpocalypseSwift/Package.swift`

Only the selected root path, recent documents, and UI preferences are persisted
through SwiftData or app preferences. World and mission data never enters
SwiftData.

The repository layer provides:

- content discovery and indexing;
- typed decoding and validation;
- dirty-state tracking and undo grouping;
- external-change observation;
- atomic replacement on save;
- reference search and repository-wide rename;
- recoverable deletion through macOS Trash;
- explicit game/Godot command launching.

Save and Save All are explicit. Saving does not rebuild atlases or launch Godot
as a hidden side effect.

### 5.5 External change policy

When an open file changes on disk, present:

- **Reload Disk Version**, discarding the editor draft after confirmation; or
- **Keep Editor Version**, retaining the draft and requiring an explicit later
  Save before it replaces the disk version.

The prompt appears whether the editor document is clean or dirty. It identifies
the exact file and modification time.

## 6. Content schema direction

### 6.1 World topology

Ordinary graph topology is derived from isometric coordinates. Two occupied
cells are neighbours when their coordinates share a full grid edge according to
`WorldGridCoordinate.neighbours`.

The version 2 world schema removes per-cell ordinary `neighbourIDs`. Exceptional
non-adjacent connections are stored once at world level:

```json
"extraConnections": [
  { "a": "broken_bridge_west", "b": "broken_bridge_east" }
]
```

Exceptional connections are always bidirectional. Endpoints must exist, differ,
and not duplicate an ordinary edge or another exceptional connection.

Moving a cell automatically changes its ordinary neighbours. Exceptional
connections remain attached to cell IDs and are shown distinctly on the canvas.

More than one cell may be initially visible.

### 6.2 Mission ownership and creation

A mission definition belongs to exactly one world cell across the open
repository. Cross-document validation rejects duplicate ownership.

Each world has a `missionNamespace`, initially `location1` for the existing
world. Creating a mission cell:

1. Finds the next unused positive mission number in that namespace.
2. Creates ID `<namespace>_<number>`.
3. Creates `godot/assets/missions/<namespace>/<number>.json`.
4. Writes a structurally valid draft mission template.
5. Adds its ID/resource reference to the world cell.
6. Opens the new mission in an editor tab.

The operation is one undoable editor command. If a filesystem step fails, it
must not leave the world reference half-created.

### 6.3 Stars and rewards

Bugpocalypse uses stars as world progression rather than maintaining separate
1/2/3-star reward bundles on every mission.

- Each ready mission defines exactly three star objectives. Each satisfied
  objective awards one star; mission completion must be one of them.
- The best result for a mission contributes 1–3 stars to its world total.
- A mission cell has one first-completion reward bundle.
- Replaying a mission does not repeat that bundle.
- A world contains manually authored star milestones and rewards.
- The editor suggests milestone thresholds from mission count, but never writes
  or changes them without explicit acceptance.
- A world may define an optional all-stars reward.
- When replay improves the best star result, newly crossed world milestones
  become claimable.

Example direction:

```json
{
  "starMilestones": [
    { "stars": 6, "items": [{ "resourceId": "coins", "amount": 250 }] },
    { "stars": 12, "items": [{ "resourceId": "upgrade_parts", "amount": 4 }] }
  ],
  "allStarsReward": [
    { "resourceId": "blue_key", "amount": 1 }
  ]
}
```

The editor displays earned stars, available milestones, and unclaimed rewards
inside exploration simulation.

This adapts Dead Ahead's separation between completion rewards and cumulative
star progression while retaining Bugpocalypse's objective-based stars. Reference
material: [Dead Ahead locations](https://deadahead.wiki.gg/wiki/Locations),
[Star Reward](https://deadahead.wiki.gg/wiki/Star_Reward), and
[Location 1](https://deadahead.wiki.gg/wiki/Location_1).

### 6.4 Reusable formations and paths

Reusable definitions live in individual files, optionally grouped into folders:

```text
godot/assets/formations/**/*.json
godot/assets/paths/**/*.json
```

A mission spawn references a base definition and may carry typed overrides:

```json
"formation": {
  "resourcePath": "res://assets/formations/basic/vertical_line.json",
  "overrides": {
    "count": 8,
    "spacing": 42
  }
},
"path": {
  "resourcePath": "res://assets/paths/basic/straight_left.json",
  "overrides": {
    "speed": 120
  }
}
```

Rules:

- Overrides are limited to fields valid for the base definition's kind.
- The inspector marks every override and offers Reset to Base.
- Editing a base is an intentional global change. The editor shows all usages
  before saving it.
- **Duplicate and Edit** creates a new reusable definition.
- **Promote Overrides to New Definition** creates a new base and repoints the
  selected event.
- Reusable definitions cannot inherit from other reusable definitions. There is
  one base plus one instance-override layer only.

The new `freeform` formation stores explicit member offsets in gameplay pixels
relative to the spawn anchor. Named member IDs are supported so drops and future
leader mechanics do not depend only on fragile numeric indexes.

Path development priority after existing paths is:

1. Bézier
2. Per-waypoint timing and easing
3. Loops
4. Orbit
5. Charge/steer
6. Per-member delays

### 6.5 Enemy catalogue

Enemy IDs remain defined in Swift. `BugpocalypseContent` exposes a public
catalogue containing canonical ID, display name, preview asset name, and editor
grouping metadata. Combat construction remains in the SwiftGodot runtime.

The schema migration converts existing aliases to one canonical ID. The editor
only writes canonical IDs and uses the catalogue for pickers and validation.

### 6.6 Backgrounds

Backgrounds remain reusable top-level documents. A layer contains its asset
candidates, horizontal scroll speed, Z index, and center-relative vertical
offset. The UI labels the existing `y` field as **Center Y Offset**.

The runtime currently resolves layer art from the packed atlas. The editor
indexes both source assets and `textures.plist`, and distinguishes artwork that
exists at source from artwork actually available to the game.

## 7. Editor experience

### 7.1 Window structure

Use one main window with editor tabs:

```text
┌──────────────┬────────────────────────────────────┬──────────────────┐
│ Project      │ Canvas / timeline / simulation     │ Inspector        │
│ Worlds       │                                    │ selection fields │
│ Missions     │                                    │ diagnostics      │
│ Formations   │                                    │ usages           │
│ Paths        │                                    │                  │
│ Backgrounds  │                                    │                  │
└──────────────┴────────────────────────────────────┴──────────────────┘
│ file path | draft/ready | dirty | errors/warnings | Save | Play      │
└───────────────────────────────────────────────────────────────────────┘
```

- Sidebar content is searchable and grouped by type/folder.
- The center adapts to the selected feature.
- The inspector uses typed controls and displays units.
- Diagnostics navigate directly to the relevant object and field.
- Numeric fields support typing, arrow increments, and mouse scrubbing.
- Standard Undo/Redo covers field edits, timeline operations, topology changes,
  creates, and reference changes.

### 7.2 World editor

- Render the isometric grid with real world tile art.
- Add, duplicate, move, and delete cells.
- Automatically display edge-derived connections.
- Add/remove exceptional bidirectional connections with a distinct style.
- Edit cell kinds, initial visibility, scouting cost, mission ownership, and
  first-completion rewards.
- Overlay IDs, coordinates, kinds, stars, draft state, unreachable regions, and
  validation diagnostics.
- Create draft missions automatically from new mission cells.
- Suggest—but do not automatically apply—star milestone thresholds.

### 7.3 Exploration simulation

Simulation uses an isolated, disposable progression state and never writes the
player's real save.

The developer can:

- reset to initial visibility and starting scout energy;
- scout available frontier cells;
- mark missions complete with 1, 2, or 3 stars;
- replay with an improved star result;
- inspect automatically revealed cells;
- inspect earned/claimable star milestones and rewards;
- inspect why a cell is visible, scoutable, or unreachable.

### 7.4 Mission editor

- Structured metadata, authoring status, completion, background, and star
  objective inspectors.
- Horizontally scrollable typed event timeline.
- Simultaneous events are allowed.
- Snapping is configurable and defaults to 0.25 seconds.
- Multi-selection, duplication, cross-mission copy/paste, and bulk time shifting
  are required in the first visual timeline release.
- Spawn events select reusable formations and paths, then expose visible typed
  overrides.
- Drop assignment uses zero-based member indices. An event permits one
  guaranteed drop per member; the index must resolve inside the formation's
  current member count. See `drop-authoring.md` for the editor contract and
  deferred probabilistic-loot design.

### 7.5 Mission preview

The native preview is a deterministic `640 x 360` geometry-and-timing simulator:

- play, pause, restart, scrub, step, and playback-speed controls;
- formation member positions;
- straight, sine, waypoint, and later path sampling;
- spawn bounds, camera bounds, and zoom event framing;
- background layers where useful for spatial context;
- real enemy sprites resolved from the atlas, with labelled placeholders when
  missing;
- member IDs/indices, anchors, path traces, and off-screen guides.

It does not simulate attacks, health, collisions, pickup release/collection,
abilities, or combat AI. It does show static badges for authored drops. Those
systems are tested through the real game.

### 7.6 Formation/path editor

- Shared canvas for standalone definitions and mission references.
- Drag handles synchronized with numeric inspector values.
- Handles for spacing, radius, angles, grid dimensions, freeform members, and
  waypoints.
- Toggle member labels, path traces, collision-size guides, and sampled times.
- Show definition usages throughout the repository.
- Support Duplicate and Edit, Reset Override, and Promote Overrides.

### 7.7 Background editor

- Ordered layer list with visibility and solo controls.
- Real-time `640 x 360` parallax preview.
- Existing-asset picker backed by source and atlas indexes.
- Layer asset candidates, scroll speed, Z index, and center Y offset.
- Seed control displays the selected deterministic variant and all candidates.
- Missing atlas entries are errors; possible seams or inconsistent dimensions
  are warnings.

## 8. Game integration

Add explicit debug launch support for a selected mission resource path. The
exact transport may be a command-line argument or environment variable, but it
must bypass normal campaign selection without changing player progression.

The editor's Play menu provides:

- **Run Selected Mission**
- **Run Game Normally**
- **Open Project in Godot**

Commands display their executable, project path, selected mission, running
state, exit result, and captured error output. Launching is explicit and never
part of Save.

## 9. Validation

Validation returns all structured diagnostics rather than throwing only the
first failure:

```swift
public struct ContentDiagnostic: Identifiable, Equatable, Sendable {
    public let severity: Severity
    public let code: String
    public let message: String
    public let location: ContentLocation
}
```

Layers:

1. Exact-version JSON decoding.
2. Local type semantics and finite/legal values.
3. Cross-document IDs and resource references.
4. World topology, unique mission ownership, and milestone validation.
5. Formation/path reference and override validation.
6. Asset and atlas availability.
7. Readiness checks and experience heuristics.
8. Optional runtime smoke loading through the game.

Errors block Save. Warnings do not block draft Save. Readiness warnings become
blocking errors when saving as `ready`.

## 10. Persistence and safety

- Each document has one in-memory draft and one last-read disk revision.
- Save validates the full affected reference graph before writing.
- Multi-file operations such as Rename and automatic mission creation stage all
  writes first, then replace files as one coordinated operation where possible.
- A failed multi-file operation reports exactly what changed and offers recovery;
  it never silently claims success.
- No command uses a broad or inferred deletion target.
- Deletion uses Trash and reports affected references.
- Save does not modify unrelated files or run formatting across the repository.
- Canonicalization affects only explicitly saved documents.

## 11. Testing strategy

### Shared content package

- Exact-version Codable round trips for every definition variant.
- Migration fixtures from the current version 1 files to version 2.
- Structural and readiness diagnostics.
- Pure formation geometry and path sampling.
- World coordinate-neighbour derivation and exceptional links.
- Reward milestones and exploration-state transitions.
- Override application and invalid-override rejection.
- Canonical enemy ID migration.

### Editor

- Project discovery and indexing.
- Atomic writes and external-change choices.
- Reference search, rename, and recoverable deletion.
- Draft/ready state transitions.
- Automatic mission naming and rollback on failure.
- Undo/redo for model and canvas commands.
- Snapshot tests for representative canvases.
- UI tests for open, edit, validate, save, rename, conflict, and playtest flows.

### Repository fixtures

Every checked-in world, mission, formation, path, and background is decoded and
validated in tests. The game package and editor use the same fixture expectations.

## 12. Delivery plan

### Slice 0: shared content foundation

- Add the `BugpocalypseContent` library target and product.
- Introduce public typed definitions, `authoringStatus`, diagnostics, JSON coding,
  and shared enemy catalogue.
- Add reusable formation/path reference and typed override models.
- Move pure geometry out of SwiftGodot-dependent types.
- Update the game runtime to consume the shared models.
- Migrate checked-in version 1 JSON and enemy aliases to version 2.
- Add fixture and geometry tests.
- Add the local package dependency to the editor.

### Slice 1: repository workspace

- Replace the SwiftData sample application.
- Disable App Sandbox.
- Open and remember one valid game root.
- Index top-level content and atlas entries.
- Implement tabs, structured inspectors, status, diagnostics, dirty state,
  Undo/Redo, external-change prompts, atomic Save, Rename, and Trash.

### Slice 2: world editor

- Build isometric cell editing and automatic edge topology.
- Add exceptional bidirectional connections.
- Implement mission-cell creation and draft mission generation.
- Implement completion rewards, manual milestone rewards, and suggestions.
- Add exploration/star/reward simulation.
- Meet the complete-world half of the product milestone.

### Slice 3: mission editor

- Build mission metadata/objective/completion editing.
- Build the timeline with snapping, multi-select, copy/paste, and bulk shifting.
- Add formation/path selection and typed override inspection.
- Build deterministic geometry/timing preview with real sprites.
- Add game debug launch and the Play menu.
- Meet the complete-mission half of the product milestone.

### Slice 4: formation/path editor

- Build standalone parametric and freeform formation editing.
- Build standalone path editing.
- Add usage search, global-change warnings, duplicate, reset, and promote flows.
- Add new path kinds in the approved priority order as missions require them.

### Slice 5: background editor

- Build layer editing, asset selection, seeded variants, parallax preview, and
  atlas/seam diagnostics.

## 13. Acceptance checks

Before declaring the first milestone complete:

- A new world can be created, fully configured, saved, reopened, and loaded by
  the game without manual JSON changes.
- A mission cell creates a unique draft mission and is rolled back cleanly if
  any file operation fails.
- A draft can be saved and played; an incomplete document cannot be marked ready.
- Ordinary world connections update after moving cells; exceptional connections
  remain bidirectional and ID-based.
- Exploration simulation reproduces runtime discovery and reward behavior.
- A new mission can be fully authored and previewed without manual JSON changes.
- One reusable formation and path can serve multiple events with visibly
  different overrides.
- Repository-wide Rename updates all references or performs no writes.
- Structural errors block Save with navigable diagnostics.
- External edits cannot be overwritten without a Reload/Keep choice.
- Saved JSON produces stable repeat saves with no diff.
- Run Selected Mission opens the intended definition in the real game.

## 14. Deferred work

- Animation and VFX authoring or preview tooling
- Atlas generation or packing
- Full combat simulation inside the editor
- Cloud sync and multi-user collaboration
- App Store distribution and sandbox restoration
- Raw JSON editing
- Git commit, branch, or merge management
- Forward/backward schema compatibility

## 15. Decision record

| Area | Decision |
| --- | --- |
| User | Single developer, local-only |
| Priority | World, mission, formation/path, background |
| Source of truth | JSON in the selected game's `godot/assets` |
| Save | Explicit, direct, atomic, deterministic |
| Sandbox | Disabled |
| Invalid content | Structural errors block Save |
| Drafts | Persisted on every top-level document and playable by the game |
| Schema compatibility | Editor and game move in lockstep |
| Shared code | Foundation-only product inside the game package |
| World topology | Derived from shared edges plus explicit bidirectional exceptions |
| Starting cells | Multiple initially visible cells allowed |
| Mission ownership | One world cell per mission |
| New mission | Automatically named and created as a draft |
| Rewards | First-completion bundle plus manual world star milestones |
| Formations/paths | Reusable files with one explicit instance-override layer |
| Formation freedom | Parametric and freeform definitions |
| Enemies | Canonical shared Swift catalogue |
| Preview | Native geometry/timing; authoritative gameplay in Godot |
| Play menu | Selected mission, normal game, or open Godot project |
| Animation/VFX | Deferred and removed from current scope |
| Raw JSON | Not included |
