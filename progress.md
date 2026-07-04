# Bartender風セカンダリバー設計メモ

## 目的

Hidden Bar のトグルボタンをクリックしたときに、macOS のメニューバー直下へ
一時的なセカンダリバーを表示する。将来的には、Hidden Bar で隠したメニュー
バー項目を Bartender Bar のように下段へ並べて操作できる状態を目指す。

## 現在の Hidden Bar の仕組み

Hidden Bar は、他アプリのメニューバー項目を取得・所有・再描画していない。
現在は `NSStatusItem` の区切り項目の幅を大きくして、左側の項目を画面外へ
押し出すことで「隠れているように見せている」。

この方式はシンプルで権限も少ないが、隠した本物のメニューアイコンを別ウィンドウ
に表示することはできない。

## 実現に必要な機能

本物に近いセカンダリバーを作るには、現在の `NSStatusItem.length` 方式だけでは
足りない。追加で以下が必要になる。

- 画面収録権限
  - メニューバー領域だけを読み取り、各アイコンの見た目をキャプチャする。
- アクセシビリティ権限
  - メニューバー項目の位置取得、移動、クリック転送を行う。
- オーバーレイウィンドウ
  - メニューバー直下に、枠なしの一時ウィンドウを表示する。
- 対応関係の管理
  - セカンダリバー上のアイコン画像と、本物のメニューバー項目を紐づける。

MacBook のノッチに隠れている部分は、画面収録では直接キャプチャできない。
ノッチ裏にある項目は、いったん見える位置に出してからキャプチャする必要がある。

## 想定アーキテクチャ

### `MenuBarScanner`

- メニューバーの位置とサイズを取得する。
- メニューバー領域だけをスクリーンショットする。
- 表示中のメニューアイコン領域を切り出す。

### `MenuBarAccessibilityController`

- Accessibility API で取得可能なメニューバー項目を列挙する。
- 各項目の位置とサイズを読む。
- セカンダリバー上のクリックを、本物の項目へ転送する。
- ノッチや混雑で見えない項目を一時的に見える位置へ出す。

### `SecondaryBarWindowController`

- アクティブな画面のメニューバー直下に、枠なしの浮動ウィンドウを表示する。
- キャプチャしたアイコン画像をボタンとして並べる。
- 外側クリック、Esc、項目クリックで閉じる。

### `HiddenItemStore`

- 隠し項目のスナップショットを順序付きで保持する。
- 画像、元の位置、Accessibility 要素、フォールバック用クリック座標を管理する。

## 実装フェーズ

### Phase 1: UI の土台

本物のメニューバー項目取得は行わず、まずセカンダリバーの見た目と表示制御だけを作る。

- 既存の展開/折りたたみボタンから表示/非表示できるようにする。
- 現在の画面のメニューバー直下へ配置する。
- 仮のアイコンやサンプル項目を表示する。
- ウィンドウの重なり順、閉じ方、マルチディスプレイ、ライト/ダーク表示を確認する。

### Phase 2: 表示中メニューバーのキャプチャ

画面収録を使って、現在見えているメニューバー項目の画像を取得する。

- 画面収録権限を要求する。
- 読み取る範囲はメニューバー領域だけに限定する。
- キャプチャしたアイコン画像をセカンダリバーに表示する。
- この段階ではクリック操作の転送は行わない。

### Phase 3: Accessibility との紐づけ

キャプチャ画像と、本物のメニューバー項目を紐づける。

- アクセシビリティ権限を要求する。
- AX で得た項目フレームと、キャプチャした画像領域を対応させる。
- セカンダリバー上のボタンをクリックしたら、本物の項目をクリックする。
- AX メタデータが不安定な項目向けにフォールバックを用意する。

### Phase 4: 隠れた項目・ノッチ項目への対応

現在見えていない項目も扱えるようにする。

- Hidden Bar を一時的に展開する、または表示中の項目を一時的に隠してスペースを作る。
- 新しく見えるようになった項目をキャプチャする。
- キャプチャ後にメニューバー状態を元へ戻す。
- ノッチ裏の項目は、見える領域へ移動・表示してからキャプチャする。

### Phase 5: 製品化

- セカンダリバー機能の有効/無効設定を追加する。
- 権限状態の診断 UI を追加する。
- キャプチャ失敗、AX 紐づけ失敗のログを追加する。
- 既存の低権限な Hidden Bar 動作はデフォルトとして残す。

## リスク

- 画面収録とアクセシビリティは、ユーザーにとって許可ハードルが高い。
- macOS バージョンごとに AX 挙動が変わる可能性がある。
- メニュー項目を提供するアプリによって AX 情報の品質が違う。
- ノッチ対応は、表示状態を一時的に変更する必要がある。
- アニメーションやリアルタイム更新されるアイコンは、キャプチャ画像が古くなりやすい。
- App Store 配布は難しくなる可能性がある。

## 直近の方針

まずは Phase 1 のみ実装する。つまり、本物のメニューアイコン取得には進まず、
セカンダリバーの UI、表示位置、閉じ方、既存 Hidden Bar との連携だけを作る。

UI が安定してから、画面収録とアクセシビリティを使う Phase 2 以降に進むか判断する。

## Phase 1 実装記録 (2026-07-04)

### 実装内容

- **`hidden/Features/StatusBar/SecondaryBarWindowController.swift`** を新規作成
  - シングルトン (`SecondaryBarWindowController.shared`)
  - `NSPanel` (`borderless` + `nonactivatingPanel`) を使用
  - `NSVisualEffectView` (`.menu`) によるライト/ダークモード自動追従の背景
  - SF Symbols 8個 (`wifi`, `battery.100`, `magnifyingglass`, `bell.fill`, `gearshape`, `lock.fill`, `icloud`, `clock`) を仮アイコンとして `NSStackView` に横並び
  - 表示位置: マウスがある画面のメニューバー直下（`NSStatusBar.system.thickness` 基準）、最大幅600pt・中央揃え
  - 閉じ方: Escキー (`keyDown` ローカルモニター)、バー外クリック（ローカル + グローバルモニター）、折りたたみボタン再クリック
  - マルチディスプレイ: `.canJoinAllSpaces` + `.stationary`
  - イベントモニターは表示時のみ有効（`show()` / `hide()` で着脱）

- **`hidden/Features/StatusBar/StatusBarController.swift`** を修正
  - `collapseMenuBar()` 末尾に `SecondaryBarWindowController.shared.show()` 追加
  - `expandMenubar()` 末尾に `SecondaryBarWindowController.shared.hide()` 追加
  - 既存の `NSStatusItem.length` による隠し機構は変更なし

- **`Hidden Bar.xcodeproj/project.pbxproj`** に新規ファイルを登録
  - `DEADBEEF0000000200000002` : PBXFileReference
  - `DEADBEEF0000000100000001` : PBXBuildFile
  - StatusBar グループに追加
  - Sources ビルドフェーズに追加

### 追加していないもの（Phase 2 以降）

- Screen Recording 権限
- Accessibility 権限
- 他アプリの本物のメニューバー項目の取得・キャプチャ
- クリック転送
- ノッチ対応

### ビルド状況

- `swift -frontend -parse` による構文チェックは両ファイルともパス
- DeepSeek TUI の sandbox 制限により `xcodebuild` が `~/Library/Caches/org.swift.swiftpm/` へ書き込みできず、Release ビルドは未確認
- Xcode またはターミナルから以下のコマンドでビルド可能:
  ```
  cd /Users/gen/WORK/AI/hidden
  xcodebuild -project "Hidden Bar.xcodeproj" -scheme "Hidden Bar" \
    -configuration Release build
  ```

### 残課題

- [ ] Release ビルドの動作確認（Xcode またはターミナルで直接実行）
- [ ] 実機での表示位置・閉じ方の確認
- [ ] フルスクリーン時の挙動確認（メニューバー非表示時）
- [ ] サンプルアイコンのクリック時に `NSLog` が出ることの確認
