# TACT Companion

SwiftUI製のTACTクライアントの土台です。依存方向は次のように固定しています。

```text
View -> ViewModel -> TactRepository -> Service -> TACT
```

`TACTCompanion.xcodeproj` をXcodeで開いて実行できます。`project.yml` も同梱しているため、
XcodeGenでプロジェクトを再生成することもできます。

## 認証

`LoginView` が `WKWebView` でTACTの通常のSSOログイン画面を表示します。アプリはIDや
パスワードを受け取らず、ログイン後にTACTドメインのCookieだけを
`TactSessionService`へ渡します。Viewから `URLSession` や各Serviceを直接呼ぶことはありません。

## 拡張箇所

- 課題: `TactAssignmentService`
- 小テスト: `TactQuizService`
- お知らせ: `TactAnnouncementService`
- 画面向け集約: `TactRepository`

各ServiceのDTOをTACTの実レスポンスに合わせて調整しても、ViewとViewModelには影響しません。

## 画面

- 時間割: 曜日・時限ごとの授業と、未提出課題・未提出小テスト・お知らせ件数
- 提出期限: 全授業の未提出課題と小テストを期限の近い順に表示
- お知らせ: 全授業のお知らせを公開日時の新しい順に表示

時間割は今年度の授業だけを対象にし、春1期・春2期・秋1期・秋2期を切り替えられます。
月曜から金曜までは横スクロールなしで画面幅に収め、土曜または曜日・時限が取得できない
授業は「曜日・時限未設定」に表示されます。

提出期限画面では期限切れ項目の表示を切り替えられます。不要な未提出項目はスワイプで
非表示にでき、非表示状態は端末内に保存されます。

授業、課題、小テスト、お知らせのリンクは、ログインCookieを共有するアプリ内ブラウザで
TACTを開きます。小テストはTACTの仕様上、個別受験URLをGETだけで再現できないため、
該当授業の小テスト一覧画面を開きます。

授業一覧と曜日・時限はログイン後のTACTポータルHTMLから取得します。課題はAssignment
Direct API、小テストはSamigo Direct API、お知らせはAnnouncements画面から取得します。
TACTがログイン画面へ戻した場合やJSON APIがHTMLを返した場合は、セッション切れとして扱います。
