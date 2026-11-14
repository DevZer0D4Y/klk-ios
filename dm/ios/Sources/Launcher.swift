// Launcher: the settings screen shown before the game starts (front_ios.m dm_show_launcher). Its settings come from the app's dm/launcher.json (an app of several programs: dm/p<N>/launcher.json), which build_ipa.sh writes for this game
// from dm/games/settings.tsv (dm/games/settings.py): each sets an environment variable the host reads when the game starts. A variable an env file set (Documents/env.txt, the bundle's
// dm/env.txt; main.m lists them in DM_ENV_FILE_KEYS) is shown but kept. All settings share one screen, grouped by section (rows: LauncherRow.swift). Choices that differ from the game's default are kept
// in UserDefaults; Reset to tested defaults shows the defaults, and Play then forgets them. DM_LAUNCHER=0 in Documents/env.txt starts the game at once with the saved choices; DM_SAVED_CHOICES=0 ignores them (and keeps them)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }


/// Cloud saves: an iCloud Drive folder shared with the Mac app (chosen in its settings window's
/// Cloud saves too). The host brings the save in from there when the game starts and
/// sends it there after each save (dm/host/save_sync.h); the folder is a bookmark (CloudSaves.m).
private struct CloudSavesSection: View {
    @State private var folder: String = ""
    @State private var note: String = ""
    @State private var picking = false

    var body: some View {
        Section {
            HStack {
                Text("Cloud saves")
                Spacer()
                Text(folder.isEmpty ? "Off" : (folder as NSString).lastPathComponent)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Button(folder.isEmpty ? "Choose a folder in iCloud Drive…" : "Choose a different folder…") { picking = true }
                // The sheet sits on the button, not on the Section: SwiftUI hands a Section's modifiers to every row, so one tap presented a picker per row and they invalidated each other (LNPANDY/NX2Apple#315).
                .sheet(isPresented: $picking) {
                    DocumentPicker(types: [.folder]) { url in
                        picking = false
                        if dm_store_cloud_saves(url) {
                            note = "Saved. The game uses this folder when you press Play."
                            refresh()
                        } else {
                            note = "That folder could not be remembered — try a different one."
                        }
                    } onCancel: { picking = false }
                }
            if !folder.isEmpty {
                Button("Turn off cloud saves", role: .destructive) {
                    dm_clear_cloud_saves(); refresh(); note = ""
                }
            }
        } footer: {
            Text(note.isEmpty
                 ? "Choose a folder in iCloud Drive, and the same one in the Mac app's Cloud saves. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups."
                 : note)
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        var stale: ObjCBool = false
        folder = dm_cloud_saves_path(&stale) ?? ""
        if stale.boolValue && folder.isEmpty {
            note = "The folder you chose before is no longer readable (the app was signed differently). Please choose it again."
        }
    }
}

/// The game files: imported on the device from the player's own dump (GameImport.m, importer.c). The launcher shows even when they are missing, with Play off until they are in place.
final class GameFilesModel: ObservableObject {
    @Published var ready = dm_game_files_ready()
    @Published var running = false
    @Published var fraction = 0.0
    @Published var phase = ""
    @Published var message = ""
    @Published var failed = false
    private var timer: Timer?

    /// What the player picked: the dump (.nsp .nsz .xci .xcz), prod.keys (any *.keys but title.keys, or keys.txt), title.keys
    func handle(_ urls: [URL]) {
        var game: URL?, keys: URL?, titleKeys: URL?
        for u in urls {
            let n = u.lastPathComponent.lowercased(), ext = u.pathExtension.lowercased()
            if n == "title.keys" { titleKeys = u }
            else if ext == "keys" || n == "keys.txt" { keys = u }
            else if ["nsp", "nsz", "xci", "xcz"].contains(ext) { game = u }
        }
        guard let g = game else {
            fail(keys != nil ? "Saved your keys. Now pick the game dump (.nsp, .nsz, .xci or .xcz)." : "Pick your game dump (.nsp, .nsz, .xci or .xcz) and prod.keys.")
            if let k = keys { keepKeysOnly(k) }
            return
        }
        start(game: g, keys: keys, titleKeys: titleKeys)
    }

    private func keepKeysOnly(_ k: URL) {   // keys picked alone: kept for the next pick (dm_import_start copies them; without a dump it is not started)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("keys")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scoped = k.startAccessingSecurityScopedResource()
        defer { if scoped { k.stopAccessingSecurityScopedResource() } }
        if let d = try? Data(contentsOf: k), !d.isEmpty { try? d.write(to: dir.appendingPathComponent("prod.keys")) }
    }

    func start(game: URL, keys: URL?, titleKeys: URL?) {
        var err: NSString?
        guard dm_import_start(game, keys, titleKeys, &err) else { fail((err as String?) ?? "The import couldn't start."); return }
        running = true; failed = false; message = ""; fraction = 0; phase = "Opening the game file"
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in self?.tick(t) }
    }

    private func tick(_ t: Timer) {
        var f = 0.0; var ph: NSString?; var er: NSString?
        let s = dm_import_state(&f, &ph, &er)
        fraction = f; phase = (ph as String?) ?? phase
        guard s != 1 else { return }
        t.invalidate(); timer = nil; running = false
        if s == 2 { ready = dm_game_files_ready(); failed = false; message = "Game files imported. You can delete the dump from Files to free its space." }
        else { fail((er as String?) ?? "The import failed.") }
    }

    private func fail(_ m: String) { failed = true; message = m }
}

private struct GameFilesSection: View {
    @ObservedObject var g: GameFilesModel
    let accent: Color
    @State private var picking = false

    var body: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Label(g.ready ? "Ready" : g.running ? "Importing…" : "Not imported", systemImage: g.ready ? "checkmark.circle.fill" : g.running ? "arrow.down.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(g.ready ? Color.green : g.running ? Color.secondary : accent)
            }
            if g.running {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: g.fraction).tint(accent)
                    Text("\(g.phase) · \(Int((g.fraction * 100).rounded())) %").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
                Button("Cancel import", role: .destructive) { dm_import_cancel() }
            } else if dm_import_available() {
                Button(g.ready ? "Import again from a game dump…" : "Choose your game dump and prod.keys…") { picking = true }
                    .fontWeight(.semibold)
                    // On the button, not the Section: a Section hands its modifiers to every row (see CloudSavesSection)
                    .sheet(isPresented: $picking) {
                        GamePicker { urls in picking = false; g.handle(urls) } onCancel: { picking = false }
                    }
                if !g.ready, let found = dm_import_found_dump() {
                    Button("Import \(found.lastPathComponent) from this app's folder") { g.start(game: found, keys: nil, titleKeys: nil) }
                }
            }
        } header: {
            Text("Game files")   // not "Game": the settings' first section is called that
        } footer: {
            Text(g.message.isEmpty
                 ? (g.ready ? "The game's files are in this app."
                    : "Pick your own dump of the game (.nsp, .nsz, .xci or .xcz) and your console's prod.keys: tap one, then Select to choose both. They are read where they are; the game data is unpacked into this app, so it needs about as much free space as the game. Keep the app open until it finishes.")
                 : g.message)
                .foregroundStyle(g.failed ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
        }
    }
}

/// The Files picker for the game dump and its keys: several files at once, opened where they are (a dump of many GB is not copied first)
private struct GamePicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)   // .item: a dump or keys file has no system type
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { urls.isEmpty ? onCancel() : onPick(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

/// A game's own look for the launcher: dm/theme.json in the app (build_ipa.sh copies the profile's launcher_theme.json), all optional:
/// {"accent": "#RRGGBB", "background": ["#RRGGBB", "#RRGGBB"], "title": "...", "subtitle": "...", "labels": {"DM_RENDER_SCALE": "Resolution"}, "defaults": {"DM_RENDER_SCALE": "0.85"}}
/// defaults: the game's own defaults on iOS for some rows (Reset to tested defaults returns to them; a saved choice still wins)
struct LauncherTheme: Decodable {
    var accent: String?
    var background: [String]?
    var title: String?
    var subtitle: String?
    var labels: [String: String]?
    var defaults: [String: String]?

    static func load(_ dir: URL?) -> LauncherTheme {
        guard let u = dir?.appendingPathComponent("theme.json"), let d = try? Data(contentsOf: u), let t = try? JSONDecoder().decode(LauncherTheme.self, from: d) else { return LauncherTheme() }
        return t
    }
    static func color(_ hex: String?) -> Color? {
        guard var h = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return Color(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    var accentColor: Color? { LauncherTheme.color(accent) }
    var backgroundColors: [Color] { (background ?? []).compactMap { LauncherTheme.color($0) } }
}

/// UIDocumentPickerViewController for a folder, in the two callbacks a SwiftUI sheet wants.
private struct DocumentPicker: UIViewControllerRepresentable {
    var types: [UTType] = [.folder]
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // .open (not .import): the folder stays where it is and the bookmark keeps pointing at it.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

private struct LauncherView: View {
    @ObservedObject var m: LauncherModel
    @ObservedObject var files: GameFilesModel
    let theme: LauncherTheme
    let play: () -> Void
    private var accent: Color { theme.accentColor ?? .accentColor }
    @State private var memory = os_proc_available_memory()
    @State private var checking = false
    @State private var check = 0   // which Play the running check is for: one the player went on from without it is dropped
    @State private var report: SaveSyncReport?
    @State private var asking: SaveSyncReport.Step?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 16) {
                    if let icon = appIcon() {
                        Image(uiImage: icon).resizable().frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .accessibilityHidden(true)
                    }
                    if let title = theme.title {   // the game's own title lettering (theme.json)
                        VStack(spacing: 2) {
                            Text(title).font(.system(size: 34, weight: .black)).italic().foregroundStyle(.white)
                                .minimumScaleFactor(0.5).lineLimit(1)
                            if let sub = theme.subtitle {
                                Text(sub).font(.system(size: 20, weight: .heavy)).italic().foregroundStyle(accent)
                                    .padding(.horizontal, 10).padding(.vertical, 2).background(Color.black.opacity(0.85))
                            }
                        }.multilineTextAlignment(.center)
                    } else {
                        Text((info("CFBundleDisplayName") as? String) ?? "Game")
                            .font(.title.weight(.bold)).multilineTextAlignment(.center)
                    }
                    Text("Version \((info("CFBundleShortVersionString") as? String) ?? "")")
                        .font(.callout).foregroundStyle(.secondary)
                    playButton
                }
                .padding(16)
                .frame(width: geometry.size.width / 3, height: geometry.size.height)
                List {
                    GameFilesSection(g: files, accent: accent)
                    ForEach(m.sections, id: \.self) { section in
                        let rows = m.rows(in: section)
                        if !rows.isEmpty {
                            Section(section) {
                                ForEach(rows) { SettingRow(s: $0, m: m) }
                            }
                        }
                    }
                    Section {
                        Button("Reset to tested defaults") { m.reset() }
                            .disabled(!m.changed)
                    } footer: {
                        Text("Brings back all settings this game was tested with.")
                    }
                    CloudSavesSection()
                    Section {
                        HStack {
                            Text("Memory available")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .scrollContentBackground(theme.backgroundColors.isEmpty ? .automatic : .hidden)
                .frame(width: geometry.size.width * 2 / 3)
            }
        }
        .background {
            let bg = theme.backgroundColors
            if !bg.isEmpty { LinearGradient(colors: bg, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
        .confirmationDialog(SaveSyncReport.chooseTitle, isPresented: isAsking(.choose), titleVisibility: .visible, presenting: report) { r in
            Button(r.localLabel(here: "iPhone")) { go(r.localChoice) }
            Button(r.cloudLabel) { go(r.cloudChoice) }
            Button("Cancel", role: .cancel) {}
        } message: { r in Text(r.chooseMessage(here: "iPhone")) }
        .confirmationDialog(SaveSyncReport.unreadableTitle, isPresented: isAsking(.unreadable), titleVisibility: .visible, presenting: report) { r in
            Button("Play This iPhone's Save") { go("offline") }   // the mount does not wait for the cloud again
            Button("Try Again") { DispatchQueue.main.async { start() } }
            Button("Cancel", role: .cancel) {}
        } message: { r in Text(r.unreadableMessage(here: "iPhone")) }
        .task {
            while !Task.isCancelled {
                memory = os_proc_available_memory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder var playButton: some View {
        let button = Button(action: start) { Text(theme.title != nil ? "PLAY" : "Play").font(theme.title != nil ? .title2.weight(.black).italic() : .title3.weight(.semibold)).frame(maxWidth: 220) }
            .controlSize(.large).disabled(checking || !files.ready || files.running)   // no game files yet: the Game files section imports them
        if #available(iOS 26.0, *) { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.borderedProminent) }
        if checking {
            VStack(spacing: 6) {
                HStack(spacing: 6) { ProgressView(); Text("Checking the cloud save…").font(.callout).foregroundStyle(.secondary) }
                Button("Play Without It") { checking = false; go("offline") }.font(.callout)
            }
        }
    }

    private func isAsking(_ step: SaveSyncReport.Step) -> Binding<Bool> {
        Binding(get: { asking == step }, set: { if !$0 && asking == step { asking = nil } })
    }

    /// Play, once the cloud's save is compared with this iPhone's (save_sync_report, SaveSyncReport): a save that changed on both sides is the player's pick, not the
    /// newer file's, and a cloud save that did not come is said so before the game starts without it.
    private func start() {
        check += 1; checking = true; asking = nil
        let mine = check
        dm_cloud_saves_env()   // DM_SAVE_SYNC from the picked folder, as the game's mount will read it (front_ios.m calls it again at the start)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.compare()
            DispatchQueue.main.async {
                guard checking, check == mine else { return }   // the player played without it
                checking = false
                switch SaveSyncReport.step(r) {
                case .play(let choice): go(choice)
                case let step: report = r; asking = step
                }
            }
        }
    }

    /// Blocks while the cloud's file downloads (SaveSyncReport.waitMs at most). nil: no report (the host then decides as it always did)
    private static func compare() -> SaveSyncReport? {
        // getenv, not ProcessInfo.environment: main.m sets DM_SAVE and applies env.txt after that snapshot
        guard let save = getenv("DM_SAVE") else { fputs("launcher: save sync: no DM_SAVE\n", stderr); return nil }
        var buf = [CChar](repeating: 0, count: 1024)
        guard save_sync_report(save, dm_save_title(), nil, SaveSyncReport.waitMs, &buf, buf.count) == 0 else {
            fputs("launcher: save sync: no report on \(String(cString: save))\n", stderr)
            return nil
        }
        let line = String(cString: buf)
        fputs("launcher: save sync: \(line)\n", stderr)
        return SaveSyncReport(line: line)
    }

    private func go(_ choice: String?) {
        asking = nil
        if let choice { setenv("DM_SAVE_SYNC_CHOICE", choice, 1); fputs("launcher: DM_SAVE_SYNC_CHOICE=\(choice)\n", stderr) }
        play()
    }

    private func appIcon() -> UIImage? {
        if let i = UIImage(named: "AppIcon") { return i }
        guard let icons = info("CFBundleIcons") as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String], let last = files.last else { return nil }
        return UIImage(named: last)
    }
}

/// launcher.json with a game's own names and defaults for some rows (theme.json labels: {env: label}, defaults: {env: value})
private func relabeled(_ data: Data, _ labels: [String: String]?, _ defaults: [String: String]? = nil) -> Data {
    let labels = labels ?? [:], defaults = defaults ?? [:]
    guard !labels.isEmpty || !defaults.isEmpty, var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let rows = root["settings"] as? [[String: Any]] else { return data }
    root["settings"] = rows.map { r -> [String: Any] in
        var r = r
        if let env = r["env"] as? String, let l = labels[env] { r["label"] = l }
        if let env = r["env"] as? String, let d = defaults[env] { r["default"] = d }
        return r
    }
    return (try? JSONSerialization.data(withJSONObject: root)) ?? data
}

// Whether this app has a launcher (front_ios.m shows it even without the game files, so they can be imported there)
@_cdecl("dm_launcher_present")
public func dmLauncherPresent() -> Bool {
    let dir = getenv("DM_APP_DM").map { URL(fileURLWithPath: String(cString: $0)) } ?? Bundle.main.resourceURL?.appendingPathComponent("dm")
    guard let url = dir?.appendingPathComponent("launcher.json") else { return false }
    return FileManager.default.fileExists(atPath: url.path)
}

// Shows the launcher over the root view controller and calls done once the settings are in the environment; false (done is not called) when there is no launcher
@_cdecl("dm_show_launcher")
public func dmShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) -> Bool {
    // a game of several programs (main.m): the running program's settings, in its dm/p<N>
    let dir = getenv("DM_APP_DM").map { URL(fileURLWithPath: String(cString: $0)) } ?? Bundle.main.resourceURL?.appendingPathComponent("dm")
    guard let url = dir?.appendingPathComponent("launcher.json"), let data = try? Data(contentsOf: url) else { return false }
    let theme = LauncherTheme.load(dir)
    guard let file = try? JSONDecoder().decode(SettingsFile.self, from: relabeled(data, theme.labels, theme.defaults)), !file.settings.isEmpty else { fputs("[RED] launcher: dm/launcher.json cannot be read; starting the game\n", stderr); return false }
    let model = LauncherModel(file.settings)
    gameMenuModel = model   // the in-game menu shows and saves the same choices (GameMenu.swift)
    if ProcessInfo.processInfo.environment["DM_LAUNCHER"] == "0" && dm_game_files_ready() {   // (without the game files the launcher shows anyway: it imports them)
        fputs("launcher: off (DM_LAUNCHER=0)\n", stderr); model.applySaved(); return false }
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    var host: UIViewController?
    let files = GameFilesModel()
    if !files.ready { fputs("launcher: no game files yet; the Game section imports them\n", stderr) }
    let view = LauncherView(m: model, files: files, theme: theme) {
        guard let h = host else { return }
        host = nil
        model.apply()
        h.dismiss(animated: false) { done() }
    }
    let h = DmHostingController(rootView: view)
    h.modalPresentationStyle = .fullScreen
    host = h
    parent.present(h, animated: false)
    fputs("launcher: \(file.settings.count) settings shown\n", stderr)
    return true
}
