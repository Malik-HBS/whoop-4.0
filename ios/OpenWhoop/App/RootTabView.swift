import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "house")
                }

            SleepView()
                .tabItem {
                    Label("Sleep", systemImage: "bed.double")
                }

            HealthView()
                .tabItem {
                    Label("Health", systemImage: "heart.text.square")
                }

            WorkoutsView()
                .tabItem {
                    Label("Workouts", systemImage: "figure.run")
                }

            NavigationStack {
                LiveView()
            }
            .tabItem {
                Label("Device", systemImage: "wave.3.right")
            }
        }
    }
}
