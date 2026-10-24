import SwiftUI

@main
struct MaxTrainerApp: App {
    @StateObject private var engine = TrainerEngine()

    var body: some Scene {
        WindowGroup {
            TrainerView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
