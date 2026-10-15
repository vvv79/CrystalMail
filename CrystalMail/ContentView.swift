import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.isLoggedIn {
            MainView()
        } else {
            LoginView()
        }
    }
}

struct MainView: View {
    var body: some View {
        NavigationView {
            FolderListView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
