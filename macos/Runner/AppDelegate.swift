import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  /// Hoodimate > Settings… (⌘,): the Dart side opens the panel on Settings.
  @IBAction func openSettings(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    MenuChannel.channel?.invokeMethod("settings", arguments: nil)
  }

  /// Help > Hoodimate Help: the Dart side opens the support page (https only).
  @IBAction func openHelp(_ sender: Any?) {
    MenuChannel.channel?.invokeMethod("help", arguments: nil)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
