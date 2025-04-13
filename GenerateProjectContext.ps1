<#
.SYNOPSIS
指定されたディレクトリ構造とファイル内容をMarkdown形式で出力します。LLMへのコンテキスト提供などに利用できます。

.DESCRIPTION
このスクリプトは、指定されたディレクトリを再帰的に探索し、
ファイル構造とテキストベースのファイルの内容を一つのMarkdownファイルにまとめます。
特定のファイルやディレクトリを除外したり、特定のファイルのみを含めたり、
バイナリファイルを除外したりするオプションがあります。

.PARAMETER Path
(必須) 情報を収集するルートディレクトリのパス。

.PARAMETER OutputFile
(必須) 結果を出力するMarkdownファイルへのパス。

.PARAMETER Exclude
除外するファイルまたはディレクトリのパターン（ワイルドカード使用可）。複数指定可能。
例: "node_modules", "*.log", "dist/"

.PARAMETER IgnoreFile
除外/包含パターンを1行ずつ記述したファイルのパス。シンプルなワイルドカードパターンを想定。
例: .gitignore と似た目的で使用できますが、完全な互換性はありません。

.PARAMETER IncludeOnly
このパターンに一致するファイルまたはディレクトリのみを対象とします（ワイルドカード使用可）。
複数指定可能。指定しない場合は、除外パターンに一致しないすべてのファイルが対象になります。

.PARAMETER ExcludeBinary
このスイッチを指定すると、一般的なバイナリファイルの拡張子を持つファイルを除外します。

.EXAMPLE
.\GenerateProjectContext.ps1 -Path "C:\MyProject" -OutputFile "C:\MyProject\context.md"

.EXAMPLE
.\GenerateProjectContext.ps1 -Path . -OutputFile context.md -Exclude "node_modules", "dist", "*.tmp" -ExcludeBinary

.EXAMPLE
.\GenerateProjectContext.ps1 -Path .\src -OutputFile src_context.md -IncludeOnly "*.js", "*.css" -IgnoreFile .llmignore

.NOTES
Author: Forest-Project-Lab
Date: 2025-04-13
文字コードは UTF-8 (BOM 無し) としてファイルを読み書きします。
巨大なファイル(デフォルト1MB超)はパフォーマンスと出力サイズのため内容は省略されます。
ファイル構造のツリー表示は簡易的なものです。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="情報収集のルートディレクトリパス")]
    [string]$Path,

    [Parameter(Mandatory=$true, HelpMessage="出力Markdownファイルパス")]
    [string]$OutputFile,

    [Parameter(HelpMessage="除外するファイル/ディレクトリパターン (ワイルドカード可)")]
    [string[]]$Exclude,

    [Parameter(HelpMessage="除外/包含パターンファイルパス")]
    [string]$IgnoreFile,

    [Parameter(HelpMessage="含めるファイル/ディレクトリパターン (ワイルドカード可)")]
    [string[]]$IncludeOnly,

    [Parameter(HelpMessage="一般的なバイナリファイルの拡張子を除外")]
    [switch]$ExcludeBinary
)

Write-Verbose "スクリプトを開始します。Path: '$Path', OutputFile: '$OutputFile'"

# -- 1. 入力パスの確認 --
try {
    $absolutePath = (Resolve-Path -Path $Path -ErrorAction Stop).Path
    if (-not (Test-Path -Path $absolutePath -PathType Container)) {
        Write-Error "'$Path' は有効なディレクトリではありません。"
        exit 1
    }
    Write-Verbose "ルートパスの絶対パス: '$absolutePath'"
}
catch {
    Write-Error "指定されたパス '$Path' の解決中にエラーが発生しました: $($_.Exception.Message)"
    exit 1
}

# -- 2. 出力先ディレクトリの確認 --
$outputDir = Split-Path -Path $OutputFile -Parent
if (-not (Test-Path -Path $outputDir -PathType Container)) {
    Write-Verbose "出力ディレクトリ '$outputDir' が存在しないため作成します。"
    try {
        New-Item -Path $outputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "出力ディレクトリ '$outputDir' の作成に失敗しました: $($_.Exception.Message)"
        exit 1
    }
}

# -- 3. 除外/包含パターンの準備 --
$defaultExcludes = @(
    ".git", ".svn", ".hg", ".vscode", ".idea", "node_modules"
)
Write-Verbose "デフォルト除外リスト: $($defaultExcludes -join ', ')"

$cliExcludes = @()
if ($PSBoundParameters.ContainsKey('Exclude')) {
    $cliExcludes = $Exclude
    Write-Verbose "-Exclude パラメータからの除外: $($cliExcludes -join ', ')"
}

$ignoreFilePatterns = @()
if ($PSBoundParameters.ContainsKey('IgnoreFile') -and (Test-Path -Path $IgnoreFile -PathType Leaf)) {
    Write-Verbose "-IgnoreFile '$IgnoreFile' を読み込みます。"
    try {
        # 環境に応じて Encoding を変更（UTF8/Defaultなど）
        $ignoreFileContent = Get-Content -Path $IgnoreFile -Encoding Default -Raw -ErrorAction Stop
        $ignoreFilePatterns = $ignoreFileContent -split '[\r\n]+' |
            Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }
        Write-Verbose "Ignoreファイルからのパターン: $($ignoreFilePatterns -join ', ')"
    }
    catch {
        Write-Warning "Ignoreファイル '$IgnoreFile' の読み込みに失敗しました: $($_.Exception.Message)"
    }
}
elseif ($PSBoundParameters.ContainsKey('IgnoreFile')) {
    Write-Warning "指定された Ignoreファイル '$IgnoreFile' が見つかりません。"
}

$includeOnlyPatterns = @()
if ($PSBoundParameters.ContainsKey('IncludeOnly')) {
    $includeOnlyPatterns = $IncludeOnly
    Write-Verbose "-IncludeOnly パターン: $($includeOnlyPatterns -join ', ')"
}

# 一般的なバイナリ拡張子
$binaryExtensions = @(
    ".exe", ".dll", ".so", ".dylib", ".bin", ".dat", ".obj", ".lib", ".a",
    ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tiff", ".ico", ".webp",
    ".mp3", ".wav", ".ogg", ".flac", ".aac", ".m4a",
    ".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv",
    ".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".odt",
    ".iso", ".img",
    ".sqlite", ".db", ".mdb",
    ".jar", ".war", ".ear",
    ".pyc", ".pyo",
    ".class"
)
if ($ExcludeBinary) {
    Write-Verbose "バイナリファイルの拡張子を除外します。"
}

# -- 4. ファイル探索とフィルタリング --
Write-Verbose "ファイル探索を開始します..."
$allFilePaths = @()
$allDirectoryPaths = @()

try {
    $items = Get-ChildItem -Path $absolutePath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +gciErrors
    if ($gciErrors) {
        foreach ($err in $gciErrors) {
            Write-Warning "ファイルアクセスエラー: $($err.TargetObject) - $($err.Exception.Message)"
        }
    }

    Write-Verbose "フィルタリング処理を開始します。対象アイテム数: $($items.Count)"

    foreach ($item in $items) {
        $currentItemPath = $item.FullName
        if ($currentItemPath -eq $absolutePath) {
            continue # ルート自身は除外
        }

        # ここが変更点: substring + パス先頭の \ 削除 + .\ を付ける
        # -----------------------------------------------------------------
        if ($currentItemPath.StartsWith($absolutePath)) {
            $relativePath = $currentItemPath.Substring($absolutePath.Length)
        } else {
            $relativePath = $currentItemPath
        }
        # remove leading \ or / if any
        $relativePath = $relativePath -replace '^[\\/]+',''

        if ($relativePath) {
            # prepend .\ 
            $relativePath = '.\' + $relativePath
        } else {
            # root case
            $relativePath = '.'
        }
        # -----------------------------------------------------------------

        $isContainer = $item.PSIsContainer
        $isExcluded = $false

        # (a) デフォルト除外
        foreach ($defaultExclude in $defaultExcludes) {
            # パス全体か名前が該当するかチェック
            if (
                $currentItemPath.Contains("\$defaultExclude\") -or
                $currentItemPath.EndsWith("\$defaultExclude") -or
                $item.Name -eq $defaultExclude
            ) {
                Write-Verbose "デフォルト除外: '$relativePath'"
                $isExcluded = $true
                break
            }
        }
        if ($isExcluded) { continue }

        # (b) -Exclude パターン
        if ($PSBoundParameters.ContainsKey('Exclude')) {
            foreach ($excludePattern in $Exclude) {
                if ($excludePattern -notmatch '[\\/]') {
                    # ファイル名だけ比較
                    if ($item.Name -like $excludePattern) {
                        Write-Verbose "-Exclude 名前一致: '$relativePath'"
                        $isExcluded = $true
                        break
                    }
                }
                else {
                    # パス比較
                    $normalizedRelativePath = $relativePath -replace '\\', '/'
                    $normalizedExcludePattern = $excludePattern -replace '\\', '/'
                    if ($normalizedRelativePath -like $normalizedExcludePattern) {
                        Write-Verbose "-Exclude パス一致: '$relativePath'"
                        $isExcluded = $true
                        break
                    }
                }
            }
        }
        if ($isExcluded) { continue }

        # (c) IgnoreFile パターン
        if ($ignoreFilePatterns.Count -gt 0) {
            foreach ($ignorePattern in $ignoreFilePatterns) {
                if ($ignorePattern -notmatch '[\\/]' ) {
                    if ($item.Name -like $ignorePattern) {
                        Write-Verbose "IgnoreFile 名前一致: '$relativePath'"
                        $isExcluded = $true
                        break
                    }
                }
                else {
                    $normalizedRelativePath = $relativePath -replace '\\', '/'
                    $normalizedIgnorePattern = $ignorePattern -replace '\\', '/'
                    if ($normalizedRelativePath -like $normalizedIgnorePattern) {
                        Write-Verbose "IgnoreFile パス一致: '$relativePath'"
                        $isExcluded = $true
                        break
                    }
                }
            }
        }
        if ($isExcluded) { continue }

        # (d) -IncludeOnly パターン
        if ($PSBoundParameters.ContainsKey('IncludeOnly')) {
            $isIncluded = $false
            foreach ($includePattern in $includeOnlyPatterns) {
                if ($includePattern -notmatch '[\\/]') {
                    if ($item.Name -like $includePattern) {
                        $isIncluded = $true
                        break
                    }
                }
                else {
                    $normalizedRelativePath = $relativePath -replace '\\', '/'
                    $normalizedIncludePattern = $includePattern -replace '\\', '/'
                    if ($normalizedRelativePath -like $normalizedIncludePattern) {
                        $isIncluded = $true
                        break
                    }
                }
            }
            if (-not $isIncluded) {
                Write-Verbose "-IncludeOnly 対象外: '$relativePath'"
                continue
            }
        }

        # (e) バイナリ除外チェック (ファイルのみ対象)
        if (-not $isContainer -and $ExcludeBinary) {
            $extension = $item.Extension.ToLower()
            if ($binaryExtensions -contains $extension) {
                Write-Verbose "バイナリ除外: '$relativePath' (拡張子: $extension)"
                continue
            }
        }

        # 振り分け
        if ($isContainer) {
            $allDirectoryPaths += $currentItemPath
        }
        else {
            $allFilePaths += $currentItemPath
        }
    }

    $allDirectoryPaths = $allDirectoryPaths | Sort-Object
    $allFilePaths = $allFilePaths | Sort-Object

    Write-Verbose "フィルタリング後のディレクトリ数: $($allDirectoryPaths.Count)"
    Write-Verbose "フィルタリング後のファイル数: $($allFilePaths.Count)"
}
catch {
    Write-Error "ファイル探索またはフィルタリング中に予期せぬエラーが発生しました: $($_.Exception.Message)"
    exit 1
}

# -- 5. Markdown生成 --
Write-Verbose "Markdown生成を開始します..."
$markdownContent = @()

# ヘッダ
$markdownContent += "# Project Context: '$($absolutePath)'"
$markdownContent += ""
$markdownContent += "Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$markdownContent += "Generated by: GenerateProjectContext.ps1"
$markdownContent += ""

# ファイル構造セクション
$markdownContent += "## File Structure"
$markdownContent += ""
$markdownContent += '```'
$markdownContent += '.'

# ディレクトリとファイルを合わせてソートし、1 つずつ階層表示
$allItemsForStructure = $allDirectoryPaths + $allFilePaths | Sort-Object
$structureLookup = @{}

foreach ($itemPath in $allItemsForStructure) {

    # 先ほどと同じロジックで relativePath を生成
    $tmpPath = ''
    if ($itemPath.StartsWith($absolutePath)) {
        $tmpPath = $itemPath.Substring($absolutePath.Length)
    } else {
        $tmpPath = $itemPath
    }
    $tmpPath = $tmpPath -replace '^[\\/]+',''
    if ($tmpPath) {
        $tmpPath = '.\' + $tmpPath
    } else {
        $tmpPath = '.'
    }

    # 分割
    $parts = $tmpPath -split '[\\/]' | Where-Object { $_ }
    $currentIndent = ""
    $currentPathKeyPrefix = ""

    for ($i = 0; $i -lt $parts.Length; $i++) {
        $part = $parts[$i]
        # 重複防止用キー作成
        $currentPathKey = "$($currentPathKeyPrefix)\$($part)"

        if (-not $structureLookup.ContainsKey($currentPathKey)) {
            $prefix = "|-- "
            $line = "$currentIndent$prefix$part"
            $markdownContent += $line
            $structureLookup[$currentPathKey] = $true
        }
        $currentIndent += "  "
        $currentPathKeyPrefix = $currentPathKey
    }
}

$markdownContent += '```'
$markdownContent += ""

# ファイル内容セクション
$markdownContent += "## File Contents"
$markdownContent += ""

$fileCounter = 0
$totalFiles = $allFilePaths.Count

foreach ($filePath in $allFilePaths) {
    $fileCounter++
    # 再度、relativePath を作る
    $tmpRel = ''
    if ($filePath.StartsWith($absolutePath)) {
        $tmpRel = $filePath.Substring($absolutePath.Length)
    } else {
        $tmpRel = $filePath
    }
    $tmpRel = $tmpRel -replace '^[\\/]+',''
    if ($tmpRel) {
        $tmpRel = '.\' + $tmpRel
    } else {
        $tmpRel = '.'
    }

    Write-Verbose "($fileCounter/$totalFiles) 処理中: '$tmpRel'"

    # ### `.\xxx\yyy`
    $markdownContent += '### `' + $tmpRel + '`'
    $markdownContent += ""

    # 拡張子で言語判定
    $extension = [System.IO.Path]::GetExtension($filePath).ToLower().TrimStart('.')
    $lang = switch ($extension) {
        'ps1'       { 'powershell' }
        'py'        { 'python' }
        'js'        { 'javascript' }
        'ts'        { 'typescript' }
        'cs'        { 'csharp' }
        'java'      { 'java' }
        'rb'        { 'ruby' }
        'go'        { 'go' }
        'php'       { 'php' }
        'html'      { 'html' }
        'css'       { 'css' }
        'scss'      { 'scss' }
        'less'      { 'less' }
        'json'      { 'json' }
        'xml'       { 'xml' }
        'yaml'      { 'yaml' }
        'yml'       { 'yaml' }
        'md'        { 'markdown' }
        'sh'        { 'shell' }
        'bat'       { 'batch' }
        'sql'       { 'sql' }
        'dockerfile'{ 'dockerfile' }
        'makefile'  { 'makefile' }
        default     { '' }
    }

    # コードブロック開始
    if ([string]::IsNullOrEmpty($lang)) {
        # 言語名が無ければ単に ```
        $markdownContent += '```'
    }
    else {
        # パーサ混乱防止のため、連結で書く
        $markdownContent += '```' + $lang
    }

    try {
        $fileInfo = Get-Item -Path $filePath -ErrorAction Stop
        $maxFileSizeMB = 1
        if ($fileInfo.Length -gt ($maxFileSizeMB * 1024 * 1024)) {
            $markdownContent += "// File content omitted because it exceeds $($maxFileSizeMB)MB"
            Write-Warning "ファイル '$tmpRel' は $($maxFileSizeMB)MB を超えるため内容は省略されました。"
        }
        else {
            $fileContent = Get-Content -Path $filePath -Raw -Encoding UTF8 -ErrorAction Stop
            if ($null -ne $fileContent) {
                $markdownContent += $fileContent
            }
            else {
                $markdownContent += "// Empty file"
            }
        }
    }
    catch {
        $markdownContent += "// Error reading file: $($_.Exception.Message)"
        Write-Warning "ファイル '$tmpRel' の読み込み中にエラーが発生しました: $($_.Exception.Message)"
    }

    # コードブロック終了
    $markdownContent += '```'
    $markdownContent += ""
}

# -- 6. Markdownファイル書き込み --
Write-Verbose "Markdown ファイル '$OutputFile' に書き込みます..."
try {
    # UTF-8 (BOM 無し) 指定
    [System.IO.File]::WriteAllLines($OutputFile, $markdownContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "処理が完了しました。出力ファイル: '$OutputFile'"
}
catch {
    Write-Error "ファイル '$OutputFile' への書き込み中にエラー: $($_.Exception.Message)"
    exit 1
}

Write-Verbose "スクリプトを終了します。"
exit 0
# End of script
# --- EOF ---
