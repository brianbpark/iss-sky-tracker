import SwiftUI

@main
struct ISSSkyTrackerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear { model.start() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            SkyView()
                .tabItem { Label("Sky", systemImage: "camera.viewfinder") }
                .tag(AppModel.Tab.sky)
            PassListView()
                .tabItem { Label("Passes", systemImage: "calendar") }
                .tag(AppModel.Tab.passes)
        }
        .tint(.yellow)
    }
}
