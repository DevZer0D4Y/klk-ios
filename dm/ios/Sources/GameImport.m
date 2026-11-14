// Importing the game files on the device (GameImport.h): the player picks their own dump (NSP / NSZ / XCI / XCZ) and prod.keys in the Files picker, importer.c decrypts the
// program NCA of this app's title and writes its RomFS into Documents/.import, its ExeFS is checked against the build this app was made for (the rewriter table's BUILD_ID), and
// the RomFS then replaces Documents/romfs. main.m looks for the game files again (front_ios_boot_retry), so Play works without restarting the app. Key values are never logged.
#import <UIKit/UIKit.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include "game_profile.h"
#include "importer.h"
#import "GameImport.h"

int front_ios_boot_ok(void);
int front_ios_boot_retry(void);   // main.m: locate the game files again after an import

static ImportJob g_job;
static _Atomic int g_state;   // 0 idle, 1 running, 2 done, 3 failed
static NSString *g_error;

static NSString *docs(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0]; }
static NSString *keys_dir(void) {   // Library/Application Support/keys: a picked prod.keys, kept for later imports and not shown in Files
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"keys"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

BOOL dm_game_files_ready(void) { return front_ios_boot_ok() != 0; }
BOOL dm_import_available(void) {
#if defined(DM_GAME_MULTI)
    return NO;
#else
    return YES;
#endif
}

// prod.keys: the kept one, else one in Documents (prod.keys, keys.txt, any *.keys but title.keys)
static NSString *find_keys(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *kept = [keys_dir() stringByAppendingPathComponent:@"prod.keys"];
    if ([fm fileExistsAtPath:kept]) return kept;
    for (NSString *n in @[@"prod.keys", @"keys.txt"]) { NSString *p = [docs() stringByAppendingPathComponent:n]; if ([fm fileExistsAtPath:p]) return p; }
    for (NSString *f in [fm contentsOfDirectoryAtPath:docs() error:nil])
        if ([f.pathExtension.lowercaseString isEqualToString:@"keys"] && [f.lowercaseString hasPrefix:@"title"] == NO) return [docs() stringByAppendingPathComponent:f];
    return nil;
}
BOOL dm_import_have_keys(void) { return find_keys() != nil; }
NSURL *dm_import_found_dump(void) {
    for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:docs() error:nil])
        if (import_is_game_file(f.fileSystemRepresentation)) return [NSURL fileURLWithPath:[docs() stringByAppendingPathComponent:f]];
    return nil;
}

// The build this app was made for: "# BUILD_ID <32 hex>" in the bundled rewriter table of main (patch_nso.py), the first 16 bytes of the NSO's build ID
static BOOL want_build(char out[33]) {
    NSString *t = [NSString stringWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"dm/main.fixups.tsv"] encoding:NSUTF8StringEncoding error:nil];
    for (NSString *ln in [t componentsSeparatedByString:@"\n"]) {
        if (![ln hasPrefix:@"# BUILD_ID\t"]) continue;
        NSString *v = [[ln substringFromIndex:11] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        if (v.length < 32) return NO;
        snprintf(out, 33, "%s", [v substringToIndex:32].UTF8String); return YES;
    }
    return NO;
}
static bool check_exefs(const char *dir, char *why, size_t n) {
    char want[33]; if (!want_build(want)) return true;   // a bundle without the table: nothing to compare (the host checks the modules it loads)
    char p[1100]; snprintf(p, sizeof p, "%s/main", dir);
    FILE *f = fopen(p, "rb"); uint8_t h[0x60] = {0};
    if (!f || fread(h, 1, sizeof h, f) != sizeof h || memcmp(h, "NSO0", 4)) { if (f) fclose(f); snprintf(why, n, "The game's code in that dump didn't read."); return false; }
    fclose(f);
    char got[33]; for (int i = 0; i < 16; i++) snprintf(got + 2 * i, 3, "%02x", h[0x40 + i]);
    if (!strcmp(got, want)) return true;
    snprintf(why, n, "That dump is another version or region of the game (its code is build %.16s…; this app was made for build %.16s…, the version it was tested with). Pick that dump, or ask for a build of this app for your version.", got, want);
    return false;
}

static BOOL copy_pick(NSURL *u, NSString *dst, NSString **error) {   // a picked keys file into the private folder (the picker's access ends with the pick)
    BOOL scoped = [u startAccessingSecurityScopedResource];
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (scoped) [u stopAccessingSecurityScopedResource];
    if (!d.length) { if (error) *error = [NSString stringWithFormat:@"Couldn't read %@. If it's in iCloud, download it first.", u.lastPathComponent]; return NO; }
    return [d writeToFile:dst atomically:YES];
}

BOOL dm_import_start(NSURL *game, NSURL *keys, NSURL *titleKeys, NSString **error) {
    if (!dm_import_available()) { if (error) *error = @"This app keeps its game files inside it."; return NO; }
    int idle = 0; if (!atomic_compare_exchange_strong(&g_state, &idle, 1)) {
        int s = atomic_load(&g_state);
        if (s == 1) { if (error) *error = @"An import is already running."; return NO; }
        atomic_store(&g_state, 1);
    }
    if (keys && !copy_pick(keys, [keys_dir() stringByAppendingPathComponent:@"prod.keys"], error)) { atomic_store(&g_state, 0); return NO; }
    if (titleKeys) copy_pick(titleKeys, [keys_dir() stringByAppendingPathComponent:@"title.keys"], nil);
    NSString *kp = find_keys();
    if (!kp) { atomic_store(&g_state, 0); if (error) *error = @"prod.keys is needed too: pick it together with the game (Select both files), or put it in this app's folder in Files."; return NO; }
    if (titleKeys == nil && [kp hasPrefix:docs()]) {   // title.keys beside prod.keys in Documents: importer.c looks next to the keys file
        NSString *tk = [docs() stringByAppendingPathComponent:@"title.keys"];
        if ([NSFileManager.defaultManager fileExistsAtPath:tk]) [NSFileManager.defaultManager copyItemAtPath:tk toPath:[keys_dir() stringByAppendingPathComponent:@"title.keys"] error:nil];
    }
    memset(&g_job, 0, sizeof g_job);
#if defined(DM_GAME_PROGRAM_ID)
    g_job.title_id = DM_GAME_PROGRAM_ID;
#endif
#if defined(DM_GAME_NAME)
    g_job.game_name = DM_GAME_NAME;
#endif
    g_job.check_exefs = check_exefs;
    g_error = nil;
    NSString *keyPath = kp;
    fprintf(stderr, "[import] start: %s, keys %s\n", game.lastPathComponent.UTF8String, [kp hasPrefix:docs()] ? "from Documents" : "kept from an earlier pick");
    UIApplication.sharedApplication.idleTimerDisabled = YES;   // the screen stays on: iOS suspends an app in the background, which would stop the import
    __block UIBackgroundTaskIdentifier bg = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"Import game files" expirationHandler:^{
        [UIApplication.sharedApplication endBackgroundTask:bg]; bg = UIBackgroundTaskInvalid;
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager new];
        NSString *out = [docs() stringByAppendingPathComponent:@".import"], *romfs = [docs() stringByAppendingPathComponent:@"romfs"];
        [fm removeItemAtPath:out error:nil];
        BOOL scoped = [game startAccessingSecurityScopedResource];
        bool ok = import_game(game.fileSystemRepresentation, keyPath.fileSystemRepresentation, out.fileSystemRepresentation, &g_job);
        if (scoped) [game stopAccessingSecurityScopedResource];
        __block NSString *err = ok ? nil : @(g_job.error[0] ? g_job.error : "The import failed.");
        if (ok) {   // the new files replace the old ones: those are moved aside at once and deleted after (many files)
            g_job.phase = "Putting the game files in place";
            NSString *old = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"romfs-old-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            if ([fm fileExistsAtPath:romfs] && ![fm moveItemAtPath:romfs toPath:old error:nil]) err = @"The old game files couldn't be moved aside.";
            NSError *e = nil;
            if (!err && ![fm moveItemAtPath:[out stringByAppendingPathComponent:@"romfs"] toPath:romfs error:&e]) err = [NSString stringWithFormat:@"The game files couldn't be put in place (%@).", e.localizedDescription];
            NSURL *u = [NSURL fileURLWithPath:romfs]; [u setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];   // many GB: not in device backups (as main.m does)
            [fm removeItemAtPath:old error:nil];
        }
        [fm removeItemAtPath:out error:nil];   // the ExeFS (only checked) and anything a failed import left
        fprintf(stderr, "[import] %s\n", err ? err.UTF8String : "done: game files in Documents/romfs");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err && !front_ios_boot_retry()) err = @"The game files were imported, but the game doesn't find them. Close the app and open it again.";
            g_error = err;
            atomic_store(&g_state, err ? 3 : 2);
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            if (bg != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:bg]; bg = UIBackgroundTaskInvalid; }
        });
    });
    return YES;
}

int dm_import_state(double *fraction, NSString **phase, NSString **error) {
    int s = atomic_load(&g_state);
    int64_t done = g_job.done, total = g_job.total;
    if (fraction) *fraction = total > 0 ? MIN(1.0, MAX(0.0, (double)done / (double)total)) : 0;
    if (phase) { const char *p = (const char *)g_job.phase; *phase = p ? @(p) : nil; }
    if (error) *error = g_error;
    return s;
}
void dm_import_cancel(void) { if (atomic_load(&g_state) == 1) g_job.cancel = true; }

