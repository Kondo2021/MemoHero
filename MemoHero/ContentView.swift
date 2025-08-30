import SwiftUI

// MARK: - ContentView
/// アプリのルートビューコンテナ
/// メインのビュー階層の起点となる最上位コンポーネント
/// 実際の機能はMemoListViewに委譲し、通知によるイベント一覧表示も処理
struct ContentView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var firebaseService: FirebaseService
    
    // MARK: - State Properties
    @State private var showingEventList = false
    
    // MARK: - Body
    /// メインビューの構成
    /// MemoListViewを表示し、通知によるイベント一覧表示も処理
    var body: some View {
        MemoListView()
            .sheet(isPresented: $showingEventList) {
                EventListView()
                    .environmentObject(firebaseService)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PresentEventList"))) { notification in
                handlePresentEventList(notification)
            }
    }
    
    // MARK: - Private Methods
    
    /// イベント一覧表示処理
    /// - Parameter notification: 通知情報
    private func handlePresentEventList(_ notification: Notification) {
        print("📅 イベント一覧の表示処理を開始")
        if let source = notification.userInfo?["source"] as? String {
            print("📅 要求元: \(source)")
        }
        
        DispatchQueue.main.async {
            showingEventList = true
        }
    }
}

// MARK: - Preview
/// SwiftUI プレビュー用の設定
/// 開発時のUI確認に使用
#Preview {
    ContentView()
}