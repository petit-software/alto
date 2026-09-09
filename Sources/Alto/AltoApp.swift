import SwiftUI
import AltoUI

@main
struct AltoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { AltoSettingsRoot(delegate: delegate) } }
}
