import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("CrystalMail")
                .font(.largeTitle)
                .bold()
            Text("iOS-версия — проверка сборки")
                .foregroundColor(.secondary)
            Text("Если ты видишь этот экран на iPad — цепочка сборки работает.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
