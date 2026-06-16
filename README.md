# TACT Companion

TACT Companionは、TACTの授業情報、課題、小テスト、お知らせ、授業資料をiPhoneで確認しやすくするためのSwiftUIアプリです。

画面から直接TACTへ通信せず、次の依存方向で実装しています。

```text
View -> ViewModel -> TactRepository -> Service -> TACT
```

## 主な機能

- 時間割表示
  - 月曜から金曜までをスマホ画面に収めて表示
  - 春1期、春2期、秋1期、秋2期の切り替え
  - 未提出課題、未提出小テスト、お知らせ件数を授業ごとに表示
  - 同じ科目が連続している場合はまとめて表示
- 授業詳細
  - 授業情報、未提出課題、小テスト、お知らせ、授業資料を表示
  - 授業資料フォルダをアプリ内で展開
  - TACTへのリンクをアプリ内ブラウザで表示
- 提出期限
  - 課題と小テストを期限順に表示
  - 期限切れ表示の切り替え
  - 個別非表示と復元
  - 残り時間に応じた色分けと「n時間以内」「n日以内」「n週間以内」表示
- カレンダー
  - 課題と小テストの提出日をカレンダー形式で表示
  - 選択した日の提出物を一覧表示
- お知らせ
  - 全授業のお知らせを新着順に表示
  - 本文をアプリ内で展開
  - 本文内URLをリンクとして表示し、アプリ内ブラウザで開く
  - TACT Companion利用者アンケート案内をお知らせとして表示
- 通知
  - 提出物が橙色判定になった後、設定時刻に通知
- ウィジェット
  - 提出期限リスト
  - 期限カレンダー
- キャッシュ
  - 授業、課題、小テスト、お知らせを端末内に保存
  - アプリ再起動後も読み込みを高速化
  - 春期、秋期の切り替わりやログアウト時にキャッシュを削除

## プロジェクト構成

```text
TACTCompanion/
|-- TACTCompanion.xcodeproj/
|-- TACTCompanion/
|   |-- Models/
|   |-- Services/
|   |-- Repositories/
|   |-- ViewModels/
|   |-- Views/
|   `-- Assets.xcassets/
|-- TACTCompanionWidget/
|-- TACTCompanionWidget-Info.plist
|-- project.yml
|-- TACTCompanion-Swift-Sources.txt
`-- TACTCompanion-Folder-Structure.txt
```

詳細なフォルダ構造は`TACTCompanion-Folder-Structure.txt`にまとめています。
Swiftファイルの確認用まとめは`TACTCompanion-Swift-Sources.txt`です。

## 主要ファイル

- `TACTCompanion/TACTCompanionApp.swift`
  - アプリのエントリポイント
- `TACTCompanion/Views/MainTabView.swift`
  - 時間割、提出期限、カレンダー、お知らせのタブ管理
- `TACTCompanion/Views/TimetableView.swift`
  - 時間割画面
- `TACTCompanion/Views/DeadlineListView.swift`
  - 提出期限画面と提出物カード
- `TACTCompanion/Views/DeadlineCalendarView.swift`
  - カレンダー画面
- `TACTCompanion/Views/AnnouncementListView.swift`
  - お知らせ画面
- `TACTCompanion/Views/CourseDetailView.swift`
  - 授業詳細画面
- `TACTCompanion/Repositories/TactRepository.swift`
  - ViewModelからTACT関連Serviceを利用するための窓口
- `TACTCompanion/Services/TactSessionService.swift`
  - TACTへのHTTP通信とセッション確認
- `TACTCompanion/Services/TactPersistentCache.swift`
  - 永続キャッシュ
- `TACTCompanion/Services/DeadlineNotificationService.swift`
  - 提出期限通知
- `TACTCompanionWidget/TACTCompanionWidget.swift`
  - Widget本体

## 認証

`LoginView`が`WKWebView`でTACTの通常ログイン画面を表示します。
アプリはIDやパスワードを直接受け取らず、ログイン後のTACTドメインCookieを利用して通信します。

ログアウト時には以下を削除します。

- TACT Cookie
- WebViewセッション
- 授業、課題、小テスト、お知らせのキャッシュ
- 非表示状態
- Widget用スナップショット

## TACTとの通信

TACTからの取得処理は`TactRepository`経由で行います。

- 授業一覧: TACTポータルHTML
- 課題: Assignment Direct API
- 小テスト: Samigo Direct API
- お知らせ: Announcements画面
- 授業資料: Resources画面

TACTがログイン画面へ戻した場合や、JSONを期待したAPIがHTMLを返した場合はセッション切れとして扱います。

## 設定

設定画面では以下を変更できます。

- 春期中に秋期、秋期中に春期も表示するか
- 時間割の件数に期限切れ課題、小テストを含めるか
- 提出期限の色分け基準
- 週の区切り曜日
- 通知のオン、オフ
- 通知時刻
- ログアウト

## ビルドと実行

Xcodeで以下を開きます。

```text
TACTCompanion/TACTCompanion.xcodeproj
```

実機で実行する場合は、Xcode上部の実行先に接続済みiPhoneを選択し、再生ボタンでビルドとインストールを行います。

コマンドラインでビルド確認する場合:

```sh
xcodebuild \
  -project TACTCompanion.xcodeproj \
  -scheme TACTCompanion \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## XcodeGen

`project.yml`を同梱しています。XcodeGenを利用する場合は、プロジェクト直下で以下を実行します。

```sh
xcodegen generate
```

通常は同梱済みの`TACTCompanion.xcodeproj`を開けば実行できます。

## Git管理

GitリポジトリのルートはこのREADMEがある`TACTCompanion/`直下です。

```text
TACTCompanion/
|-- .git/
|-- .gitignore
|-- .gitattributes
|-- TACTCompanion.xcodeproj/
|-- TACTCompanion/
`-- TACTCompanionWidget/
```

変更をGitHubへ反映する例:

```sh
git status
git add -A
git commit -m "Update TACT Companion"
git push origin main
```

pushが拒否された場合:

```sh
git pull --rebase origin main
git push origin main
```
