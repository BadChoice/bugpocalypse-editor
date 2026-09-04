# Mission-editor drop authoring

## Scope

The mission editor authors deterministic pickups attached to the individual
enemies in a `spawnFormation` event. It does not simulate a kill, pickup
movement, collection, or resource effects; the mission preview only shows
which formation members have a drop.

The game already consumes this content. When a member dies, its configured
drop is spawned, then the runtime applies the pickup effect when collected.

## Content contract

`SpawnFormationEvent.drops` remains an optional array so events with no drops
write no `drops` key. Each entry uses the existing schema:

```json
"drops": [
  { "kind": "focus", "amount": 10, "memberIndex": 0 },
  { "kind": "coins", "amount": 5, "memberIndex": 4 }
]
```

Supported kinds are `health`, `focus`, `rage`, and `coins`. A drop is fixed
and guaranteed: the named enemy releases the stated amount when defeated.
No probability, condition, rarity, or loot-table fields are written in this
version.

`memberIndex` is a zero-based index into `formation.offsets()`, the same order
used when the game creates the formation members. This is deliberately index
based for every formation kind; stable member IDs are out of scope.

## Editor interaction

For a selected spawn-formation event, the inspector gains a **Drops** section.
The preview provides the primary target-selection interaction:

1. Click a visible formation member in the preview. Its existing selection
   treatment identifies the target and its zero-based index.
2. Click **Add Drop**. The editor adds one default drop to that member (use
   `focus`, amount `1`) and selects it in the Drops section.
3. Edit its kind and positive whole-number amount in the inspector, or remove
   it with that row's remove action.

The Drops section lists the configured drops in formation-member order, with
the member index and a readable label such as `Enemy 3`. Selecting a row also
selects the same member in the preview. If no member is selected, **Add Drop**
is disabled and explains that an enemy must be selected first.

There is no free-form index text field in the normal flow. This prevents an
author from targeting a nonexistent member while still keeping the persisted
schema compact and unambiguous.

## Validation and edits

An event is valid only when every drop satisfies all of the following:

- `amount` is an integer greater than zero.
- `memberIndex` is in `0 ..< formation.offsets().count`.
- Each member index occurs at most once; one enemy can release one drop.

The Add Drop action is disabled for members that already have a drop. On save,
the editor performs the same checks and blocks saving an invalid mission with a
specific error naming the event and member index.

Changing a formation can change its resolved member count. The editor must
revalidate drops immediately after any formation edit. Drops whose indexes are
now outside the resolved count stay visible as invalid rows, are marked in the
preview/inspector, and prevent save; they are never silently reassigned or
deleted. The author can remove the invalid drop or increase the formation's
member count. Reordering within a formation retains index-based assignments by
design.

## Preview presentation

Each member with a valid drop shows a small drop badge offset from its enemy
sprite. The badge uses the existing drop visual and is tinted by kind; a
compact numeric amount is shown when it fits without hiding the enemy. The
preview does not animate the pickup or modify its playback timeline.

An invalid drop target uses a warning indicator outside the formation rather
than pretending it is attached to a valid enemy. This makes content errors
visible before save.

## Implementation plan

1. Add pure editor helpers that resolve formation count, find a member's drop,
   add/remove/update a drop, and return validation diagnostics. Keep these
   helpers independent of SwiftUI so they can be unit tested.
2. Extend the spawn-event inspector with the Drops section and bind its edits
   through the existing `updateSelectedMissionEvent` path.
3. Extend `MissionPreview`'s formation rendering with member selection and
   static drop badges. Its selection state should be event-scoped so selecting
   a different timeline event cannot target a stale index.
4. Include drop validation in the existing mission validation/save path and
   add tests for valid assignments, duplicate targets, zero/negative amounts,
   and out-of-range indexes after a formation count is reduced.
5. Preserve the optional JSON behavior: remove the `drops` key when the final
   drop is removed, and retain existing valid authored drop arrays on load and
   save.

## Deferred: chance and weighted loot

Future drop systems may add chance rolls and weighted loot tables, but they
must not overload `DropDefinition`'s current guaranteed semantics. When that
work is scheduled, introduce a versioned/discriminated drop rule (for example,
`guaranteed`, `chance`, and `lootTable`) and define deterministic RNG seeding,
preview representation, validation, and balancing tools. The current UI should
not expose placeholder controls for those rules.
