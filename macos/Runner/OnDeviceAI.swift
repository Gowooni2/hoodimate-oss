import FlutterMacOS
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (Foundation Models) as a chat backend.
/// Runs entirely on this Mac: no Private Cloud Compute, no network.
///   availability -> {status: available|unavailable, reason}
///   respond {instructions, prompt, tools: bool}
///     -> {text, mood, remember, reminder?: {minutes, text}} or {error}
enum OnDeviceAIChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "hoodimong/ondevice_ai", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        switch call.method {
        case "availability": result(OnDeviceAI.availability())
        case "respond":
          let a = call.arguments as? [String: Any] ?? [:]
          Task {
            let r = await OnDeviceAI.respond(
              instructions: a["instructions"] as? String ?? "",
              prompt: a["prompt"] as? String ?? "",
              tools: a["tools"] as? Bool ?? false)
            DispatchQueue.main.async { result(r) }
          }
        default: result(FlutterMethodNotImplemented)
        }
        return
      }
      #endif
      result(call.method == "availability"
        ? ["status": "unavailable", "reason": "osTooOld"] : ["error": "unavailable"])
    }
  }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct PetReply {
  @Guide(description: "The pet's reply for a speech bubble, 1-3 short sentences")
  var text: String
  @Guide(.anyOf(["idle", "happy", "celebrating", "sad", "bored", "sleepy", "thinking", "eating", "hot"]))
  var mood: String
  @Guide(description: "A plan, to-do or important fact the owner told you, in one line; otherwise empty")
  var remember: String
}

/// The model asks for an alarm; the app sets it (Dart side).
@available(macOS 26.0, *)
final class ReminderBox: @unchecked Sendable {
  var minutes: Int?
  var text = ""
}

@available(macOS 26.0, *)
struct SetReminderTool: Tool {
  let box: ReminderBox
  let name = "set_reminder"
  let description = "Set an alarm that rings after some minutes with a short message."
  @Generable struct Arguments {
    @Guide(description: "Minutes from now") var minutes: Int
    @Guide(description: "What to remind about") var text: String
  }
  func call(arguments: Arguments) async throws -> String {
    box.minutes = max(1, arguments.minutes)
    box.text = arguments.text
    return "Alarm set for \(arguments.minutes) minutes from now."
  }
}

@available(macOS 26.0, *)
enum OnDeviceAI {
  static func availability() -> [String: String] {
    switch SystemLanguageModel.default.availability {
    case .available: return ["status": "available", "reason": ""]
    case .unavailable(.deviceNotEligible): return ["status": "unavailable", "reason": "deviceNotEligible"]
    case .unavailable(.appleIntelligenceNotEnabled):
      return ["status": "unavailable", "reason": "appleIntelligenceNotEnabled"]
    case .unavailable(.modelNotReady): return ["status": "unavailable", "reason": "modelNotReady"]
    case .unavailable(let other): return ["status": "unavailable", "reason": "\(other)"]
    }
  }

  static func respond(instructions: String, prompt: String, tools: Bool) async -> [String: Any] {
    guard case .available = SystemLanguageModel.default.availability else {
      return ["error": "unavailable", "reason": availability()["reason"] ?? ""]
    }
    let box = ReminderBox()
    let session = tools
      ? LanguageModelSession(tools: [SetReminderTool(box: box)], instructions: instructions)
      : LanguageModelSession(instructions: instructions)
    do {
      let r = try await session.respond(to: prompt, generating: PetReply.self)
      var out: [String: Any] = ["text": r.content.text, "mood": r.content.mood, "remember": r.content.remember]
      if let m = box.minutes { out["reminder"] = ["minutes": m, "text": box.text] }
      return out
    } catch let e as LanguageModelSession.GenerationError {
      switch e {
      case .guardrailViolation: return ["error": "guardrail"]
      case .exceededContextWindowSize: return ["error": "context"]
      case .unsupportedLanguageOrLocale: return ["error": "language"]
      default: return ["error": "\(e)"]
      }
    } catch {
      return ["error": "\(error)"]
    }
  }
}
#endif
