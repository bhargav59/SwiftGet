import SwiftUI

struct CategorySidebarView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @Binding var selectedCategory: DownloadCategory

    var body: some View {
        List(DownloadCategory.allCases, selection: $selectedCategory) { category in
            Label {
                HStack {
                    Text(category.rawValue)
                    Spacer()
                    let count = downloadManager.tasks.filter {
                        category == .all || $0.category == category
                    }.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            } icon: {
                Image(systemName: category.systemImage)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SwiftGet")
    }
}
