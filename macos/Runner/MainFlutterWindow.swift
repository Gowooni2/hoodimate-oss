import Cocoa
import EventKit
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Desktop pet: fully transparent window, only the character is visible.
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    NotesFolderChannel.register(with: flutterViewController)
    HapticChannel.register(with: flutterViewController)
    LinkChannel.register(with: flutterViewController)
    SyncFolderChannel.register(with: flutterViewController)
    CalendarChannel.register(with: flutterViewController)
    GroupChannel.register(with: flutterViewController)
    OnDeviceAIChannel.register(with: flutterViewController)
    SiriBridge.register(with: flutterViewController)
    MenuChannel.register(with: flutterViewController)
    StatusBarChannel.register(with: flutterViewController)
    NotifyChannel.register(with: flutterViewController)
    FirstClick.enable()

    super.awakeFromNib()
  }
}

/// Lets the sandboxed app write notes into a folder the user picks once
/// (e.g. an Obsidian vault on the NAS). The pick is kept as a
/// security-scoped bookmark so access survives restarts.
///   pick    -> path or nil      (shows the folder picker)
///   restore -> path or nil      (re-opens the saved folder)
///   write {name, text, append} -> true/false
/// The App Group folder shared with Hoodibot (see the pets' interaction
/// protocol). `dir` -> path or nil when the group isn't available.
enum GroupChannel {
  static let id = "YOURTEAMID.app.hoodimong.shared"

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "hoodimong/group", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "dir" else { return result(FlutterMethodNotImplemented) }
      result(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?.path)
    }
  }
}

/// Menu bar commands handled in Dart: `settings`, `help` (native -> Dart).
enum MenuChannel {
  static var channel: FlutterMethodChannel?

  static func register(with controller: FlutterViewController) {
    channel = FlutterMethodChannel(
      name: "hoodimong/menu", binaryMessenger: controller.engine.binaryMessenger)
  }
}

/// Opens a web page (privacy policy, support) in the default browser.
/// `open {url}` -> true/false. Only https links are opened.
enum LinkChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "hoodimong/link", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "open", let s = call.arguments as? String,
            let url = URL(string: s), url.scheme == "https" else {
        result(false)
        return
      }
      result(NSWorkspace.shared.open(url))
    }
  }
}

/// Trackpad haptics (Force Touch trackpads). `play` takes a list of
/// [pattern, delayMs] steps: 0 generic, 1 alignment, 2 level change.
/// Silently does nothing on Macs without a haptic trackpad.
enum HapticChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "hoodimong/haptic", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "play", let steps = call.arguments as? [[Int]] else {
        result(FlutterMethodNotImplemented)
        return
      }
      let performer = NSHapticFeedbackManager.defaultPerformer
      var at = 0
      for step in steps where step.count == 2 {
        at += step[1]
        let pattern: NSHapticFeedbackManager.FeedbackPattern =
          step[0] == 1 ? .alignment : (step[0] == 2 ? .levelChange : .generic)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(at)) {
          performer.perform(pattern, performanceTime: .now)
        }
      }
      result(nil)
    }
  }
}

/// A folder the owner picks once, kept across launches with a
/// security-scoped bookmark (the app is sandboxed). Used for Obsidian notes
/// (hoodimong/notes) and for syncing between Macs (hoodimong/sync).
/// Methods: pick, restore, write {name, text, append}, read {name}.
final class FolderChannel {
  let key: String
  let message: String
  var url: URL?

  init(key: String, message: String) {
    self.key = key
    self.message = message
  }

  func register(name: String, with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: name, binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [self] call, result in
      let a = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "pick": pick(result)
      case "restore": result(restore()?.path)
      case "write":
        result(write(name: a["name"] as? String ?? "", text: a["text"] as? String ?? "",
                     append: a["append"] as? Bool ?? true))
      case "read": result(read(name: a["name"] as? String ?? ""))
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  func pick(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "OK"
    panel.message = message
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [self] resp in
      guard resp == .OK, let u = panel.url else { return result(nil) }
      if let data = try? u.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil) {
        UserDefaults.standard.set(data, forKey: key)
      }
      url?.stopAccessingSecurityScopedResource()
      url = u
      _ = u.startAccessingSecurityScopedResource()
      result(u.path)
    }
  }

  func restore() -> URL? {
    if let u = url { return u }
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    var stale = false
    guard let u = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                           relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
    guard u.startAccessingSecurityScopedResource() else { return nil }
    if stale, let fresh = try? u.bookmarkData(options: .withSecurityScope,
                                              includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(fresh, forKey: key)
    }
    url = u
    return u
  }

  /// `name` may contain one subfolder ("후디몽/일상.md").
  func write(name: String, text: String, append: Bool) -> Bool {
    guard let base = restore(), !name.isEmpty, !name.contains("..") else { return false }
    let file = base.appendingPathComponent(name)
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      if append, FileManager.default.fileExists(atPath: file.path) {
        let h = try FileHandle(forWritingTo: file)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
      } else {
        try Data(text.utf8).write(to: file, options: .atomic)
      }
      return true
    } catch {
      return false
    }
  }

  /// File text, or nil when missing (or still downloading from the cloud).
  func read(name: String) -> String? {
    guard let base = restore(), !name.isEmpty, !name.contains("..") else { return nil }
    let file = base.appendingPathComponent(name)
    try? FileManager.default.startDownloadingUbiquitousItem(at: file)  // iCloud: fetch if evicted
    return try? String(contentsOf: file, encoding: .utf8)
  }
}

/// The owner's Mac calendars for the AI's calendar tools (EventKit).
/// events {days} -> [{title, start, end, allDay, location, calendar}] or an
/// error string; add {title, start, end?, location?} -> result string.
enum CalendarChannel {
  static let store = EKEventStore()

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "hoodimong/calendar", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      let a = call.arguments as? [String: Any] ?? [:]
      access { ok in
        guard ok else {
          return result("no calendar access: allow Hoodimate in System Settings > Privacy & Security > Calendars")
        }
        switch call.method {
        case "events": result(events(days: a["days"] as? Int ?? 7))
        case "add": result(add(a))
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  static func access(_ done: @escaping (Bool) -> Void) {
    let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
    if #available(macOS 14.0, *) {
      store.requestFullAccessToEvents(completion: finish)
    } else {
      store.requestAccess(to: .event, completion: finish)
    }
  }

  static let iso: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return f
  }()

  static func events(days: Int) -> [[String: Any]] {
    let start = Date()
    let end = Calendar.current.date(byAdding: .day, value: max(1, min(days, 31)), to: start)!
    let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: pred).prefix(60).map { e in
      ["title": e.title ?? "", "start": iso.string(from: e.startDate), "end": iso.string(from: e.endDate),
       "allDay": e.isAllDay, "location": e.location ?? "", "calendar": e.calendar.title]
    }
  }

  static func parse(_ s: String) -> Date? {
    for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
      iso.dateFormat = fmt
      if let d = iso.date(from: s) { iso.dateFormat = "yyyy-MM-dd'T'HH:mm"; return d }
    }
    iso.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return nil
  }

  static func add(_ a: [String: Any]) -> String {
    guard let title = a["title"] as? String, !title.isEmpty,
          let start = parse(a["start"] as? String ?? "") else { return "error: need title and start time" }
    let e = EKEvent(eventStore: store)
    e.title = title
    e.startDate = start
    e.endDate = parse(a["end"] as? String ?? "") ?? start.addingTimeInterval(3600)
    if let loc = a["location"] as? String, !loc.isEmpty { e.location = loc }
    guard let cal = store.defaultCalendarForNewEvents else { return "error: no default calendar" }
    e.calendar = cal
    do {
      try store.save(e, span: .thisEvent)
      return "added \(title) on \(iso.string(from: start)) to \(cal.title)"
    } catch {
      return "error: \(error.localizedDescription)"
    }
  }
}

enum NotesFolderChannel {
  static let shared = FolderChannel(
    key: "notesFolderBookmark",
    message: "후디메이트가 노트를 저장할 폴더(옵시디언 볼트 등)를 골라 주세요 · Pick the folder for Hoodimate's notes (e.g. inside your Obsidian vault)")
  static func register(with controller: FlutterViewController) {
    shared.register(name: "hoodimong/notes", with: controller)
  }
}

enum SyncFolderChannel {
  static let shared = FolderChannel(
    key: "syncFolderBookmark",
    message: "두 맥에서 함께 보이는 폴더(iCloud Drive, Dropbox 등)를 골라 주세요 · Pick a folder both Macs can see (iCloud Drive, Dropbox, ...)")
  static func register(with controller: FlutterViewController) {
    shared.register(name: "hoodimong/sync", with: controller)
  }
}

/// A desktop pet is clicked while another app is in front. By default the
/// first click on an inactive window only activates it and never reaches
/// Flutter, so catching the running alarm pet took two clicks. Make
/// Flutter's view accept the first mouse-down.
enum FirstClick {
  static func enable() {
    guard let cls = NSClassFromString("FlutterView"),
          let m = class_getInstanceMethod(cls, #selector(NSView.acceptsFirstMouse(for:)))
    else { return }
    let yes: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
    method_setImplementation(m, imp_implementationWithBlock(yes))
  }
}


/// Menu bar status item (sold editions): the pet's mood as a face, fullness
/// and energy as text, and quick actions. Dart owns every string and state;
/// this side only draws it and reports the chosen action back.
///   Dart -> Swift  update {enabled, face, header, hunger, energy, feed, feedEnabled,
///                          sleep, alarm, show, quit}
///   Swift -> Dart  action 'feed' | 'sleep' | 'alarm' | 'show'
final class StatusBarChannel: NSObject {
  static let shared = StatusBarChannel()
  var channel: FlutterMethodChannel?
  var item: NSStatusItem?

  static func register(with controller: FlutterViewController) {
    let ch = FlutterMethodChannel(
      name: "hoodimong/statusbar", binaryMessenger: controller.engine.binaryMessenger)
    shared.channel = ch
    ch.setMethodCallHandler { call, result in
      guard call.method == "update", let a = call.arguments as? [String: Any] else {
        return result(FlutterMethodNotImplemented)
      }
      DispatchQueue.main.async { shared.apply(a) }
      result(nil)
    }
  }

  func apply(_ a: [String: Any]) {
    guard a["enabled"] as? Bool ?? false else {
      if let i = item { NSStatusBar.system.removeStatusItem(i) }
      item = nil
      return
    }
    if item == nil { item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
    item?.button?.title = a["face"] as? String ?? "🙂"
    let menu = NSMenu()
    menu.autoenablesItems = false // isEnabled below is the real state (Feed when full, Sleep while asleep)
    func info(_ key: String) {
      guard let t = a[key] as? String, !t.isEmpty else { return }
      let m = NSMenuItem(title: t, action: nil, keyEquivalent: "")
      m.isEnabled = false
      menu.addItem(m)
    }
    func action(_ key: String, _ id: String, enabled: Bool = true) {
      let m = NSMenuItem(title: a[key] as? String ?? id, action: #selector(pick(_:)), keyEquivalent: "")
      m.target = self
      m.representedObject = id
      m.isEnabled = enabled
      menu.addItem(m)
    }
    info("header")
    info("hunger")
    info("energy")
    menu.addItem(.separator())
    action("feed", "feed", enabled: a["feedEnabled"] as? Bool ?? true)
    action("sleep", "sleep", enabled: a["sleepEnabled"] as? Bool ?? true)
    action("alarm", "alarm")
    menu.addItem(.separator())
    action("show", "show")
    let quit = NSMenuItem(title: a["quit"] as? String ?? "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)
    item?.menu = menu
  }

  @objc func pick(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    if id == "show" || id == "alarm" { NSApp.activate(ignoringOtherApps: true) }
    channel?.invokeMethod("action", arguments: id)
  }
}


/// Notification Center notices (hungry, alarm, bedtime). The sandbox needs
/// no extra entitlement for local notifications. macOS is asked for
/// permission only when Dart calls `requestAuth` (the Settings switch).
///   requestAuth -> Bool
///   status      -> "authorized" | "denied" | "notDetermined"
///   post {id, title, body}
final class NotifyChannel: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotifyChannel()

  static func register(with controller: FlutterViewController) {
    let center = UNUserNotificationCenter.current()
    center.delegate = shared  // show banners even while the pet is the active app
    let ch = FlutterMethodChannel(
      name: "hoodimong/notify", binaryMessenger: controller.engine.binaryMessenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "requestAuth":
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
          DispatchQueue.main.async { result(ok) }
        }
      case "status":
        center.getNotificationSettings { s in
          let v: String
          switch s.authorizationStatus {
          case .authorized, .provisional: v = "authorized"
          case .denied: v = "denied"
          default: v = "notDetermined"
          }
          DispatchQueue.main.async { result(v) }
        }
      case "post":
        let a = call.arguments as? [String: Any] ?? [:]
        let c = UNMutableNotificationContent()
        c.title = a["title"] as? String ?? ""
        c.body = a["body"] as? String ?? ""
        let id = (a["id"] as? String ?? "notice") + "-\(Int(Date().timeIntervalSince1970))"
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil)) { _ in
          DispatchQueue.main.async { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
    done([.banner, .list])
  }
}
