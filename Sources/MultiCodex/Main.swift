import AppKit
import MultiCodexCore

@main
struct Main {
  @MainActor static func main() {
    let arguments = CommandLine.arguments
    let root: URL
    if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
      root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    } else {
      root = ProfileStore.defaultRoot(home: FileManager.default.homeDirectoryForCurrentUser)
    }
    do {
      let controller = try AppController(root: root)
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      let delegate = AppDelegate(controller: controller)
      application.delegate = delegate
      withExtendedLifetime(delegate) { application.run() }
    } catch {
      let alert = NSAlert()
      alert.messageText = "MultiCodex를 시작하지 못했습니다"
      alert.informativeText = error.localizedDescription
      alert.addButton(withTitle: "닫기")
      alert.runModal()
    }
  }
}
