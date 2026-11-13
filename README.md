# StarWatcher

**Algalon the Observer helper for World of Warcraft 3.3.5a (ChromieCraft / AzerothCore)**

Made by **Jakunda**.

## License

Free for everyone: copy it, use it, change it and share it, no restrictions.

## What is it?

StarWatcher is an addon for the Algalon the Observer fight in Ulduar. It follows the Collapsing Stars of the fight and tells you when each one will die, and whether that moment is safe.

It comes in two versions, in two folders:

- **StarWatcher** (full): for the players who kill the stars.
- **StarWatcher-Lite**: for the rest of the raid.

## What does it do?

Both versions show, during the fight:

- the timers of the next star wave, the Big Bang and the Cosmic Smash;
- the Collapsing Stars with their health and the estimated time each one dies;
- for each star, whether its death is safe, or too close to a Cosmic Smash, to another star or to a Big Bang (3 s for the Cosmic Smash, 6 s for stars and Big Bang by default, both adjustable);
- a perfect window setting (2, 3 or 4 seconds before the end of the Big Bang cast), where stars may die together.

The full StarWatcher adds, for the star killers:

- the safe windows of the fight, a strategy for 2 or 3 stars per minute, and a short to-do list of what to do next;
- a rolling timeline of the fight;
- the Curse of Doom window for the warlocks: when to cast it and how much damage the star must take so the curse kills it at the right moment;
- raid markers on the stars: off, automatic, or dynamic (a star is marked while it is correctly placed).

## Installation

1. Copy **one** of the folders, `StarWatcher` or `StarWatcher-Lite`, into the `Interface\AddOns` folder of your game.
2. Restart the game (or log in again).

Use **StarWatcher** if you kill the stars, and **StarWatcher-Lite** for other members of the raid. They can be installed together, but there is no need.

## Quick start

1. Type `/sw config` (full) or `/swl config` (Lite). The addon windows appear while the configuration is open, so you can drag them where you want them (**Shift + drag** works at any time too). Choose your settings, then close the configuration: the windows disappear until the fight.
2. Type `/sw test` or `/swl test` to simulate a fight and see the addon working. Type `/sw reset` or `/swl reset` to end the test.

The addon shows itself automatically during the Algalon fight.

## Documentation

The full guide is the PDF **StarWatcher-Guide.pdf**, at the root of this folder (next to this file): the fight and its timeline, the strategies, how the addon works, the interface, every setting and every command. It is not meant to be copied into the game; only the `StarWatcher` and `StarWatcher-Lite` folders are.
