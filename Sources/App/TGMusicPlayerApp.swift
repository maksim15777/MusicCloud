import SwiftUI

@main
struct TGMusicPlayerApp: App {
    init() {
        // Dark theme global styling
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
