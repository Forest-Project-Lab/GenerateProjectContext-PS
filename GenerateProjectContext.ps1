<#
.SYNOPSIS
指定されたディレクトリ構造とファイル内容をMarkdown形式で出力します。LLMへのコンテキスト提供などに利用できます。

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
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
    $absolutePath = $resolvedPath.Path

    if (-not (Test-Path -Path $absolutePath -PathType Container)) {
        Write-Error "'$Path' は有効なディレクトリではありません。"
        exit 1
    }

    $absolutePath = $absolutePath.TrimEnd('\','/')
    if (-not $absolutePath.EndsWith('\')) {
        $absolutePath += '\'
    }

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
    $outputDir = '.'
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
    $absoluteOutputFile = Join-Path (Resolve-Path $outputDir) (Split-Path $OutputFile -Leaf)
    Write-Verbose "出力ファイルの絶対パス: '$absoluteOutputFile'"
}
catch {
    Write-Error "OutputFile '$OutputFile' の解決中にエラーが発生しました: $($_.Exception.Message)"
    exit 1
}

# -- 3. 除外/包含パターンの準備 --
$defaultExcludes = @(".git", ".svn", ".hg", ".vscode", ".idea", "node_modules")
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
$gciErrors = @()

try {
    $items = Get-ChildItem -Path $resolvedPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +gciErrors |
        Where-Object {
            $_.FullName -ne $resolvedPath -and
            $_.FullName.StartsWith($absolutePath, [StringComparison]::OrdinalIgnoreCase)
        }

    if ($gciErrors) {
        foreach ($err in $gciErrors) {
            Write-Warning "ファイルアクセスエラー: $($err.TargetObject) - $($err.Exception.Message)"
        }
    }

    Write-Verbose "フィルタリング処理を開始します。対象アイテム数: $($items.Count)"

    $allFilePaths = @()
    $allDirectoryPaths = @()

    foreach ($item in $items) {
        $currentItemPath = $item.FullName

        # 出力ファイル自身は除外
        if ($currentItemPath -eq $absoluteOutputFile) {
            Write-Verbose "出力ファイル自身を除外: '$currentItemPath'"
            continue
        }
        if ($currentItemPath -eq $absolutePath) {
            continue
        }

        $currentItemPathLower = $currentItemPath.ToLower()

        # (a) デフォルト除外
        $isExcluded = $false
        foreach ($defaultExclude in $defaultExcludes) {
            if ($item.Name -eq $defaultExclude) {
                Write-Verbose "デフォルト除外: '$currentItemPath'"
                $isExcluded = $true
                break
            }
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
                if ($excludePattern -notmatch '[\\/]') {
                    if ($item.Name -like $excludePattern) {
                        Write-Verbose "-Exclude 名前一致: '$currentItemPath'"
                        $isExcluded = $true
                        break
                    }
                }
                else {
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
                if ($includePattern -notmatch '[\\/]') {
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

        if ($item.PSIsContainer) {
            $allDirectoryPaths += $currentItemPath
        }
        else {
            $allFilePaths += $currentItemPath
        }
    }

    $allDirectoryPaths = $allDirectoryPaths | Sort-Object
    $allFilePaths = $allFilePaths | Sort-Object
    
    if ($null -eq $allDirectoryPaths) {
        Write-Verbose "[DEBUG] `$allDirectoryPaths became null after Sort-Object (was empty). Resetting to empty array."
        $allDirectoryPaths = @()
    }
    if ($null -eq $allFilePaths) {
        # ファイルがないケースも念のため対処
        Write-Verbose "[DEBUG] `$allFilePaths became null after Sort-Object (was empty). Resetting to empty array."
        $allFilePaths = @()
    }
    if ($allDirectoryPaths -ne $null -and $allDirectoryPaths.Count -eq 1 -and $allDirectoryPaths -is [string]) {
        Write-Warning "[WARN] `$allDirectoryPaths was a string after sort. Forcing back to array."
        $allDirectoryPaths = @($allDirectoryPaths)
    }
    
    Write-Verbose "フィルタリング後のディレクトリ数: $($allDirectoryPaths.Count)"
    Write-Verbose "フィルタリング後のファイル数: $($allFilePaths.Count)"
    Write-Verbose "--- Debug Start ---"
    Write-Verbose "[Debug] Type of `$allDirectoryPaths`: $($allDirectoryPaths.GetType().FullName)"
    Write-Verbose "[Debug] Count of `$allDirectoryPaths`: $($allDirectoryPaths.Count)"

    Write-Verbose "[Debug] Type of `$allFilePaths`: $($allFilePaths.GetType().FullName)"
    Write-Verbose "[Debug] Count of `$allFilePaths`: $($allFilePaths.Count)"

    try {
        $combinedItems = $allDirectoryPaths + $allFilePaths
        Write-Verbose "[Debug] Type of `$combinedItems`: $($combinedItems.GetType().FullName)"
        Write-Verbose "[Debug] Count of `$combinedItems`: $($combinedItems.Count)"

        $allItemsForStructure = $combinedItems | Sort-Object
        Write-Verbose "[Debug] Type of `$allItemsForStructure` after Sort: $($allItemsForStructure.GetType().FullName)"
        Write-Verbose "[Debug] Count of `$allItemsForStructure` after Sort: $($allItemsForStructure.Count)"
    } catch {
        Write-Error "[Debug] Error during combination/sort: $($_.Exception.Message)"
    }
    Write-Verbose "--- Debug End ---"

}
catch {
    Write-Error "ファイル探索またはフィルタリング中に予期せぬエラーが発生しました: $($_.Exception.Message)"
    exit 1
}

# -- 6. Markdown生成 --
Write-Verbose "[StructGen] Markdown生成を開始します..." # 既存ログのプレフィックス変更
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
Write-Verbose "[StructGen] ファイル構造セクションヘッダー出力完了。" # 追加ログ

# ディレクトリとファイルをまとめてソートし、階層表示
$allItemsForStructure = $allDirectoryPaths + $allFilePaths | Sort-Object
Write-Verbose "[StructGen] 構造生成対象アイテム数: $($allItemsForStructure.Count)" # 追加ログ
# Write-Verbose "[StructGen] 構造生成対象リスト: $($allItemsForStructure -join ', ')" # 必要であればコメント解除（リストが長いと見づらい）

$structureLookup = @{}
Write-Verbose "[StructGen] structureLookup ハッシュテーブルを初期化しました。" # 追加ログ

# --- Outer Loop Start ---
foreach ($itemPath in $allItemsForStructure) {
    Write-Verbose "--------------------------------------------------"
    Write-Verbose "[Debug][OuterLoop] Processing ItemPath: '$itemPath' (Type: $($itemPath.GetType().FullName))"

    $rel = $null

    # --- $rel の計算 ---
    if ($itemPath -ne $null -and $itemPath -is [string]) {
        if ($itemPath.StartsWith($absolutePath, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $itemPath.Substring($absolutePath.Length)
            Write-Verbose "[StructGen][OuterLoop]   絶対パスからの相対パス計算: '$rel'"
        } else {
            $rel = $itemPath
            Write-Verbose "[StructGen][OuterLoop]   絶対パスで始まらないためそのまま使用: '$rel'"
        }
        $rel = $rel.TrimStart('\/')
        Write-Verbose "[StructGen][OuterLoop]   相対パス (Trimmed): '$rel'"

    } else {
        Write-Warning "[WARN][OuterLoop] ItemPath is null or not a string: '$itemPath'"
        continue
    }

    $parts = @() # 先に初期化
    if ($null -ne $rel -and $rel -ne "") {
        if ($rel -match '[\\/]') { # パス区切り文字を含むか？
            # 区切り文字を含む場合のみ Split を使用
            $parts = $rel -split '[\\/]' | Where-Object { $_ -ne '' }
        } else {
            # 区切り文字を含まない場合（ファイル名やルート直下のディレクトリ名のみ）
            # $rel 自体を要素とする配列にする
            $parts = @($rel)
        }
    }
    Write-Verbose "[StructGen][OuterLoop]   パス要素に分割 (\$parts): $($parts -join ', ')"

    $currentIndent = ""
    $currentPathKeyPrefix = ""
    Write-Verbose "[StructGen][OuterLoop]   InnerLoop 用変数を初期化 (Indent='', PathKeyPrefix='')"

    # --- Inner Loop Start ---
    if ($parts.Count -gt 0) {
        for ($i = 0; $i -lt $parts.Length; $i++) {
            $part = $parts[$i]
            Write-Verbose "[StructGen][InnerLoop][$i] Part '$part' 処理開始" # ここで正しい要素が出るはず
            Write-Verbose "[StructGen][InnerLoop][$i]   現在のインデント: '$currentIndent'"

            # PathKeyの生成
            $currentPathKey = $part
            if ($i -gt 0) {
                $currentPathKey = "$($currentPathKeyPrefix)$([System.IO.Path]::DirectorySeparatorChar)$($part)"
            }
            Write-Verbose "[StructGen][InnerLoop][$i]   生成された PathKey: '$currentPathKey'"

            # 出力ロジック
            if (-not $structureLookup.ContainsKey($currentPathKey)) {
                Write-Verbose "[StructGen][InnerLoop][$i]   PathKey '$currentPathKey' は structureLookup に *存在しません*。"
                $prefix = "|-- "
                $line = "$currentIndent$prefix$part"
                Write-Verbose "[StructGen][InnerLoop][$i]   生成された行: '$line'"
                $markdownContent += $line
                Write-Verbose "[StructGen][InnerLoop][$i]   Markdownに行を追加しました。"
                $structureLookup[$currentPathKey] = $true
                Write-Verbose "[StructGen][InnerLoop][$i]   structureLookup に PathKey '$currentPathKey' を追加しました。"
            }
            else {
                Write-Verbose "[StructGen][InnerLoop][$i]   PathKey '$currentPathKey' は structureLookup に *存在します*。出力スキップ。"
            }

            $currentIndent += "   "
            Write-Verbose "[StructGen][InnerLoop][$i]   インデント更新後: '$currentIndent'"
            $currentPathKeyPrefix = $currentPathKey
            Write-Verbose "[StructGen][InnerLoop][$i]   PathKeyPrefix 更新後: '$currentPathKeyPrefix'"
            Write-Verbose "[StructGen][InnerLoop][$i] Part '$part' 処理完了。"
        }
    } else {
         Write-Verbose "[StructGen][OuterLoop]   No parts to process for '$rel'."
    }
    # --- Inner Loop End ---

    Write-Verbose "[StructGen][OuterLoop] ItemPath 処理完了: '$itemPath'"
}
# --- Outer Loop End ---
Write-Verbose "--------------------------------------------------" # 区切り線

$markdownContent += '```'
$markdownContent += ""
Write-Verbose "[StructGen] ファイル構造セクション生成完了 (フッター出力含む)。" # 追加ログ

# ファイル内容セクション (ここからは元のまま)
# ... (以降のコードは省略) ...

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
    }
    else {
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
            $markdownContent += "// File content omitted because it exceeds $($maxFileSizeMB)MB"
            Write-Warning "ファイル '$tmpRel' は $($maxFileSizeMB)MB を超えるため内容は省略されました。"
        }
        else {
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
                    $decodedSample = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                    $controlCount = 0
                    $chars = $decodedSample.ToCharArray()
                    foreach ($ch in $chars) {
                        $code = [int][char]$ch
                        if ((($code -lt 32) -and ($code -notin 9,10,13)) -or ($code -eq 127)) {
                            $controlCount++
                        }
                    }
                    $totalLen = $chars.Length
                    if ($totalLen -gt 0) {
                        $controlRatio = $controlCount / $totalLen
                        if ($controlRatio -ge 0.1) {
                            $markdownContent += "// Omitted content for non-text file: control characters ratio $($controlRatio.ToString('P1'))"
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
                    else {
                        $markdownContent += "// Empty file"
                    }
                }
                catch {
                    $markdownContent += "// Omitted content for non-text file: UTF-8 decode error"
                }
            }
            else {
                $markdownContent += "// Empty file"
            }
        }
    }
    catch {
        $markdownContent += "// Error reading file: $($_.Exception.Message)"
        Write-Warning "ファイル '$tmpRel' の読み込み中にエラー: $($_.Exception.Message)"
    }

    $markdownContent += '```'
    $markdownContent += ""
}

# -- 7. Markdownファイル書き込み --
Write-Verbose "Markdown ファイル '$OutputFile' に書き込みます..."
try {
    [System.IO.File]::WriteAllLines($OutputFile, $markdownContent, [System.Text.UTF8Encoding]::new($false))
    Write-Verbose "処理が完了しました。出力ファイル: '$OutputFile'"
}
catch {
    Write-Error "ファイル '$OutputFile' への書き込み中にエラー: $($_.Exception.Message)"
    exit 1
}

Write-Verbose "スクリプトを終了します。"
exit 0
# End of script
