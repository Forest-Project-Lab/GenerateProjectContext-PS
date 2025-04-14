# GenerateProjectContext

指定されたディレクトリ構造とファイル内容をMarkdown形式で出力するPowerShellスクリプトです。主に大規模言語モデル (LLM) へのコンテキスト提供を目的としています。

## 機能

* 指定ディレクトリ以下のファイル構造をツリー形式で表示
* テキストベースのファイルの内容をMarkdownコードブロックとして出力
* 拡張子に応じたシンタックスハイライト指定 (可能な場合)
* 特定のファイル/ディレクトリを除外 (`-Exclude`, `-IgnoreFile`)
* 特定のファイル/ディレクトリのみを包含 (`-IncludeOnly`)
* 一般的なバイナリファイルの拡張子を持つファイルを除外 (`-ExcludeBinary`)
* 巨大なファイル (デフォルト1MB超) の内容を省略
* 生成される出力ファイル自体を処理対象から自動的に除外
* UTF-8 (BOM無し) でMarkdownファイルを出力

## インストール

### 方法1: Makefile (Windows環境で `make` が利用可能な場合)

この方法は、`make` コマンドが利用できる環境でのセットアップを簡略化します。

1.  リポジトリ全体をクローンまたはダウンロードします。
2.  コマンドプロンプトまたはターミナルで、リポジトリのルートディレクトリに移動します。
3.  `make` コマンドがインストールされていることを確認します。
    * インストールされていない場合は、[GNU Make for Windows](http://gnuwin32.sourceforge.net/packages/make.htm) をダウンロードするか、パッケージマネージャー（例: [Chocolatey](https://chocolatey.org/install) で `choco install make` を実行）を利用してインストールしてください。
4.  **管理者権限で** PowerShell またはコマンドプロンプトを開き、以下のコマンドを実行します:
    ```bash
    make setup
    ```
    * **[注記]** `make setup` はデフォルトで `%USERPROFILE%\MyPowerShellScripts\GenerateProjectContext` ディレクトリを作成し、スクリプトをコピーし、そのディレクトリを**ユーザー**環境変数 `PATH` に追加します。ユーザー環境変数の変更自体には通常管理者権限は不要ですが、PowerShellスクリプトの実行に必要な実行ポリシー (`Execution Policy`) の設定変更が必要になる場合があるため、管理者権限での実行を推奨します（詳細は「注意点」の実行ポリシーの項目を参照）。
5.  **重要:** 環境変数 `PATH` の変更を有効にするには、コマンドプロンプトやターミナルを**再起動**する必要があります。場合によってはシステムの再起動が必要なこともあります。

### 方法2: 手動インストール

1.  リポジトリから `GenerateProjectContext.ps1` と `gpc.bat` をダウンロードし、任意のディレクトリ（例: `C:\MyScripts`）に配置します。
2.  そのディレクトリをシステムの環境変数 `PATH` に手動で追加します。
3.  **重要:** 環境変数 `PATH` の変更を有効にするには、コマンドプロンプトやターミナルを**再起動**する必要があります。
4.  PowerShellスクリプトの実行ポリシーを確認し、必要であれば変更します（詳細は「注意点」の実行ポリシーの項目を参照）。

## 使い方

スクリプトは直接 `GenerateProjectContext.ps1` を実行するか、便利なラッパー `gpc.bat` を使って実行できます (`PATH` が通っている場合)。`gpc.bat` は、特に日本語環境などでの文字コードの問題を回避するための設定を含んでいます。

### 基本コマンド

```powershell
# PowerShell スクリプトを直接実行 (配置したディレクトリで)
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

# 詳細なログを表示しながら実行 (-Verbose スイッチを追加)
gpc -Path . -OutputFile context_verbose.md -Verbose
```

## パラメータ

| パラメータ            | エイリアス | 型         | 必須 | 説明                                                                                                                       |
| :-------------------- | :--------- | :--------- | :--- | :------------------------------------------------------------------------------------------------------------------------- |
| `Path`                |            | `string`   | Yes  | 情報を収集するルートディレクトリのパス。                                                                                       |
| `OutputFile`          |            | `string`   | Yes  | 結果を出力するMarkdownファイルへのパス。このファイル自体は処理から自動的に除外されます。                                           |
| `Exclude`             |            | `string[]` | No   | 除外するファイル/ディレクトリパターン (ワイルドカード可)。複数指定可能。名前に区切り文字を含まない場合は名前のみ、含む場合はパスで比較。 |
| `IgnoreFile`          |            | `string`   | No   | 除外パターンを1行に1つずつ記述したファイルのパス。シンプルなワイルドカードのみサポート。詳細は後述。                                |
| `IncludeOnly`         |            | `string[]` | No   | **含める**ファイル/ディレクトリパターン (ワイルドカード可)。指定した場合、これらに一致しないものは除外される。指定しない場合は、除外以外すべてが対象。 |
| `ExcludeBinary`       |            | `switch`   | No   | 指定すると、一般的な拡張子に基づいてバイナリファイルを除外します。                                                              |
| `Verbose`             | `vb`       | `switch`   | No   | スクリプトの実行中に詳細なログメッセージを表示します (CmdletBinding共通パラメータ)。                                             |
| `Debug`               | `db`       | `switch`   | No   | デバッグメッセージを表示します (CmdletBinding共通パラメータ)。                                                               |
| `ErrorAction`         | `ea`       | `string`   | No   | エラー発生時のアクションを指定します (CmdletBinding共通パラメータ)。例: `Stop`, `Continue`, `SilentlyContinue`。               |
| `WarningAction`       | `wa`       | `string`   | No   | 警告発生時のアクションを指定します (CmdletBinding共通パラメータ)。                                                             |
| `InformationAction`   | `ia`       | `string`   | No   | 情報メッセージ発生時のアクションを指定します (CmdletBinding共通パラメータ)。                                                     |
| `ErrorVariable`       | `ev`       | `string`   | No   | エラーを変数に格納します (CmdletBinding共通パラメータ)。 '+'を先頭につけると追記。                                               |
| `WarningVariable`     | `wv`       | `string`   | No   | 警告を変数に格納します (CmdletBinding共通パラメータ)。 '+'を先頭につけると追記。                                               |
| `InformationVariable` | `iv`       | `string`   | No   | 情報メッセージを変数に格納します (CmdletBinding共通パラメータ)。 '+'を先頭につけると追記。                                         |
| `OutVariable`         | `ov`       | `string`   | No   | 出力結果を変数に格納します (CmdletBinding共通パラメータ)。 '+'を先頭につけると追記。                                            |
| `OutBuffer`           | `ob`       | `int`      | No   | 出力をバッファリングする数を指定します (CmdletBinding共通パラメータ)。                                                          |
| `PipelineVariable`    | `pv`       | `string`   | No   | パイプラインの現在のオブジェクトを変数に格納します (CmdletBinding共通パラメータ)。                                               |

## `IgnoreFile` の仕様

`-IgnoreFile` で指定するファイルには、除外したいファイルやディレクトリのパターンを1行に1つずつ記述します。

* **コメント:** `#` で始まる行は無視されます。
* **空行:** 空行は無視されます。
* **パターン:**
    * `*.log`: カレントディレクトリおよびサブディレクトリ内のすべての `.log` ファイルを除外します。
    * `node_modules`: `node_modules` という名前のファイルまたはディレクトリを除外します。
    * `build/`: `build` ディレクトリ (およびその中身) を除外します。パス区切り文字は `/` または `\` を使用できます。
* **ワイルドカード:** `*` (任意の文字列) や `?` (任意の一文字) などの基本的なワイルドカードが利用可能です (PowerShellの `-like` 演算子に準拠)。
* **.gitignore との非互換性:** `.gitignore` のような複雑なネスト、否定 (`!`)、パスのルート指定 (`/`) などの高度なパターンは**サポートしていません**。シンプルなパターンのみが解釈されます。
* **エンコーディング:** ファイルはシステムのデフォルトエンコーディング (`Get-Content -Encoding Default`) で読み込まれます。意図しない動作を避けるため、**UTF-8 (BOM無し)** で保存することを強く推奨します。

## 注意点

* **文字コード:**
    * ファイル内容は UTF-8 として読み込もうと試みます。非UTF-8ファイルやバイナリファイルは内容が省略されるか、エラーメッセージが表示されることがあります。
    * 出力されるMarkdownファイルは常に UTF-8 (BOM無し) で書き込まれます。
    * `IgnoreFile` はシステムのデフォルトエンコーディングで読み込まれるため、UTF-8での保存を推奨します。
* **巨大ファイル:** 1MB を超えるファイルは、パフォーマンスと出力サイズのため、ファイルパスのみが出力され、内容は省略されます。この閾値は現在スクリプト内で固定されています。
* **バイナリファイル判定:** `-ExcludeBinary` スイッチによる判定は、スクリプト内に定義された一般的な拡張子のリストに基づいて行われます。完璧な判定ではなく、リストに含まれない拡張子のバイナリファイルは除外されません。
* **ツリー表示:** ファイル構造のツリー表示は簡易的なものです。非常に深い階層や特殊なファイル名（改行を含むなど）の場合、表示が完全でない可能性があります。
* **出力ファイルの自動除外:** `-OutputFile` で指定したファイルは、探索と内容出力の対象から常に除外されます。
* **PowerShell 実行ポリシー (Execution Policy):**
    * PowerShellスクリプトの実行には、適切な実行ポリシーが設定されている必要があります。デフォルトでは制限されている場合があります。
    * 環境によっては、以下のいずれかのコマンドを**管理者権限のPowerShell**で実行し、実行ポリシーを変更する必要があるかもしれません。
        * `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` (ローカルスクリプトと署名付きリモートスクリプトを許可。推奨される場合が多い)
        * `Set-ExecutionPolicy Unrestricted -Scope CurrentUser` (全てのスクリプトを許可。セキュリティリスクを理解した上で使用)
        * `Set-ExecutionPolicy Bypass -Scope CurrentUser` (何もブロックせず、警告も表示しない。セキュリティリスク高)
    * 現在の設定は `Get-ExecutionPolicy -List` で確認できます。
    * `gpc.bat` ラッパースクリプトは、内部で `-ExecutionPolicy RemoteSigned` を指定して PowerShell を起動しようと試みますが、システムのポリシー設定によってはこれが無視される場合があります。

## アンインストール

### 方法1: 手動

1.  インストール時に配置した `GenerateProjectContext.ps1` と `gpc.bat` ファイルを削除します (例: `%USERPROFILE%\MyPowerShellScripts\GenerateProjectContext` ディレクトリごと削除)。
2.  環境変数 `PATH` に手動で追加した場合は、そのパスを環境変数から削除します。

### 方法2: Makefile を使用した場合

1.  コマンドプロンプトまたはターミナルで、**リポジトリのルートディレクトリ**（Makefileがある場所）に移動します。
2.  以下のコマンドを実行します:
    ```bash
    make uninstall
    ```
    これにより、`make setup` で追加されたインストールディレクトリのパスがユーザー環境変数 `PATH` から削除されます。
3.  **重要:** このコマンドは `PATH` 環境変数からパスを削除するだけで、**スクリプトファイル自体は削除しません**。ファイルが不要な場合は、手動で削除してください（デフォルトのインストール先: `%USERPROFILE%\MyPowerShellScripts\GenerateProjectContext`）。
4.  環境変数 `PATH` の変更を反映させるために、ターミナルやシステムを再起動してください。

## 貢献

バグ報告や改善提案は、Issueを通じてお願いします。