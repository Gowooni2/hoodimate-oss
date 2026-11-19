import AppIntents
import FlutterMacOS
import Foundation

/// Siri / Shortcuts entry points (owner, 2026-10-28): "Ask Hoodimate",
/// "Hoodimate reminder", "Feed Hoodimate", "How is Hoodimate feeling" (1.2.0).
/// Siri runs them in the app; the
/// Dart side (PetBrain) answers through the same chat path as typing, so
/// consent, the chosen AI and offline reminder commands behave the same.
///   channel hoodimong/siri
///     Dart -> Swift  ready                  (handler installed)
///     Swift -> Dart  ask {text}    -> String (the pet's reply)
///                    remind {minutes, text} -> String
///                    feed                   -> String
///                    feeling                -> String (from the pet's own stats, no AI)
enum SiriBridge {
  static var channel: FlutterMethodChannel?
  static var ready = false

  static func register(with controller: FlutterViewController) {
    let ch = FlutterMethodChannel(name: "hoodimong/siri", binaryMessenger: controller.engine.binaryMessenger)
    ch.setMethodCallHandler { call, result in
      if call.method == "ready" {
        ready = true
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  /// Waits up to 10 s for the pet to start (Siri may launch the app), then
  /// asks the Dart side. Empty string when the pet isn't there.
  @MainActor
  static func call(_ method: String, _ args: [String: Any] = [:]) async -> String {
    var tries = 0
    while !ready && tries < 40 {
      try? await Task.sleep(nanoseconds: 250_000_000)
      tries += 1
    }
    guard ready, let ch = channel else { return "" }
    return await withCheckedContinuation { cont in
      ch.invokeMethod(method, arguments: args) { r in
        cont.resume(returning: (r as? String) ?? "")
      }
    }
  }

  static func spoken(_ text: String) -> String {
    text.isEmpty ? String(localized: "Hoodimate isn't ready yet. Try again in a moment.") : text
  }
}

@available(macOS 13.0, *)
struct AskHoodimateIntent: AppIntent {
  static var title: LocalizedStringResource = "Ask Hoodimate"
  static var description = IntentDescription("Ask your desktop pet anything, or tell it what to remember.")
  static var openAppWhenRun = false

  @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
  var question: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
    let text = SiriBridge.spoken(await SiriBridge.call("ask", ["text": question]))
    return .result(value: text, dialog: IntentDialog(stringLiteral: text))
  }
}

@available(macOS 13.0, *)
struct HoodimateReminderIntent: AppIntent {
  static var title: LocalizedStringResource = "Set a Hoodimate Alarm"
  static var description = IntentDescription("Your pet rings an alarm after some minutes and runs around with a clock.")
  static var openAppWhenRun = false

  @Parameter(title: "Minutes", inclusiveRange: (1, 1440), requestValueDialog: "In how many minutes?")
  var minutes: Int

  @Parameter(title: "About", requestValueDialog: "What should I remind you about?")
  var about: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let text = SiriBridge.spoken(await SiriBridge.call("remind", ["minutes": minutes, "text": about]))
    return .result(dialog: IntentDialog(stringLiteral: text))
  }
}

@available(macOS 13.0, *)
struct FeedHoodimateIntent: AppIntent {
  static var title: LocalizedStringResource = "Feed Hoodimate"
  static var description = IntentDescription("Give your pet a snack.")
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let text = SiriBridge.spoken(await SiriBridge.call("feed"))
    return .result(dialog: IntentDialog(stringLiteral: text))
  }
}

/// Answered from the pet's own numbers on this Mac: nothing is sent to any AI,
/// so no consent is involved.
@available(macOS 13.0, *)
struct HowIsHoodimateIntent: AppIntent {
  static var title: LocalizedStringResource = "Ask How Hoodimate Feels"
  static var description = IntentDescription("Hear how your pet is doing: mood, fullness and energy.")
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
    let text = SiriBridge.spoken(await SiriBridge.call("feeling"))
    return .result(value: text, dialog: IntentDialog(stringLiteral: text))
  }
}

@available(macOS 13.0, *)
struct HoodimateShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AskHoodimateIntent(),
      phrases: ["Ask \(.applicationName)", "Talk to \(.applicationName)", "\(.applicationName)에게 물어봐"],
      shortTitle: "Ask", systemImageName: "bubble.left.and.bubble.right")
    AppShortcut(
      intent: HoodimateReminderIntent(),
      phrases: ["Set an alarm with \(.applicationName)", "Set a reminder with \(.applicationName)", "\(.applicationName) reminder", "\(.applicationName) 알람 맞춰"],
      shortTitle: "Alarm", systemImageName: "alarm")
    AppShortcut(
      intent: FeedHoodimateIntent(),
      phrases: ["Feed \(.applicationName)", "\(.applicationName) 밥 줘"],
      shortTitle: "Feed", systemImageName: "fork.knife")
    AppShortcut(
      intent: HowIsHoodimateIntent(),
      phrases: ["How is \(.applicationName) feeling", "How is \(.applicationName) doing", "\(.applicationName) 기분 어때"],
      shortTitle: "How is it?", systemImageName: "face.smiling")
  }
}
