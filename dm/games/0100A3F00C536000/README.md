# Kill la Kill The Game - IF (`0100A3F00C536000`)

Base game v0 (display version 1.0.0), SDK 7.4.0, the Japanese release (its menus offer English). The ExeFS holds `main`, `subsdk0` and `sdk`. Arc System Works' engine on **NVN**. The NSP script's provisional profile booted it on the Mac with no host change; with the render size stub and the fade fix below it plays on the Mac (Episode 1 onward and the tutorial fight at 60 fps) and on the iPhone.

## What it needs

| Setting | Where | Why |
|---|---|---|
| 4 GB layout: `mem_reserve 0x100000000`, `mem_alias 0x10000000`, `mem_stack 0x10000000`, `app_pool 0xCD500000` | [`game.tsv`](game.tsv) | no system resource; `main` sets a heap of the pool − 64 MB, which the 3.25 GB heap region holds |
| `render_base 1920x1080 1280x720` | `game.tsv` | the launcher shows the render scale in pixels for the console mode chosen |
| render size stub and screen fade fix | [`patches.py`](patches.py), `MATCH_FRAME_STEP` | [Rendering](#rendering) |
| `launcher_theme.json` | [`launcher_theme.json`](launcher_theme.json) | the iOS launcher's colours and title, Render scale shown as "Resolution", and its iOS default (0.85) |

## Versions

- **Current: v0 (1.0.0) registered** (main `d5413d9ec7c47e65cf6585647d92701d`). No update is registered: none was at hand. Other regions' builds get the stubs only where their functions have the same fingerprints.

## Rendering

- **Current: render scale 0.5 to 2.0.** The game keeps its view sizes in a table of 0x30-byte entries (1.0.0 `main+0x464ae0`); entry 0 holds, from +0x40, the display size (1920x1080 docked, 1280x720 handheld), the render size, the render size aligned up, the 2D canvas (1920x1080) and its half. One leaf function writes the render size (`main+0x7dab0`, `setter(index, float size[2], alignment)`), called at start-up (`main+0x5be2c`) and on a console mode change (`main+0x5c960`), both with index 0 and alignment 8. The stub runs it with the size times `DM_RENDER_SCALE` (state +0x10), each side rounded to a multiple of 8 (1.30 docked: 2496x1408). The whole frame follows the render size, the 2D layer and the HUD included.
- **Resolved: a darker box over the menus and intro logos above 1.0.** The screen fade (`main+0x16f750`) draws its rectangle from (0, 0) the size of entry 0's display size (always 1920x1080) and its 2D drawing (`main+0x5b0c0`) turns it into clip space by the render size: at 1.30 it covered 1920x1080 of 2496x1408, so fades darkened only the top-left of the frame. The fade now takes the render size (its call at +0x78 goes to the render size getter), equal to the display size at 1.0 docked. Found with `DM_NVN_PASSDUMP` (the fade is the last draw of the frame, a passthrough vertex shader `dc62849aafd20243`) and `DM_PROBE_WATCH` on its vertex buffer (written through `main+0x52770` from the fade).
- **Measured (Mac, tutorial fight):** 1.0: GPU p50 6.8 ms, 60 fps, CPU 0.16 W; 0.5 (960x544): 4.2 ms; 2.0 (3840x2160): 36 ms (25 fps) with another GPU load on the same machine. Heat comes from the GPU; the iOS launcher defaults to 0.85.

## Playing on the iPhone

- The game files can be imported on the device: the launcher's Game files section reads the player's own NSP / NSZ / XCI / XCZ and prod.keys in place and unpacks the RomFS into the app (`dm/ios/Sources/importer.c`, `GameImport.m`); a dump whose `main` is another build is refused with a message. It needs about the game's size free (6.5 GB of RomFS) besides the dump.

## Running it on the Mac

- Practice, tutorial fight: start, wait about 32 s, A, 8 s, A, 5 s, Right, Right, A, A, 15 s, A.
