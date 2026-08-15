# CLAUDE.md (tools/CopyOneDriveLink)

OneDriveでローカル同期しているSharePointライブラリについて、ローカルファイル
パスとSharePoint上のURLを相互変換するためのPowerShellモジュール。
`src/CopyOneDriveLink.psm1` を参照。

（旧名`OneDriveUtils`。2026-08-16にリネーム。フォルダ名・主要ファイル名・
`*OneDriveUtils*`という関数名接頭辞は全て`*OneDrive*`に統一済み。
`Copy-OneDriveLink.ps1`/`.vbs`は元々この名前だったため変更なし。）

全サブプロジェクト共通のルール（確定操作ボタンを押さない原則、日本語での
メッセージ記述規約など）は [../../CLAUDE.md](../../CLAUDE.md) を参照。

## 背景

OneDriveの同期先ローカルフォルダ（例: `D:\Contoso Corporation`）はPCごとに
異なる（ドライブ文字・フォルダ名とも）。これを吸収するため、レジストリから
同期先情報を取得する。

## 調査結果（2026-08-16 実機検証）

- `HKCU\Software\SyncEngines\Providers\OneDrive\<GUID>` 配下の各キーが同期中の
  ライブラリ1つに対応し、`MountPoint`（ローカル同期先フルパス）・
  `UrlNamespace`（SharePoint側のライブラリルートURL）・`LibraryType`
  （`teamsite`/`mysite`等）を持つ。他の候補
  （`HKCU\Software\Microsoft\OneDrive\Accounts\Business1\Tenants\...` 等）は
  URLとの対応が取れない、または個人用フォルダしか示さないため不採用。
- **`teamsite`（Teamsチャネル等）の場合、`UrlNamespace`はライブラリルートまで
  しか示さず、実際に同期対象としているサブフォルダ名を含まない。**
  同一サイト内の別チャネルを同期した2つのローカルフォルダ
  （`総務部 - 全体` と `総務部 - 資料共有`）で
  `UrlNamespace`が完全に同一だったことから判明した。
- ローカル同期フォルダ名は `<サイト表示名> - <サーバー側フォルダ名>` という
  命名規則になっており、末尾の部分（最初の `" - "` より後ろ全部）を
  `UrlNamespace`の直後に挿入することで正しいURLが組み立てられる。
  実機で2件（`総務部 - 全体` → ファイル1件、
  `総務部 - 資料共有` → フォルダ）を検証済み。
- `mysite`/`personal`（個人用OneDrive）はこのサブフォルダ挿入が不要
  （`MountPoint`と`UrlNamespace`が1:1対応）。
- **`FullRemotePath`（teamsiteのみ）は、実際に同期しているフォルダの完全URLを
  OneDriveクライアント自身が書き込んだ値**であることを確認した
  （`MountPoint`/`UrlNamespace`/`LibraryType`と同じキー配下）。これを使えば
  上記のローカル同期フォルダ名からの推測（サイト名とフォルダ名の境界を
  `" - "`の位置で当てずっぽうに決める方式）が一切不要になる。
  `Get-OneDriveSyncFolders`で取得し、`Resolve-OneDriveServerFolderSegment`/
  `Get-OneDriveTeamChannelInfo`で最優先に使用している（ローカル同期フォルダ名
  からの推測は、万一`FullRemotePath`が取得できなかった場合のみのフォールバック）。

## エクスプローラ統合（SendTo・スタートアップ・右クリックメニュー）

`Install-OneDriveSendTo`/`Install-OneDriveStartup`/`Install-OneDriveContextMenu`
（およびそれぞれの`Test-`/`Uninstall-`）で、SendToメニュー・ログオン時自動起動・
右クリックメニューへの登録を行う。いずれもHKCU/ユーザースコープのみで
UAC昇格は不要。右クリックメニューは全ファイル種別が対象（OneDrive同期フォルダ
配下限定の絞り込みは試したが撤退。経緯は
[docs/context-menu-investigation.md](docs/context-menu-investigation.md)を参照）。
右クリックメニューのアイコンは`assets/icon.ico`（System.Drawingで生成した
OneDriveブルーの角丸バッジ＋白いリンクの鎖）を使用。常駐トレイアイコンは
同じ絵柄をその場でビットマップ描画する方式（`.ico`ファイル読み込みだと
`System.Drawing.Icon`経由では透過が正しく反映されず空白表示になる問題が
あったため）。

## 常駐アプリ（タスクトレイ）

`CopyOneDriveLinkTrayApp.ps1`はグローバルホットキー・SendTo・`.bat`/`.vbs`
ダブルクリックなど複数の起動経路があるため、Mutexで多重起動を防止している。
実装時に「`[ref]`へ未初期化の`$script:`スコープ変数を渡すと常に多重起動と
誤判定される」という不具合を踏んだ。詳細は
[docs/single-instance-mutex-investigation.md](docs/single-instance-mutex-investigation.md)
を参照。

## 既知の制約

- ~~ローカル同期フォルダ名に `" - "` が複数回含まれるケースでの誤動作~~ →
  **2026-08-16に解決済み。** 当初は `Resolve-OneDriveServerFolderSegment` が
  ローカル同期フォルダ名を「最初の`" - "`より後ろ全部をサーバー側フォルダ名
  とする」方式で推測しており、サイト表示名自体に`" - "`を含むケース
  （実機の同期フォルダで実例あり: サイト表示名
  `サンプル案件管理PJ - Phase1納品`、ローカル同期フォルダ名
  `サンプル案件管理PJ - Phase1納品 - Phase1納品`）でURLの組み立てを誤る
  不具合があった。上記の`FullRemotePath`（実際に同期しているフォルダの
  完全URLをOneDriveクライアント自身が書き込んだ値）を最優先で使う方式に
  修正し、`ConvertTo-OneDriveUrl`/`Get-OneDriveShareSegments`/
  `Get-OneDriveTeamChannelInfo`のいずれも実機の全同期フォルダ（12件）で
  正しい結果を返すことを確認済み。ローカル同期フォルダ名からの推測は、
  `FullRemotePath`が万一取得できなかった場合のみのフォールバックとして残置。
- `ConvertTo-OneDriveUrl` が返すのはSharePoint UIの「リンクのコピー」で得られる
  共有リンク（`sourcedoc=<GUID>&...`形式）とは別物で、アイテム固有GUIDを含まない
  「サーバー相対URL」形式。ブラウザで開く/REST API
  （`_api/web/GetFileByServerRelativeUrl`等）での参照には使えるが、
  厳密な共有リンクが必要な用途には使えない。
