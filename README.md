# LootFilter v2.0.0

Automatic loot filter for World of Warcraft 1.12.1 (Vanilla).

## Features

- Auto-delete items by quality (grey, white, green, etc.)
- Blacklist specific items for deletion
- Whititelist items to always keep
- Low performance impact
- Debug mode for safe testing
- NAMPOWER support for improved performance

## What's New in v2.0.0

### Performance Improvements
- **Pre-filtering system** - Items filtered before processing, reducing bag iterations by up to 80%
- **Event-driven architecture** - No polling, responds only to game events
- **NAMPOWER integration** - Uses optimized GetBagItems() API when available
- **Early exit optimizations** - Zero CPU usage when idle

### Bug Fixes
- Fixed broken timer system (added proper OnUpdate handler)
- Fixed inverted quality filter logic
- Fixed infinite retry loop for non-filtered items
- Fixed duplicate event handling

### Technical Changes
- Complete code refactoring for Lua 5.0 optimization
- Cached table operations for better performance
- Simplified string matching (single string.lower call)
- Removed legacy code and dependencies

## Installation

1. Download latest release
2. Extract to `Interface/AddOns/LootFilter/`
3. Restart WoW or type `/reload`

## Usage

| Command | Description |
|---------|-------------|
| `/lootf` | Open settings |
| `/lootf on` | Enable filter |
| `/lootf off` | Disable filter |
| `/lootf status` | Show settings |
| `/lootf debug` | Toggle debug mode |
| `/lootf item <name>` | Add to keep list |
| `/lootf itemd <name>` | Add to delete list |
| `/lootf quality <1-8>` | Toggle quality filter |

## Quality Numbers

| # | Quality |
|---|---------|
| 1 | Grey (Crap) |
| 2 | White (Common) |
| 3 | Green (Uncommon) |
| 4 | Blue (Rare) |
| 5 | Purple (Epic) |
| 6 | Orange (Legendary) |
| 7 | Red (Artifact) |
| 8 | Quest Items |

## Requirements

- World of Warcraft 1.12.1 (Vanilla)
- Optional: [NAMPOWER](https://gitea.com/avitasia/nampower) (improves performance)

## Authors

- Original addon: meter@darkenbane.com
- v2.0.0 optimization: unS0uL

## License

Open source - feel free to modify and improve.

## Disclaimer

This project is an independent community-driven modification for World of Warcraft 1.12.1. It is not affiliated with, endorsed by, or connected to Blizzard Entertainment, Turtle WoW administration, or any other private server entity. The code is provided "as is" for educational and interface enhancement purposes only.
