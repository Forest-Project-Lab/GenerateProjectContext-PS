# GenerateProjectContext

指定されたディレクトリ構造とファイル内容をMarkdown形式で出力するPowerShellスクリプトです。主に大規模言語モデル (LLM) へのコンテキスト提供を目的としています。

## 機能

* 指定ディレクトリ以下のファイル構造をツリー形式で表示
* テキストベースのファイルの内容をMarkdownコードブロックとして出力
* 拡張子に応じたシンタックスハイライト指定 (可能な場合)
* 特定のファイル/ディレクトリを除外 (`-Exclude`, `-IgnoreFile`)
* 特定のファイル/ディレクトリのみを包含 (`-IncludeOnly`)
* 一般的なバイナリファイルの拡張子を持つファイルを除外 (`-ExcludeBinary`)
* 巨大なファイル (1MB超) の内容を省略
* 生成される出力ファイル自体を処理対象から自動的に除外
* UTF-8 (BOM無し) でMarkdownファイルを出力

## インストール

### 方法1: 手動

1.  `GenerateProjectContext.ps1` と `gpc.bat` をダウンロードします。
2.  これらのファイルを、環境変数 `PATH` が通っている任意のディレクトリ（例: `C:\Users\YourUser\Scripts`）に配置します。
3.  必要に応じて、PowerShellの実行ポリシーを設定します (後述の「注意点」を参照)。

### 方法2: Makefile (Windows環境で `make` が利用可能な場合)

1.  リポジトリ全体をクローンまたはダウンロードします。
2.  コマンドプロンプトまたはターミナルで、リポジトリのルートディレクトリに移動します。
3.  `make` コマンドがインストールされていることを確認します (例: `choco install make` など)。
4.  以下のコマンドを実行します:
    ```bash
    make setup
    ```
    これにより、デフォルトでは `%USERPROFILE%\MyPowerShellScripts\GenerateProjectContext` ディレクトリが作成され、スクリプトがコピーされ、そのディレクトリがユーザー環境変数 `PATH` に追加されます。
5.  **重要:** 環境変数 `PATH` の変更を有効にするには、コマンドプロンプトやターミナルを**再起動**する必要があります。場合によってはシステムの再起動が必要なこともあります。

## 使い方

スクリプトは直接 `GenerateProjectContext.ps1` を実行するか、便利なラッパー `gpc.bat` を使って実行できます (`PATH` が通っている場合)。

### 基本コマンド

```powershell
# PowerShell スクリプトを直接実行
.\GenerateProjectContext.ps1 -Path <対象ディレクトリ> -OutputFile <出力ファイル.md> [オプション...]

# バッチファイルラッパーを使用 (PATHが通っている場合)
gpc -Path <対象ディレクトリ> -OutputFile <出力ファイル.md> [オプション...]
```

### 実行例

```powershell
# カレントディレクトリの情報を context.md に出力
gpc -Path . -OutputFile context.md

# 特定のプロジェクトディレクトリの情報を出力し、node_modules と dist を除外
gpc -Path C:\Projects\MyWebApp -OutputFile webapp_context.md -Exclude "node_modules", "dist"

# src ディレクトリ内の .ts ファイルのみを出力し、バイナリを除外、 .llmignore ファイルを使用
gpc -Path .\src -OutputFile src_ts_context.md -IncludeOnly "*.ts" -ExcludeBinary -IgnoreFile .llmignore

# 詳細なログを表示しながら実行
gpc -Path . -OutputFile context_verbose.md -Verbose
```

## パラメータ

| パラメータ        | エイリアス | 型        | 必須 | 説明                                                                                                                               |
| :---------------- | :--------- | :-------- | :--- | :--------------------------------------------------------------------------------------------------------------------------------- |
| `Path`            |            | `string`  | Yes  | 情報を収集するルートディレクトリのパス。                                                                                             |
| `OutputFile`      |            | `string`  | Yes  | 結果を出力するMarkdownファイルへのパス。このファイル自体は処理から除外されます。                                                       |
| `Exclude`         |            | `string[]`| No   | 除外するファイル/ディレクトリパターン (ワイルドカード可)。複数指定可能。名前に区切り文字を含まない場合は名前のみ、含む場合はパスで比較。 |
| `IgnoreFile`      |            | `string`  | No   | 除外パターンを記述したファイルのパス。シンプルなワイルドカードのみサポート。                                                         |
| `IncludeOnly`     |            | `string[]`| No   | 含めるファイル/ディレクトリパターン (ワイルドカード可)。指定しない場合、除外以外すべてが対象。名前に区切り文字を含まない場合は名前のみ、含む場合はパスで比較。 |
| `ExcludeBinary`   |            | `switch`  | No   | 指定すると、一般的なバイナリ拡張子を持つファイルを除外します。                                                                         |
| `Verbose`         | `vb`       | `switch`  | No   | スクリプトの実行中に詳細なログメッセージを表示します (CmdletBindingによる共通パラメータ)。                                          |
| `Debug`           | `db`       | `switch`  | No   | デバッグメッセージを表示します (CmdletBindingによる共通パラメータ)。                                                                 |
| `ErrorAction`     | `ea`       | `string`  | No   | エラー発生時のアクションを指定します (CmdletBindingによる共通パラメータ)。                                                           |
| `WarningAction`   | `wa`       | `string`  | No   | 警告発生時のアクションを指定します (CmdletBindingによる共通パラメータ)。                                                             |
| `InformationAction` | `ia`     | `string`  | No   | 情報メッセージ発生時のアクションを指定します (CmdletBindingによる共通パラメータ)。                                                 |
| `ErrorVariable`   | `ev`       | `string`  | No   | エラーを変数に格納します (CmdletBindingによる共通パラメータ)。                                                                     |
| `WarningVariable` | `wv`       | `string`  | No   | 警告を変数に格納します (CmdletBindingによる共通パラメータ)。                                                                     |
| `InformationVariable` | `iv`   | `string`  | No   | 情報メッセージを変数に格納します (CmdletBindingによる共通パラメータ)。                                                             |
| `OutVariable`     | `ov`       | `string`  | No   | 出力結果を変数に格納します (CmdletBindingによる共通パラメータ)。                                                                   |
| `OutBuffer`       | `ob`       | `int`     | No   | 出力をバッファリングする数を指定します (CmdletBindingによる共通パラメータ)。                                                         |
| `PipelineVariable`| `pv`       | `string`  | No   | パイプラインの現在のオブジェクトを変数に格納します (CmdletBindingによる共通パラメータ)。                                           |

## `IgnoreFile` の仕様

`-IgnoreFile` で指定するファイルには、除外したいファイルやディレクトリのパターンを1行に1つずつ記述します。

* **コメント:** `#` で始まる行は無視されます。
* **空行:** 空行は無視されます。
* **パターン:**
    * `*.log`: カレントディレクトリおよびサブディレクトリ内のすべての `.log` ファイルを除外します。
    * `node_modules`: `node_modules` という名前のファイルまたはディレクトリを除外します。
    * `build/`: `build` ディレクトリ (およびその中身) を除外します。パス区切り文字は `/` または `\` を使用できます。
* **ワイルドカード:** `*` (任意の文字列) や `?` (任意の一文字) などの基本的なワイルドカードが利用可能です。
* **.gitignore との非互換性:** `.gitignore` のような複雑なネスト、否定 (`!`)、パスのルート指定 (`/`) などの高度なパターンは**サポートしていません**。シンプルなパターンのみが解釈されます。
* **エンコーディング:** ファイルはシステムのデフォルトエンコーディングで読み込まれます。意図しない動作を避けるため、**UTF-8** で保存することを推奨します。

## 注意点

* **文字コード:** ファイル内容は UTF-8 として読み込まれ、出力Markdownも UTF-8 (BOM無し) で書き込まれます。`IgnoreFile` の読み込みはデフォルトエンコーディングに依存します。
* **巨大ファイル:** 1MB を超えるファイルは、パフォーマンスと出力サイズのため、ファイルパスのみが出力され、内容は省略されます。この閾値は現在変更できません。
* **バイナリファイル判定:** `-ExcludeBinary` スイッチによる判定は、一般的な拡張子のリストに基づいて行われます。完璧な判定ではありません。
* **ツリー表示:** ファイル構造のツリー表示は簡易的なものであり、非常に深い階層や特殊なファイル名の場合、表示が崩れる可能性がゼロではありません。
* **出力ファイルの自動除外:** `-OutputFile` で指定したファイルは、探索と内容出力の対象から常に除外されます。
* **PowerShell 実行ポリシー (Execution Policy):** PowerShellスクリプトの実行には、適切な実行ポリシーが設定されている必要があります。環境によっては、以下のいずれかのコマンドを管理者権限のPowerShellで実行する必要があるかもしれません。
    * `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` (推奨される場合が多い)
    * `Set-ExecutionPolicy Bypass -Scope CurrentUser` (より緩いがセキュリティリスクあり)
    `gpc.bat` は内部で `-ExecutionPolicy RemoteSigned` を試みますが、環境設定によっては不十分な場合があります。

## アンインストール

### 方法1: 手動

1.  配置した `GenerateProjectContext.ps1` と `gpc.bat` ファイルを削除します。
2.  (もし手動で追加した場合) 環境変数 `PATH` から、これらのファイルを配置したディレクトリのパスを削除します。

### 方法2: Makefile

1.  コマンドプロンプトまたはターミナルで、リポジトリのルートディレクトリに移動します。
2.  以下のコマンドを実行します:
    ```bash
    make uninstall
    ```
    これにより、`make setup` で追加されたインストールディレクトリがユーザー環境変数 `PATH` から削除されます。
3.  **重要:** このコマンドは `PATH` 環境変数からパスを削除するだけで、**スクリプトファイル自体は削除しません**。ファイルは手動で削除する必要があります（デフォルト: `%USERPROFILE%\MyPowerShellScripts\GenerateProjectContext`）。
4.  `PATH` の変更を反映させるためにターミナルを再起動してください。

## 貢献

バグ報告や改善提案は、Issueを通じてお願いします (もしGitHubリポジトリなどがあれば)。