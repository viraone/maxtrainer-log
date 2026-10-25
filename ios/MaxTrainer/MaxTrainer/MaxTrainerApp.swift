import SwiftUI

@main
struct MaxTrainerApp: App {
    @StateObject private var engine = TrainerEngine()

    init() { Brand.applyAppearance() }

    var body: some Scene {
        WindowGroup {
            TrainerView()
                .environmentObject(engine)
                .font(.brand(.body))
                .preferredColorScheme(.dark)
        }
    }
}
