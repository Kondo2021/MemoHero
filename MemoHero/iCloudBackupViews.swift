import SwiftUI

// MARK: - iCloudBackupView
/// iCloudバックアップ画面（シンプル版）
struct iCloudBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var memoStore: MemoStore
    @StateObject private var backupManager = iCloudBackupManager.shared
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isBackupSuccess = false
    @State private var showingRestoreConfirmation = false
    @State private var showingBackupList = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBackupWithComment = false
    @State private var showingBackupHistory = false
    @State private var showingHistoryClearConfirmation = false
    @State private var backupComment = ""
    @State private var backupToDelete: BackupItem?
    @State private var backupToRestore: BackupItem?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // iCloud状態表示
                iCloudStatusView
                
                // バックアップ情報表示
                backupInfoView
                
                Spacer()
                
                // 全ボタンをまとめて配置
                VStack(spacing: 16) {
                    // アクションボタン
                    actionButtonsView
                    
                    // バックアップ管理ボタン
                    manageBackupsButton
                    
                    // 操作履歴ボタン
                    operationHistoryButton
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("iCloudバックアップ")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isBackupSuccess ? "完了" : "エラー", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .alert("データ復元", isPresented: $showingRestoreConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("復元する", role: .destructive) {
                    performRestore()
                }
            } message: {
                Text("現在のメモデータが置き換えられます。この操作は元に戻せません。")
            }
            .alert("バックアップを削除", isPresented: $showingDeleteConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    if let backup = backupToDelete {
                        performDelete(backup)
                    }
                }
            } message: {
                Text("このバックアップを完全に削除します。この操作は元に戻せません。")
            }
            .alert("操作履歴を全削除", isPresented: $showingHistoryClearConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("全削除", role: .destructive) {
                    performHistoryClear()
                }
            } message: {
                Text("すべての操作履歴を削除します。この操作は元に戻せません。")
            }
            .sheet(isPresented: $showingBackupList) {
                BackupListView(backupManager: backupManager, 
                               onRestore: { backup in
                                   backupToRestore = backup
                                   showingBackupList = false
                                   showingRestoreConfirmation = true
                               },
                               onDelete: { backup in
                                   backupToDelete = backup
                                   showingBackupList = false
                                   showingDeleteConfirmation = true
                               })
            }
            .sheet(isPresented: $showingBackupWithComment) {
                BackupWithCommentView(
                    memoStore: memoStore,
                    backupManager: backupManager,
                    comment: $backupComment,
                    onBackupCompleted: { success, message in
                        showingBackupWithComment = false
                        backupComment = ""
                        isBackupSuccess = success
                        alertMessage = message
                        showingAlert = true
                    }
                )
            }
            .sheet(isPresented: $showingBackupHistory) {
                NavigationView {
                    VStack {
                        if backupManager.backupHistory.isEmpty {
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
                        } else {
                            List {
                                ForEach(backupManager.backupHistory) { item in
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
                            .listStyle(PlainListStyle())
                        }
                    }
                    .navigationTitle("操作履歴")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("全削除") {
                                showingHistoryClearConfirmation = true
                            }
                            .foregroundColor(.red)
                            .disabled(backupManager.backupHistory.isEmpty)
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("閉じる") {
                                showingBackupHistory = false
                            }
                        }
                    }
                }
            }
            .onAppear {
                backupManager.checkiCloudAvailability()
                Task {
                    try? await backupManager.fetchAllBackups()
                }
            }
        }
    }
    
    // MARK: - Manage Backups Button
    private var manageBackupsButton: some View {
        Button(action: {
            showingBackupList = true
        }) {
            HStack {
                Image(systemName: "list.bullet")
                Text("バックアップ管理（復元・削除）")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(.primary)
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .disabled(!backupManager.isAvailable)
    }
    
    // MARK: - View Components
    private var iCloudStatusView: some View {
        HStack(spacing: 12) {
            Image(systemName: backupManager.isAvailable ? "checkmark.icloud" : "exclamationmark.icloud")
                .font(.system(size: 30))
                .foregroundColor(backupManager.isAvailable ? .green : .red)
            
            VStack(alignment: .leading) {
                Text(backupManager.isAvailable ? "iCloud利用可能" : "iCloud利用不可")
                    .font(.headline)
                    .foregroundColor(backupManager.isAvailable ? .primary : .red)
                
                if !backupManager.isAvailable {
                    Text("設定でiCloudにサインインしてください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var backupInfoView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("現在のメモ数:")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(memoStore.memos.count)件")
                    .fontWeight(.medium)
            }
            
            HStack {
                Text("最終バックアップ:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(backupManager.latestBackupInfo)
                    .fontWeight(.medium)
                    .foregroundColor(backupManager.latestBackupInfo == "バックアップなし" ? .red : .primary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(8)
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            // バックアップボタン（クイック）
            Button(action: performBackup) {
                HStack {
                    if backupManager.isBackingUp {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                    Text(backupManager.isBackingUp ? "バックアップ中..." : "クイックバックアップ")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundColor(.white)
                .background(backupManager.isAvailable && !backupManager.isBackingUp ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!backupManager.isAvailable || backupManager.isBackingUp)
            
            // バックアップボタン（コメント付き）
            Button(action: {
                showingBackupWithComment = true
            }) {
                HStack {
                    Image(systemName: "icloud.and.arrow.up.fill")
                    Text("コメント付きバックアップ")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundColor(.blue)
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
            }
            .disabled(!backupManager.isAvailable || backupManager.isBackingUp)
            
        }
    }
    
    private var operationHistoryButton: some View {
        Button(action: {
            showingBackupHistory = true
        }) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                Text("操作履歴")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(.primary)
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .disabled(!backupManager.isAvailable)
    }
    
    // MARK: - Actions
    private func performBackup() {
        Task {
            do {
                try await memoStore.backupToiCloud()
                
                await MainActor.run {
                    isBackupSuccess = true
                    alertMessage = "バックアップが完了しました"
                    showingAlert = true
                }
                
            } catch {
                await MainActor.run {
                    isBackupSuccess = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
    
    private func performRestore() {
        let backupToUse = backupToRestore ?? backupManager.backupItems.first
        
        Task {
            do {
                if let backup = backupToUse {
                    let memos = try await backupManager.restoreFromBackup(backup)
                    await memoStore.replaceMemos(with: memos)
                } else {
                    try await memoStore.restoreFromiCloud()
                }
                
                await MainActor.run {
                    isBackupSuccess = true
                    alertMessage = "復元が完了しました"
                    showingAlert = true
                    backupToRestore = nil
                }
                
            } catch {
                await MainActor.run {
                    isBackupSuccess = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                    backupToRestore = nil
                }
            }
        }
    }
    
    private func performDelete(_ backup: BackupItem) {
        Task {
            do {
                try await backupManager.deleteBackup(backup)
                
                await MainActor.run {
                    isBackupSuccess = true
                    alertMessage = "バックアップを削除しました"
                    showingAlert = true
                    backupToDelete = nil
                }
                
            } catch {
                await MainActor.run {
                    isBackupSuccess = false
                    alertMessage = error.localizedDescription
                    showingAlert = true
                    backupToDelete = nil
                }
            }
        }
    }
    
    private func performHistoryClear() {
        backupManager.clearAllHistory()
        isBackupSuccess = true
        alertMessage = "操作履歴をすべて削除しました"
        showingAlert = true
    }
}

// MARK: - BackupListView
/// バックアップ一覧・管理画面
struct BackupListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var backupManager: iCloudBackupManager
    let onRestore: (BackupItem) -> Void
    let onDelete: (BackupItem) -> Void
    
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            VStack {
                if backupManager.backupItems.isEmpty {
                    emptyStateView
                } else {
                    backupListView
                }
            }
            .navigationTitle("バックアップ一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshBackups) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .onAppear {
                refreshBackups()
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("バックアップがありません")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("メモをバックアップしてからもう一度お試しください")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Backup List
    private var backupListView: some View {
        List {
            ForEach(backupManager.backupItems) { backup in
                BackupItemRow(
                    backup: backup,
                    isLatest: backup.id == backupManager.backupItems.first?.id,
                    onRestore: { onRestore(backup) },
                    onDelete: { onDelete(backup) }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Actions
    private func refreshBackups() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        Task {
            try? await backupManager.fetchAllBackups()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

// MARK: - BackupItemRow
/// バックアップアイテムの行
struct BackupItemRow: View {
    let backup: BackupItem
    let isLatest: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 情報表示部分
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if !backup.comment.isEmpty {
                        Text(backup.comment)
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else {
                        Text("\(backup.memoCount)件のメモ")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    if isLatest {
                        Text("最新")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                }
                
                HStack {
                    Text("\(backup.memoCount)件のメモ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("・")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(backup.formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            // アクションボタン部分
            HStack(spacing: 12) {
                Button(action: onRestore) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.down")
                        Text("復元")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("削除")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    iCloudBackupView()
        .environmentObject(MemoStore())
}

#Preview {
    BackupListView(
        backupManager: iCloudBackupManager.shared,
        onRestore: { _ in },
        onDelete: { _ in }
    )
}

// MARK: - BackupWithCommentView
/// コメント付きバックアップ作成画面
struct BackupWithCommentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var memoStore: MemoStore
    @ObservedObject var backupManager: iCloudBackupManager
    @Binding var comment: String
    let onBackupCompleted: (Bool, String) -> Void
    
    @State private var isBackingUp = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("バックアップコメント")
                        .font(.headline)
                    
                    Text("このバックアップに任意のコメントを追加できます（省略可）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("例: 重要な変更前のバックアップ", text: $comment)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isTextFieldFocused)
                }
                
                VStack(spacing: 12) {
                    HStack {
                        Text("メモ数:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(memoStore.memos.count)件")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("作成日時:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatCurrentDate())
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
                
                Spacer()
                
                Button(action: performBackup) {
                    HStack {
                        if isBackingUp {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "icloud.and.arrow.up.fill")
                        }
                        Text(isBackingUp ? "バックアップ中..." : "バックアップ作成")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundColor(.white)
                    .background(isBackingUp ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isBackingUp)
            }
            .padding()
            .navigationTitle("コメント付きバックアップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .disabled(isBackingUp)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
    
    private func formatCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    private func performBackup() {
        isBackingUp = true
        Task {
            do {
                try await memoStore.backupToiCloud(comment: comment)
                
                await MainActor.run {
                    isBackingUp = false
                    onBackupCompleted(true, "バックアップが完了しました")
                }
                
            } catch {
                await MainActor.run {
                    isBackingUp = false
                    onBackupCompleted(false, error.localizedDescription)
                }
            }
        }
    }
}
