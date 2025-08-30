import SwiftUI

// MARK: - BackupHistoryView
/// バックアップ履歴表示画面
struct BackupHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var backupManager: iCloudBackupManager
    
    var body: some View {
        NavigationView {
            VStack {
                if backupManager.backupHistory.isEmpty {
                    emptyHistoryView
                } else {
                    historyListView
                }
            }
            .navigationTitle("操作履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyHistoryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("履歴がありません")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("バックアップ、復元、削除を行うと履歴に記録されます")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - History List
    private var historyListView: some View {
        List {
            ForEach(backupManager.backupHistory) { item in
                BackupHistoryItemRow(item: item)
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - BackupHistoryItemRow
/// バックアップ履歴項目の行
struct BackupHistoryItemRow: View {
    let item: BackupHistoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: item.actionIcon)
                    .font(.title2)
                    .foregroundColor(item.actionColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayText)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(item.formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let count = item.memoCount {
                        Text("\(count)件のメモ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    BackupHistoryView(backupManager: iCloudBackupManager.shared)
}