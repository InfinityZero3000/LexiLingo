# Affordable Shop And Avatar Catalog Design

## Goal

Make the gem shop useful at the current reward rate by lowering prices,
expanding functional consumables, and adding a large catalog of exclusive
avatars that users can purchase and equip.

## Economy

Existing free profile avatars remain free. Existing shop prices are reduced:

- Hint Pack (5): 12 gems
- Double XP (1 hour): 25 gems
- Streak Freeze: 25 gems
- Heart Refill: 15 gems

New consumables add useful price steps:

- Hint Pack (10): 20 gems
- Double XP (2 hours): 40 gems
- Double XP (4 hours): 65 gems
- Triple XP (1 hour): 50 gems
- Streak Freeze Pack (3): 60 gems

Exclusive avatars use the existing DiceBear Adventurer visual style. Thirty-six
new seeds are split across 10, 15, and 20 gem tiers. Avatar purchases are
permanent and repeated purchases are rejected.

## Catalog Synchronization

An Alembic migration updates existing prices and upserts all new catalog rows.
The admin sample-data endpoint uses the same catalog definitions so fresh and
existing environments stay aligned.

Shop API fields remain compatible with the database model. Flutter derives
display categories from `item_type` and reads duration and effect metadata from
the `effects` object.

## Consumable Effects

Double and triple XP use the existing timed inventory mechanism. Streak packs
add their configured quantity to the user's freeze count.

Lesson attempts gain `bonus_hints`. Hint packs add bonus hints to the user's
currently active lesson attempt. Heart refill restores the active attempt to
three lives. An item cannot be consumed when no unfinished lesson attempt
exists, preventing a successful response with no gameplay effect.

## Avatar Ownership And Equip

Avatar shop items use `item_type = avatar`, their DiceBear URL as `icon_url`,
and `effects.avatar_url` as the authoritative equip value.

After purchase, Flutter offers an "Equip now" action. A dedicated authenticated
endpoint verifies that the user owns the requested avatar inventory item before
updating `users.avatar_url`. Equipping does not decrement inventory.

The profile avatar picker combines the existing free presets with avatar URLs
owned in inventory. Purchased avatars therefore remain selectable later.

## UI

Shop cards render `icon_url` for avatar items, including SVG support. Category
tabs correctly classify power-ups, boosts, cosmetics, and special items.
Purchase dialogs use the real item image when available.

## Verification

- Backend tests cover catalog pricing, item mapping, real hint/heart effects,
  avatar ownership validation, permanent equip behavior, and duplicate avatar
  purchase prevention.
- Flutter tests cover API-to-entity mapping and owned-avatar extraction.
- Run focused pytest and Flutter tests, then backend and Flutter static checks.
