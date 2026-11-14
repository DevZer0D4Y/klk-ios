// The game files from the player's own dump, imported on the device (GameImport.m, importer.c): the launcher's Game files section (Launcher.swift) calls these.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The game files are in place and the game can start (main.m found them at launch or after an import)
BOOL dm_game_files_ready(void);
// Whether this app can import its game files (one program; a game of several programs keeps them in the app)
BOOL dm_import_available(void);
// Starts importing in the background: game is the NSP / NSZ / XCI / XCZ the player picked (read in place), keys the prod.keys picked with it or nil (then the
// one kept from an earlier pick, or one in Documents), titleKeys an optional title.keys. NO with why in *error when it cannot start
BOOL dm_import_start(NSURL *game, NSURL *_Nullable keys, NSURL *_Nullable titleKeys, NSString *_Nullable *_Nullable error);
// 0 idle, 1 running, 2 done (the files are in place), 3 failed; fraction 0..1 of the current phase, phase what it is doing, error why it failed
int dm_import_state(double *fraction, NSString *_Nullable *_Nullable phase, NSString *_Nullable *_Nullable error);
void dm_import_cancel(void);
// The game files in Documents the player put there through the Files app (On My iPhone → this app): a dump and prod.keys, nil when there is none
NSURL *_Nullable dm_import_found_dump(void);
// Whether a prod.keys is kept (picked earlier) or in Documents
BOOL dm_import_have_keys(void);
NS_ASSUME_NONNULL_END
