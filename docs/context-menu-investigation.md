# 右クリックメニュー統合に関する調査記録

`Install-OneDriveContextMenu`（エクスプローラ右クリックメニューへの直接登録）
まわりで検証した2つのテーマの記録。詳細な経緯・判断根拠を残すためのメモであり、
現状の実装仕様は [../CLAUDE.md](../CLAUDE.md) を参照。

## 1. OneDrive同期フォルダ配下限定の表示（`AppliesTo`） — 撤退

### やりたかったこと

本家OneDriveの右クリックメニューは、OneDrive同期フォルダ配下のアイテムでしか
メニュー項目が表示されない。同様の絞り込みを、COM拡張（DLL）を書かずに
レジストリ設定だけで実現できないか検証した。

### 試したこと

Windowsのシェル拡張には `AppliesTo` というレジストリ値があり、AQS
（Advanced Query Syntax）の条件式を書くと、条件に一致するアイテムでのみ
メニュー項目を表示できる、という仕組みが存在する（COM拡張なしで動く）。
`shell\<動詞名>` キー配下に以下のような値を追加して検証した。

```
AppliesTo = System.ItemFolderPathDisplay:"D:\Contoso Corporation" OR System.ItemFolderPathDisplay:"D:\OneDrive - Contoso Corporation"
```

`System.ItemFolderPathDisplay` はアイテムの「親フォルダパス」を表す
プロパティで、公式ドキュメントには次のような実例がある
（`NOT System.ItemFolderPathDisplay:"C:"` で「C:配下の全フォルダ以外」に一致、
という説明）。この前方一致的な挙動を利用した。

対象パス（`Get-OneDriveSyncFolders` の `MountPoint` の親フォルダ）を動的に
組み立てて `OR` で連結。ただし個人用OneDriveフォルダ（`D:\OneDrive - ...`)
のようにドライブ直下にあるケースでは、親を取ると `D:\` まで一般化されて
しまい、ドライブ全体に一致する過剰な条件になる不具合があったため、その場合は
親ではなくライブラリ自身のパスを使うよう調整した。

### 結果：実機で期待通り動作せず

実際にレジストリへ登録し、`AppliesTo`の条件に**明確に一致するはずの
ファイル**（`D:\Contoso Corporation\サンプル開発チーム - General\...`配下）を
右クリックしたところ、メニュー項目自体が表示されなくなった
（`AppliesTo`無しの状態では正しく表示されていた）。
条件が一致していないのではなく、**条件評価そのものが失敗して
非表示側に倒れている**挙動に見える。

### 考えられる原因（未確定）

- ドキュメントに「AQSはfast propertyでしか機能しない」という制約が明記されて
  いる（`IShellFolder2::GetDefaultColumnState`が`SHCOLSTATE_SLOW`を返さない
  プロパティのみ対象）。OneDriveの同期ファイルはクラウドプレースホルダー
  （オンデマンドファイル）という特殊な仕組みのため、`ItemFolderPathDisplay`が
  slow property扱いになっている可能性がある。
- `:`演算子によるパスの前方一致は、公式ドキュメントに載っている実例が
  `System.ItemName:"exampleText1"`（ファイル名の部分一致）や
  `System.Volume.BitlockerProtection:=2`（数値の完全一致）程度で、
  パス文字列に対する前方一致の正確な演算子・構文は見当たらなかった
  （`~`演算子は`System.Kind:~Library`のような列挙型プロパティの所属判定に
  使う例はあったが、パス文字列向けではなさそう）。
- 別の質問スレッドでは「AppliesTo/DefaultAppliesToはフォルダ背景
  （何もない場所）の右クリックでは機能しない」という既知の制限も見つかった
  （今回はファイル自体の右クリックなので直接の原因ではなさそうだが、
  AppliesTo自体が全体的にドキュメントが薄く、挙動が不安定な機能である
  傍証として記録しておく）。

### 判断：撤退

ドキュメントが薄く挙動の裏付けが取れない機能に依存するリスクが高いと判断し、
撤退した。現在の実装は**常時表示**（全ファイル種別が対象）に戻し、
OneDrive同期フォルダ外のファイルでクリックした場合は、
`Find-OneDriveSyncFolderMatch`が投げる例外をそのまま警告ダイアログに
表示して終了する形で対応している（[../CLAUDE.md](../CLAUDE.md)参照）。

### 将来再挑戦する場合の選択肢

条件付き表示を確実に実現するには、`IContextMenu`/`IExplorerCommand`を実装した
COM拡張（DLL）を書き、`QueryContextMenu`/`GetState`等で選択アイテムのパスを
実行時に判定する方式が本筋（本家OneDriveも恐らくこちら）。ただし現状の
軽量なPowerShell/VBS構成とは別次元の開発（DLLビルド・COM登録・配布）になる。

### 参考にした情報源

- [Creating Shortcut Menu Handlers - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers)
  （`AppliesTo`の公式説明・実例、fast property制約の記載元）
- [How to exclude libraries from custom right-click menu entries - Windows 10 Help Forums](https://www.tenforums.com/customization/173886-how-exclude-libraries-custom-right-click-menu-entries.html)
  （`System.ItemFolderPathDisplay`を使った実例）
- [How to exclude libraries from custom right-click menu entries using AppliesTo string? - Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/264315/how-to-exclude-libraries-from-custom-right-click-m)
  （フォルダ背景では`AppliesTo`が機能しないという既知の制限）

## 2. Windows 11の新しい右クリックメニューへの直接登録 — 対応外

Windows 11には「簡略化された新メニュー（既定、Shiftなし右クリック）」と
「従来の完全なメニュー（Shift+右クリック、または『その他のオプションを表示』）」
の2種類があり、`HKCU:\...\shell\...`のレジストリ登録は**従来メニュー側にのみ**
表示される、という仕様上の制約がある。

新メニューに直接登録するには、Windows App SDKの
`com.microsoft.windows.contextMenu`拡張を使ったMSIXパッケージ化アプリとして
作り直す必要があり、単発のPowerShell/VBS構成とは別次元の開発（パッケージング・
マニフェスト等）が要る。ユーザー判断により今回は対応外とした
（別解として「新メニュー自体を無効化し常に従来メニューを表示する」という
Windows全体設定のレジストリTweakも存在するが、これは自ツールのメニュー項目に
限らず全アプリの右クリック挙動に影響するため、今回は採用していない）。
