<#
.SYNOPSIS
指定されたディレクトリ構造とファイル内容をMarkdown形式で出力します。LLMへのコンテキスト提供などに利用できます。

.DESCRIPTION
このスクリプトは、指定されたディレクトリを再帰的に探索し、
ファイル構造とテキストベースのファイルの内容を一つのMarkdownファイルにまとめます。
特定のファイルやディレクトリを除外したり、特定のファイルのみを含めたり、
巨大ファイルやバイナリファイルを省略したりするオプションがあります。

- ファイルが 1MB 超の場合は「// File content omitted because it exceeds 1MB」を表示。
- ファイルが 1MB 以下の場合は先頭4KBをバイナリ読み込み・UTF8デコードして制御文字の割合をチェック。
  - デコード不可 or 制御文字が 10%以上なら「// Omitted content for non-text file: ...」と省略。
  - 問題なければ全文テキスト出力。

PARAMETER Path
(必須) 情報を収集するルートディレクトリのパス。

.PARAMETER OutputFile
(必須) 結果を出力するMarkdownファイルへのパス。

.PARAMETER Exclude
除外するファイルまたはディレクトリのパターン（ワイルドカード可）。複数指定可能。
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
巨大なファイル(デフォルト1MB超)は内容を省略します。
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
    # Resolve-Path で絶対パスを取得
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
    $absolutePath = $resolvedPath.Path

    if (-not (Test-Path -Path $absolutePath -PathType Container)) {
        Write-Error "'$Path' は有効なディレクトリではありません。"
        exit 1
    }

    # 末尾の \ / を除去してから統一的に追加
    $absolutePath = $absolutePath.TrimEnd('\','/')
    if (-not $absolutePath.EndsWith('\')) {
        $absolutePath += '\'
    }

    # 比較用に小文字化した文字列を用意
    $absolutePathLower = $absolutePath.ToLower()

    Write-Verbose "ルートパスの絶対パス(整形後): '$absolutePath'"
    Write-Verbose "ルートパス(小文字化) : '$absolutePathLower'"

}
catch {
    Write-Error "指定されたパス '$Path' の解決中にエラーが発生しました: $($_.Exception.Message)"
    exit 1
}

# -- 2. 出力先ディレクトリの確認 --
$outputDir = Split-Path -Path $OutputFile -Parent
if ([string]::IsNullOrEmpty($outputDir)) {
    $outputDir = '.'  # カレントディレクトリ扱い
}
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

# -- 2.1 出力ファイルの絶対パスを取得（除外判定に利用） --
try {
    # ディレクトリまでのパスはすでに存在が確認できているので、手動で絶対パスを組み立てる
    $absoluteOutputFile = Join-Path (Resolve-Path $outputDir) (Split-Path $OutputFile -Leaf)
    Write-Verbose "出力ファイルの絶対パス: '$absoluteOutputFile'"
}
catch {
    Write-Error "OutputFile '$OutputFile' の解決中にエラーが発生しました: $($_.Exception.Message)"
    exit 1
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

# -- 4. バイナリ除外用の拡張子定義 (必要な場合) --
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

# -- 5. ファイル探索とフィルタリング --
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
        # フルパス
        $currentItemPath = $item.FullName

        # 出力ファイル自身は除外
        if ($currentItemPath -eq $absoluteOutputFile) {
            Write-Verbose "出力ファイル自身を除外: '$currentItemPath'"
            continue
        }

        # ルート自身も除外
        # (子孫を探した結果ルートに戻ることは通常ないが一応チェック)
        if ($currentItemPath -eq $absolutePath) {
            continue
        }

        # 大小文字揃えたパスを作る
        $currentItemPathLower = $currentItemPath.ToLower()

        # (a) デフォルト除外
        $isExcluded = $false
        foreach ($defaultExclude in $defaultExcludes) {
            # フォルダ名 or ファイル名単体での比較
            if ($item.Name -eq $defaultExclude) {
                Write-Verbose "デフォルト除外: '$currentItemPath'"
                $isExcluded = $true
                break
            }
            # 絶対パスに含む場合 (node_modulesなど)
            if ($currentItemPathLower -like "*\$($defaultExclude.ToLower())\*") {
                Write-Verbose "デフォルト除外(パス内): '$currentItemPath'"
                $isExcluded = $true
                break
            }
        }
        if ($isExcluded) { continue }

        # (b) -Exclude パターン
        if ($PSBoundParameters.ContainsKey('Exclude')) {
            foreach ($excludePattern in $Exclude) {
                # パターンが区切り文字を含まない => ファイル名だけ比較
                if ($excludePattern -notmatch '[\\/]' ) {
                    if ($item.Name -like $excludePattern) {
                        Write-Verbose "-Exclude 名前一致: '$currentItemPath'"
                        $isExcluded = $true
                        break
                    }
                }
                else {
                    # パス比較
                    # 小文字にして -like 比較
                    $patternLower = $excludePattern.ToLower() -replace '\\','/'
                    $normalizedPathLower = $currentItemPathLower -replace '\\','/'
                    if ($normalizedPathLower -like $patternLower) {
                        Write-Verbose "-Exclude パス一致: '$currentItemPath'"
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
                        Write-Verbose "IgnoreFile 名前一致: '$currentItemPath'"
                        $isExcluded = $true
                        break
                    }
                }
                else {
                    $ignorePatLower = $ignorePattern.ToLower() -replace '\\','/'
                    $normalizedPathLower = $currentItemPathLower -replace '\\','/'
                    if ($normalizedPathLower -like $ignorePatLower) {
                        Write-Verbose "IgnoreFile パス一致: '$currentItemPath'"
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
                if ($includePattern -notmatch '[\\/]' ) {
                    # 名前だけ
                    if ($item.Name -like $includePattern) {
                        $isIncluded = $true
                        break
                    }
                }
                else {
                    $incPatLower = $includePattern.ToLower() -replace '\\','/'
                    $normalizedPathLower = $currentItemPathLower -replace '\\','/'
                    if ($normalizedPathLower -like $incPatLower) {
                        $isIncluded = $true
                        break
                    }
                }
            }
            if (-not $isIncluded) {
                Write-Verbose "-IncludeOnly 対象外: '$currentItemPath'"
                continue
            }
        }

        # (e) -ExcludeBinary (ファイルのみ対象)
        if (-not $item.PSIsContainer -and $ExcludeBinary) {
            $ext = $item.Extension.ToLower()
            if ($binaryExtensions -contains $ext) {
                Write-Verbose "バイナリ拡張子除外: '$currentItemPath'"
                continue
            }
        }

        # 振り分け
        if ($item.PSIsContainer) {
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

# -- 6. Markdown生成 --
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

# ディレクトリとファイルをまとめてソートし、階層表示
$allItemsForStructure = $allDirectoryPaths + $allFilePaths | Sort-Object
$structureLookup = @{}

foreach ($itemPath in $allItemsForStructure) {

    # パスを小文字化してルートと比較
    $itemPathLower = $itemPath.ToLower()
    if ($itemPathLower.StartsWith($absolutePathLower)) {
        # Substring で差分だけ抜く
        $rel = $itemPath.Substring($absolutePath.Length)
    }
    else {
        # 何らかの理由でStartsWith失敗(ドライブ異なる等)
        $rel = $itemPath
    }

    # 先頭の \ / を除去
    $rel = $rel -replace '^[\\/]+',''
    if ($rel) {
        $rel = '.\' + $rel
    }
    else {
        $rel = '.'
    }

    # ツリー表示用
    $parts = $rel -split '[\\/]' | Where-Object { $_ }
    $currentIndent = ""
    $currentPathKeyPrefix = ""

    for ($i = 0; $i -lt $parts.Length; $i++) {
        $part = $parts[$i]
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

    # 相対パス生成(小文字比較)
    $filePathLower = $filePath.ToLower()
    if ($filePathLower.StartsWith($absolutePathLower)) {
        $tmpRel = $filePath.Substring($absolutePath.Length)
    }
    else {
        $tmpRel = $filePath
    }
    $tmpRel = $tmpRel -replace '^[\\/]+',''
    if ($tmpRel) {
        $tmpRel = '.\' + $tmpRel
    } else {
        $tmpRel = '.'
    }

    Write-Verbose "($fileCounter/$totalFiles) 処理中: '$tmpRel'"

    # 見出し
    $markdownContent += "### ``$tmpRel``"
    $markdownContent += ""

    # 拡張子でコードブロックの言語判定
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
        $markdownContent += '```'
    }
    else {
        $markdownContent += '```' + $lang
    }

    # ファイル内容を取得
    try {
        $fileInfo = Get-Item -Path $filePath -ErrorAction Stop
        $maxFileSizeMB = 1
        if ($fileInfo.Length -gt ($maxFileSizeMB * 1024 * 1024)) {
            # 1MB 超の場合
            $markdownContent += "// File content omitted because it exceeds $($maxFileSizeMB)MB"
            Write-Warning "ファイル '$tmpRel' は $($maxFileSizeMB)MB を超えるため内容は省略されました。"
        }
        else {
            # 1MB以下 => 先頭4KBを読んでテキスト判定
            $sampleSize = 4096
            [byte[]]$buffer = New-Object byte[] $sampleSize

            $fs = [System.IO.File]::Open($filePath, 'Open', 'Read')
            try {
                $bytesRead = $fs.Read($buffer, 0, $sampleSize)
            }
            finally {
                $fs.Close()
            }

            if ($bytesRead -gt 0) {
                try {
                    # UTF-8デコードを試みる
                    $decodedSample = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                    # 制御文字チェック
                    $controlCount = 0
                    $chars = $decodedSample.ToCharArray()
                    foreach ($ch in $chars) {
                        $code = [int][char]$ch
                        # CR(13)/LF(10)/TAB(9) を除く0-31と127を制御文字とみなす
                        if (
                            ($code -lt 32 -and $code -notin 9,10,13) -or
                            ($code -eq 127)
                        ) {
                            $controlCount++
                        }
                    }
                    $totalLen = $chars.Length
                    if ($totalLen -gt 0) {
                        $controlRatio = $controlCount / $totalLen
                        if ($controlRatio -ge 0.1) {
                            # 10%以上制御文字 => 非テキスト扱い
                            $markdownContent += "// Omitted content for non-text file: control characters ratio $($controlRatio.ToString('P1'))"
                        }
                        else {
                            # テキストとして全文取得
                            $fileContent = Get-Content -Path $filePath -Raw -Encoding UTF8 -ErrorAction Stop
                            if ($null -ne $fileContent) {
                                $markdownContent += $fileContent
                            }
                            else {
                                $markdownContent += "// Empty file"
                            }
                        }
                    }
                    else {
                        # 先頭が空文字列
                        $markdownContent += "// Empty file"
                    }
                }
                catch {
                    # UTF-8で読めなかったら非テキスト
                    $markdownContent += "// Omitted content for non-text file: UTF-8 decode error"
                }
            }
            else {
                # そもそも0バイト => 空ファイル
                $markdownContent += "// Empty file"
            }
        }
    }
    catch {
        $markdownContent += "// Error reading file: $($_.Exception.Message)"
        Write-Warning "ファイル '$tmpRel' の読み込み中にエラー: $($_.Exception.Message)"
    }

    # コードブロック終了
    $markdownContent += '```'
    $markdownContent += ""
}

# -- 7. Markdownファイル書き込み --
Write-Verbose "Markdown ファイル '$OutputFile' に書き込みます..."
try {
    # UTF-8 (BOM 無し)で出力
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
