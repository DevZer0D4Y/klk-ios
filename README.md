# KILL la KILL -IF- for iPhone and Mac

This fork of [nxnative](https://github.com/seedds/nxnative) adds **Kill la Kill The Game - IF** (`0100A3F00C536000`, 1.0.0) and lets the iPhone app import the game from your own dump. The game runs natively on Apple silicon: its own code on the chip, its graphics on Metal.

- **Resolution slider from 50 % to 200 %** (up to 3840x2160 docked, 2560x1440 handheld). The iPhone launcher calls it Resolution and starts at 85 %, which keeps the phone cooler; 100 % is the Switch's own size.
- **Fades fixed above 100 %**: the menus and intro logos no longer darken only the top-left of the screen.
- **Import on the iPhone**: the launcher opens even without the game. Under Game files, pick your own `.nsp`, `.nsz`, `.xci` or `.xcz` together with your console's `prod.keys` in the Files picker; the app unpacks the game into itself (about 6.5 GB) and Play turns on. A dump of another version is refused with a message.
- The launcher has the game's colours and title.

Nothing from the game is in this repository, and no app is published: the app is built from your own copy of the game, and the build contains the game's own code. Build it as nxnative's [How to play](#how-to-play) describes, cloning this fork instead (`git clone https://github.com/DevZer0D4Y/nxnative.git`) and with your Kill la Kill NSP in the game folder; the game's profile and notes are in [dm/games/0100A3F00C536000](dm/games/0100A3F00C536000/README.md).
