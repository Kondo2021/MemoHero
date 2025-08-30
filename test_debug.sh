#!/bin/bash

# シミュレーターのデバイスIDを取得
DEVICE_ID="73615DE7-52DE-4018-B0F0-825442DBA6C6"

echo "=== デバッグテスト開始 ==="
echo "1. シミュレーターを起動中..."

# シミュレーターを起動
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || echo "シミュレーターは既に起動しています"

# アプリをアンインストール（初回起動状態にするため）
echo "2. アプリをアンインストール（初回起動状態にするため）..."
xcrun simctl uninstall "$DEVICE_ID" com.memoapp.edfusion 2>/dev/null

# アプリをインストール
echo "3. アプリをインストール中..."
xcrun simctl install "$DEVICE_ID" "/Users/kondokenji/Library/Developer/Xcode/DerivedData/MemoApp-cgnfjfcjnselopcbwqmkaizzxapk/Build/Products/Debug-iphonesimulator/MemoApp.app"

# コンソールログを取得開始（バックグラウンドで実行）
echo "4. コンソールログ取得開始..."
xcrun simctl spawn "$DEVICE_ID" log stream --predicate 'processImagePath contains "MemoApp"' > memo_debug.log 2>&1 &
LOG_PID=$!

# 少し待ってからアプリを起動
sleep 2
echo "5. アプリを起動中..."
xcrun simctl launch "$DEVICE_ID" com.memoapp.edfusion

# アプリ起動後しばらく待つ
echo "6. アプリ動作ログを収集中（10秒間）..."
sleep 10

# ログ取得を停止
kill $LOG_PID 2>/dev/null

echo "=== デバッグテスト完了 ==="
echo "ログファイル: memo_debug.log"
echo ""
echo "初回起動時のログ："
cat memo_debug.log