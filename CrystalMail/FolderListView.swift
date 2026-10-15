import SwiftUI

struct FolderListView: View {
    @EnvironmentObject var app: AppState

    private let folders: [MailFolder] = [
        MailFolder(id: "inbox", name: "Входящие", symbol: "tray"),
        MailFolder(id: "sentitems", name: "Отправленные", symbol: "paperplane"),
        MailFolder(id: "drafts", name: "Черновики", symbol: "doc.text"),
        MailFolder(id: "deleteditems", name: "Корзина", symbol: "trash")
    ]

    var body: some View {
        List {
            ForEach(folders) { folder in
                NavigationLink(destination: MailListView(folderId: folder.id, folderName: folder.name)) {
                    Label(folder.name, systemImage: folder.symbol)
                        .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("CrystalMail")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                }
            }
        }
    }
}
