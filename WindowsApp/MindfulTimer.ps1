[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$RenderPreview,
    [switch]$RenderDesignOptions,
    [switch]$SmokeTest,
    [string]$DataDirectory = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:DataDir = if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    Join-Path $script:AppDir "data"
}
else {
    [System.IO.Path]::GetFullPath($DataDirectory)
}
$script:DraftPath = Join-Path $script:DataDir "draft.json"
$script:CurrentNotePath = Join-Path $script:DataDir "current-note.md"
$script:RecordsJsonPath = Join-Path $script:DataDir "records.json"
$script:RecordsMarkdownPath = Join-Path $script:DataDir "records.md"
$script:SettingsPath = Join-Path $script:DataDir "settings.json"
$script:IconPath = Join-Path $script:AppDir "assets\MindfulTimer.ico"

$xamlPath = Join-Path $script:AppDir "App.xaml"
$stringsPath = Join-Path $script:AppDir "strings.json"
$xamlText = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
$stringsText = [System.IO.File]::ReadAllText($stringsPath, [System.Text.Encoding]::UTF8)
$script:Strings = $stringsText | ConvertFrom-Json

$xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlText))
try {
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)
}
finally {
    $xmlReader.Dispose()
}
if (Test-Path -LiteralPath $script:IconPath) {
    $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($script:IconPath))
}

if ($ValidateOnly) {
    $libraryValidationPath = Join-Path $script:AppDir "NotesLibrary.xaml"
    $libraryValidationText = [System.IO.File]::ReadAllText($libraryValidationPath, [System.Text.Encoding]::UTF8)
    $libraryValidationReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($libraryValidationText))
    try {
        $libraryValidationWindow = [Windows.Markup.XamlReader]::Load($libraryValidationReader)
        $libraryValidationWindow.Close()
    }
    finally {
        $libraryValidationReader.Dispose()
    }
    Write-Output "Mindful Timer and Notes Library XAML loaded successfully."
    exit 0
}

if (-not (Test-Path -LiteralPath $script:DataDir)) {
    New-Item -ItemType Directory -Path $script:DataDir | Out-Null
}
if (-not (Test-Path -LiteralPath $script:RecordsMarkdownPath)) {
    [System.IO.File]::WriteAllText(
        $script:RecordsMarkdownPath,
        "# Mindful records`r`n`r`n",
        [System.Text.UTF8Encoding]::new($true)
    )
}
if (-not (Test-Path -LiteralPath $script:RecordsJsonPath)) {
    [System.IO.File]::WriteAllText(
        $script:RecordsJsonPath,
        "[]",
        [System.Text.UTF8Encoding]::new($true)
    )
}

$DragBar = $window.FindName("DragBar")
$RootBorder = $window.FindName("RootBorder")
$RootShadow = $window.FindName("RootShadow")
$ThemeButton = $window.FindName("ThemeButton")
$MoonIcon = $window.FindName("MoonIcon")
$SunIcon = $window.FindName("SunIcon")
$MinimizeButton = $window.FindName("MinimizeButton")
$CloseButton = $window.FindName("CloseButton")
$SaveStatus = $window.FindName("SaveStatus")
$StartPanel = $window.FindName("StartPanel")
$PurposeInput = $window.FindName("PurposeInput")
$RestoreHint = $window.FindName("RestoreHint")
$StartLibraryButton = $window.FindName("StartLibraryButton")
$StartButton = $window.FindName("StartButton")
$TimerPanel = $window.FindName("TimerPanel")
$ActivePurpose = $window.FindName("ActivePurpose")
$TimerText = $window.FindName("TimerText")
$ToggleNotesButton = $window.FindName("ToggleNotesButton")
$OpenRecordsButton = $window.FindName("OpenRecordsButton")
$FinishButton = $window.FindName("FinishButton")
$NotesPanel = $window.FindName("NotesPanel")
$NotesInput = $window.FindName("NotesInput")
$DonePanel = $window.FindName("DonePanel")
$DoneSummary = $window.FindName("DoneSummary")
$DoneMeta = $window.FindName("DoneMeta")
$DoneOpenButton = $window.FindName("DoneOpenButton")
$NextButton = $window.FindName("NextButton")

$script:Stopwatch = [System.Diagnostics.Stopwatch]::new()
$script:IsActive = $false
$script:IsFinishing = $false
$script:NotesExpanded = $false
$script:DraftDirty = $false
$script:CurrentPurpose = ""
$script:CurrentStartTime = $null
$script:CurrentTheme = "light"
$script:NotesLibraryWindow = $null
$script:RestoreTopmostAfterLibrary = $true

function Set-ThemeBrush {
    param(
        [string]$Name,
        [string]$Color
    )
    $converted = [System.Windows.Media.ColorConverter]::ConvertFromString($Color)
    $window.Resources[$Name] = [System.Windows.Media.SolidColorBrush]::new($converted)
}

function Save-ThemePreference {
    $settings = [ordered]@{ theme = $script:CurrentTheme }
    $settingsJson = $settings | ConvertTo-Json
    [System.IO.File]::WriteAllText(
        $script:SettingsPath,
        $settingsJson,
        [System.Text.UTF8Encoding]::new($true)
    )
}

function Get-InitialTheme {
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            $settingsText = [System.IO.File]::ReadAllText($script:SettingsPath, [System.Text.Encoding]::UTF8)
            $settings = $settingsText | ConvertFrom-Json
            if ($settings.theme -in @("light", "dark")) { return [string]$settings.theme }
        }
        catch { }
    }

    try {
        $systemLight = Get-ItemPropertyValue -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme"
        if ($systemLight -eq 0) { return "dark" }
    }
    catch { }
    return "light"
}

function Get-ThemePalette {
    param([ValidateSet("light", "dark")][string]$Theme)
    if ($Theme -eq "dark") {
        return @{
            CanvasBrush = "#15181B"
            SurfaceBrush = "#20252A"
            InkBrush = "#F7F7F4"
            MutedBrush = "#9CA7AE"
            SageBrush = "#B6F3C7"
            PaleSageBrush = "#26362C"
            LineBrush = "#30363A"
            InputBrush = "#1D2226"
            ButtonTextBrush = "#122017"
            FrameBrush = "#2A2E32"
        }
    }
    return @{
        CanvasBrush = "#F4F8F5"
        SurfaceBrush = "#E6EFEA"
        InkBrush = "#1F2924"
        MutedBrush = "#66756D"
        SageBrush = "#2F765D"
        PaleSageBrush = "#D9ECE2"
        LineBrush = "#D8E3DD"
        InputBrush = "#FFFFFF"
        ButtonTextBrush = "#FFFFFF"
        FrameBrush = "#D9E4DE"
    }
}

function Apply-Theme {
    param(
        [ValidateSet("light", "dark")]
        [string]$Theme,
        [switch]$Persist
    )

    $script:CurrentTheme = $Theme
    $palette = Get-ThemePalette -Theme $Theme
    if ($Theme -eq "dark") {
        $MoonIcon.Visibility = "Collapsed"
        $SunIcon.Visibility = "Visible"
        $ThemeButton.ToolTip = $script:Strings.switchToLight
        if ($null -ne $RootShadow) {
            $RootShadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
            $RootShadow.Opacity = 0.48
        }
    }
    else {
        $MoonIcon.Visibility = "Visible"
        $SunIcon.Visibility = "Collapsed"
        $ThemeButton.ToolTip = $script:Strings.switchToDark
        if ($null -ne $RootShadow) {
            $RootShadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#273024")
            $RootShadow.Opacity = 0.18
        }
    }

    foreach ($entry in $palette.GetEnumerator()) {
        Set-ThemeBrush -Name $entry.Key -Color $entry.Value
    }
    if ($null -ne $script:NotesLibraryWindow -and $script:NotesLibraryWindow.IsVisible) {
        Apply-LibraryTheme -LibraryWindow $script:NotesLibraryWindow -Theme $Theme
    }
    if ($Persist) { Save-ThemePreference }
}

function Format-Elapsed {
    param([TimeSpan]$Elapsed)
    $totalHours = [Math]::Floor($Elapsed.TotalHours)
    if ($totalHours -gt 0) {
        return "{0:00}:{1:00}:{2:00}" -f $totalHours, $Elapsed.Minutes, $Elapsed.Seconds
    }
    return "{0:00}:{1:00}" -f [Math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds
}

function Set-StartLayout {
    $window.Topmost = $true
    $StartPanel.Visibility = "Visible"
    $TimerPanel.Visibility = "Collapsed"
    $DonePanel.Visibility = "Collapsed"
    $SaveStatus.Text = ""
    $window.Width = 480
    $window.Height = 286
    $PurposeInput.Focus() | Out-Null
}

function Set-TimerLayout {
    $window.Topmost = $true
    $StartPanel.Visibility = "Collapsed"
    $TimerPanel.Visibility = "Visible"
    $DonePanel.Visibility = "Collapsed"
    if ($script:NotesExpanded) {
        $NotesPanel.Visibility = "Visible"
        $ToggleNotesButton.Content = $script:Strings.collapseNotes
        $window.Width = 620
        $window.Height = 600
    }
    else {
        $NotesPanel.Visibility = "Collapsed"
        $ToggleNotesButton.Content = $script:Strings.expandNotes
        $window.Width = 520
        $window.Height = 210
    }
}

function Set-DoneLayout {
    $window.Topmost = $false
    $StartPanel.Visibility = "Collapsed"
    $TimerPanel.Visibility = "Collapsed"
    $DonePanel.Visibility = "Visible"
    $SaveStatus.Text = $script:Strings.saved
    $window.Width = 520
    $window.Height = 330
}

function Write-Draft {
    if (-not $script:IsActive) { return }
    $SaveStatus.Text = $script:Strings.saving

    $draft = [ordered]@{
        purpose = $script:CurrentPurpose
        startedAt = $script:CurrentStartTime.ToString("o")
        note = $NotesInput.Text
    }
    $draftJson = $draft | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText(
        $script:DraftPath,
        $draftJson,
        [System.Text.UTF8Encoding]::new($true)
    )

    $noteText = "# Current mindful note`r`n`r`nPurpose: $($script:CurrentPurpose)`r`n`r`n---`r`n`r`n$($NotesInput.Text)"
    [System.IO.File]::WriteAllText(
        $script:CurrentNotePath,
        $noteText,
        [System.Text.UTF8Encoding]::new($true)
    )

    $script:DraftDirty = $false
    $SaveStatus.Text = $script:Strings.saved
}

function Restore-Draft {
    if (-not (Test-Path -LiteralPath $script:DraftPath)) { return }
    try {
        $text = [System.IO.File]::ReadAllText($script:DraftPath, [System.Text.Encoding]::UTF8)
        $draft = $text | ConvertFrom-Json
        if ($draft.purpose) { $PurposeInput.Text = [string]$draft.purpose }
        if ($draft.note) { $NotesInput.Text = [string]$draft.note }
        $RestoreHint.Text = $script:Strings.restoreHint
    }
    catch {
        $RestoreHint.Text = ""
    }
}

function Start-Session {
    $purpose = $PurposeInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($purpose)) {
        [System.Windows.MessageBox]::Show(
            $script:Strings.purposeRequired,
            $script:Strings.closeTitle,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
        $PurposeInput.Focus() | Out-Null
        return
    }

    $script:CurrentPurpose = $purpose
    $script:CurrentStartTime = [DateTimeOffset]::Now
    $script:IsActive = $true
    $script:NotesExpanded = $false
    $script:DraftDirty = $true
    $ActivePurpose.Text = $purpose
    $TimerText.Text = "00:00"
    $script:Stopwatch.Restart()
    Set-TimerLayout
    Write-Draft
}

function Save-SessionRecord {
    if (-not $script:IsActive -or $script:IsFinishing) { return $null }
    $script:IsFinishing = $true
    try {
        $script:Stopwatch.Stop()
        $endedAt = [DateTimeOffset]::Now
        $elapsed = $script:Stopwatch.Elapsed
        $record = [ordered]@{
            id = [Guid]::NewGuid().ToString()
            purpose = $script:CurrentPurpose
            startedAt = $script:CurrentStartTime.ToString("o")
            endedAt = $endedAt.ToString("o")
            elapsedSeconds = [Math]::Floor($elapsed.TotalSeconds)
            notes = $NotesInput.Text
        }

        $existingText = [System.IO.File]::ReadAllText($script:RecordsJsonPath, [System.Text.Encoding]::UTF8)
        $existing = @($existingText | ConvertFrom-Json | Where-Object {
            $null -ne $_ -and
            $null -ne $_.PSObject.Properties["purpose"] -and
            $null -ne $_.PSObject.Properties["endedAt"]
        })
        $allRecords = @($existing) + [pscustomobject]$record
        $recordsJson = $allRecords | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText(
            $script:RecordsJsonPath,
            $recordsJson,
            [System.Text.UTF8Encoding]::new($true)
        )

        $duration = Format-Elapsed -Elapsed $elapsed
        $notes = if ([string]::IsNullOrWhiteSpace($NotesInput.Text)) { "_No notes._" } else { $NotesInput.Text.Trim() }
        $entry = @"
## $($endedAt.ToString("yyyy-MM-dd HH:mm")) - $($script:CurrentPurpose)

- Duration: $duration
- Started: $($script:CurrentStartTime.ToString("yyyy-MM-dd HH:mm:ss"))
- Ended: $($endedAt.ToString("yyyy-MM-dd HH:mm:ss"))

$notes

---

"@
        [System.IO.File]::AppendAllText(
            $script:RecordsMarkdownPath,
            $entry,
            [System.Text.UTF8Encoding]::new($true)
        )

        foreach ($path in @($script:DraftPath, $script:CurrentNotePath)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }

        $script:IsActive = $false
        $DoneSummary.Text = $script:CurrentPurpose
        $DoneMeta.Text = "$duration$($script:Strings.separator)$($endedAt.ToString("yyyy-MM-dd HH:mm"))"
        Set-DoneLayout
        return [pscustomobject]$record
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "$($script:Strings.saveError) $($_.Exception.Message)",
            $script:Strings.closeTitle,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        $script:Stopwatch.Start()
        return $null
    }
    finally {
        $script:IsFinishing = $false
    }
}

function Discard-Draft {
    $script:Stopwatch.Stop()
    $script:IsActive = $false
    foreach ($path in @($script:DraftPath, $script:CurrentNotePath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Ensure-DesktopShortcut {
    param([string]$TargetDirectory = "")

    try {
        $desktopDirectory = if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
            [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        }
        else {
            [System.IO.Path]::GetFullPath($TargetDirectory)
        }
        if ([string]::IsNullOrWhiteSpace($desktopDirectory)) { return $false }
        if (-not (Test-Path -LiteralPath $desktopDirectory)) {
            New-Item -ItemType Directory -Path $desktopDirectory | Out-Null
        }

        $shortcutPath = Join-Path $desktopDirectory "Mindful Timer.lnk"
        $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $scriptPath = Join-Path $script:AppDir "MindfulTimer.ps1"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $powershellPath
        $shortcut.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
        $shortcut.WorkingDirectory = $script:AppDir
        $shortcut.Description = "Mindful Timer - intentional browsing and notes"
        if (Test-Path -LiteralPath $script:IconPath) {
            $shortcut.IconLocation = "$($script:IconPath),0"
        }
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        return (Test-Path -LiteralPath $shortcutPath)
    }
    catch {
        return $false
    }
}

function Open-RawRecordsFile {
    try {
        Start-Process -FilePath "notepad.exe" -ArgumentList "`"$script:RecordsMarkdownPath`""
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "$($script:Strings.openError) $($_.Exception.Message)",
            $script:Strings.closeTitle,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

function Format-ElapsedSeconds {
    param([double]$Seconds)
    return Format-Elapsed -Elapsed ([TimeSpan]::FromSeconds([Math]::Max(0, $Seconds)))
}

function Get-LibraryItems {
    $items = [System.Collections.ArrayList]::new()

    if (Test-Path -LiteralPath $script:DraftPath) {
        try {
            $draftText = [System.IO.File]::ReadAllText($script:DraftPath, [System.Text.Encoding]::UTF8)
            $draft = $draftText | ConvertFrom-Json
            $started = [DateTimeOffset]::Parse([string]$draft.startedAt).ToLocalTime()
            $notes = if ([string]::IsNullOrWhiteSpace([string]$draft.note)) { $script:Strings.noNotes } else { [string]$draft.note }
            $item = [pscustomobject]@{
                Purpose = [string]$draft.purpose
                ListMeta = $script:Strings.ongoingMeta
                Kind = $script:Strings.currentDraftKind
                DetailMeta = $started.ToString("yyyy-MM-dd HH:mm")
                Notes = $notes
                SavedHint = $script:Strings.autoSavedHint
                SearchText = "$($draft.purpose) $notes".ToLowerInvariant()
                CopyText = "$($draft.purpose)`r`n$($started.ToString("yyyy-MM-dd HH:mm"))`r`n`r`n$notes"
            }
            [void]$items.Add($item)
        }
        catch { }
    }

    if (Test-Path -LiteralPath $script:RecordsJsonPath) {
        try {
            $recordsText = [System.IO.File]::ReadAllText($script:RecordsJsonPath, [System.Text.Encoding]::UTF8)
            $records = @($recordsText | ConvertFrom-Json | Where-Object {
                $null -ne $_ -and
                $null -ne $_.PSObject.Properties["purpose"] -and
                $null -ne $_.PSObject.Properties["endedAt"]
            }) | Sort-Object { [DateTimeOffset]::Parse([string]$_.endedAt) } -Descending
            foreach ($record in $records) {
                if ($null -eq $record) { continue }
                $ended = [DateTimeOffset]::Parse([string]$record.endedAt).ToLocalTime()
                $duration = Format-ElapsedSeconds -Seconds ([double]$record.elapsedSeconds)
                $notes = if ([string]::IsNullOrWhiteSpace([string]$record.notes)) { $script:Strings.noNotes } else { [string]$record.notes }
                $listMeta = "$($ended.ToString("yyyy-MM-dd"))$($script:Strings.separator)$duration"
                $detailMeta = "$($ended.ToString("yyyy-MM-dd HH:mm"))$($script:Strings.separator)$duration"
                $item = [pscustomobject]@{
                    Purpose = [string]$record.purpose
                    ListMeta = $listMeta
                    Kind = $script:Strings.sessionKind
                    DetailMeta = $detailMeta
                    Notes = $notes
                    SavedHint = $script:Strings.archivedHint
                    SearchText = "$($record.purpose) $notes".ToLowerInvariant()
                    CopyText = "$($record.purpose)`r`n$detailMeta`r`n`r`n$notes"
                }
                [void]$items.Add($item)
            }
        }
        catch {
            if ($SmokeTest) { throw }
        }
    }

    return @($items)
}

function Apply-LibraryTheme {
    param(
        [System.Windows.Window]$LibraryWindow,
        [ValidateSet("light", "dark")][string]$Theme
    )
    $palette = Get-ThemePalette -Theme $Theme
    foreach ($entry in $palette.GetEnumerator()) {
        $converted = [System.Windows.Media.ColorConverter]::ConvertFromString($entry.Value)
        $LibraryWindow.Resources[$entry.Key] = [System.Windows.Media.SolidColorBrush]::new($converted)
    }
    $libraryMoonIcon = $LibraryWindow.FindName("LibraryMoonIcon")
    $librarySunIcon = $LibraryWindow.FindName("LibrarySunIcon")
    $libraryThemeButton = $LibraryWindow.FindName("LibraryThemeButton")
    if ($Theme -eq "dark") {
        if ($null -ne $libraryMoonIcon) { $libraryMoonIcon.Visibility = "Collapsed" }
        if ($null -ne $librarySunIcon) { $librarySunIcon.Visibility = "Visible" }
        if ($null -ne $libraryThemeButton) { $libraryThemeButton.ToolTip = $script:Strings.switchToLight }
    }
    else {
        if ($null -ne $libraryMoonIcon) { $libraryMoonIcon.Visibility = "Visible" }
        if ($null -ne $librarySunIcon) { $librarySunIcon.Visibility = "Collapsed" }
        if ($null -ne $libraryThemeButton) { $libraryThemeButton.ToolTip = $script:Strings.switchToDark }
    }
    $shadow = $LibraryWindow.FindName("LibraryShadow")
    if ($null -ne $shadow) {
        if ($Theme -eq "dark") {
            $shadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
            $shadow.Opacity = 0.5
        }
        else {
            $shadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#273024")
            $shadow.Opacity = 0.2
        }
    }
}

function New-NotesLibraryWindow {
    param([object[]]$PreviewItems = $null)

    $libraryPath = Join-Path $script:AppDir "NotesLibrary.xaml"
    $libraryXaml = [System.IO.File]::ReadAllText($libraryPath, [System.Text.Encoding]::UTF8)
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($libraryXaml))
    try { $library = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    if (Test-Path -LiteralPath $script:IconPath) {
        $library.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($script:IconPath))
    }

    Apply-LibraryTheme -LibraryWindow $library -Theme $script:CurrentTheme

    $dragBar = $library.FindName("LibraryDragBar")
    $closeButton = $library.FindName("LibraryCloseButton")
    $libraryThemeButton = $library.FindName("LibraryThemeButton")
    $searchInput = $library.FindName("LibrarySearchInput")
    $list = $library.FindName("LibraryList")
    $count = $library.FindName("LibraryCount")
    $emptyPanel = $library.FindName("LibraryEmptyPanel")
    $detailPanel = $library.FindName("LibraryDetailPanel")
    $detailKind = $library.FindName("DetailKind")
    $detailPurpose = $library.FindName("DetailPurpose")
    $detailMeta = $library.FindName("DetailMeta")
    $detailNotes = $library.FindName("DetailNotes")
    $detailSavedHint = $library.FindName("DetailSavedHint")
    $copyButton = $library.FindName("CopyNoteButton")
    $copyLabel = $library.FindName("CopyNoteLabel")
    $openRawButton = $library.FindName("OpenRawButton")
    $libraryStrings = $script:Strings

    $allItems = @()
    if ($null -ne $PreviewItems) {
        $allItems = @($PreviewItems)
    }
    else {
        $allItems = @(Get-LibraryItems)
    }
    $libraryState = @{
        AllItems = $allItems
        SelectedItem = $null
        PlaceholderActive = $true
    }
    $searchInput.Text = $script:Strings.searchPlaceholder
    $searchInput.Foreground = $library.Resources["MutedBrush"]

    $showDetail = {
        param($item)
        $libraryState.SelectedItem = $item
        if ($null -eq $item) {
            $detailPanel.Visibility = "Collapsed"
            $emptyPanel.Visibility = "Visible"
            return
        }
        $emptyPanel.Visibility = "Collapsed"
        $detailPanel.Visibility = "Visible"
        $detailKind.Text = $item.Kind
        $detailPurpose.Text = $item.Purpose
        $detailMeta.Text = $item.DetailMeta
        $detailNotes.Text = $item.Notes
        $detailSavedHint.Text = $item.SavedHint
        $copyLabel.Text = $libraryStrings.copyFull
    }.GetNewClosure()

    $refreshList = {
        $query = if ($libraryState.PlaceholderActive) { "" } else { $searchInput.Text.Trim().ToLowerInvariant() }
        $filtered = @(
            if ([string]::IsNullOrWhiteSpace($query)) {
                $libraryState.AllItems
            }
            else {
                $libraryState.AllItems | Where-Object { $_.SearchText.Contains($query) }
            }
        )
        $list.ItemsSource = $null
        $list.ItemsSource = $filtered
        $count.Text = $libraryStrings.countFormat -f $filtered.Count
        if ($filtered.Count -gt 0) {
            $list.SelectedIndex = 0
            & $showDetail $filtered[0]
        }
        else {
            & $showDetail $null
        }
    }.GetNewClosure()

    $dragBar.Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
            try { $library.DragMove() } catch { }
        }
    }.GetNewClosure())
    $closeButton.Add_Click({ $library.Close() }.GetNewClosure())
    $libraryThemeButton.Add_Click({
        $nextTheme = if ($script:CurrentTheme -eq "dark") { "light" } else { "dark" }
        Apply-Theme -Theme $nextTheme -Persist
    })
    $openRawButton.Add_Click({ Open-RawRecordsFile })
    $list.Add_SelectionChanged({
        if ($null -ne $list.SelectedItem) { & $showDetail $list.SelectedItem }
    }.GetNewClosure())
    $searchInput.Add_GotFocus({
        if ($libraryState.PlaceholderActive) {
            $libraryState.PlaceholderActive = $false
            $searchInput.Text = ""
            $searchInput.Foreground = $library.Resources["InkBrush"]
        }
    }.GetNewClosure())
    $searchInput.Add_LostFocus({
        if ([string]::IsNullOrWhiteSpace($searchInput.Text)) {
            $libraryState.PlaceholderActive = $true
            $searchInput.Text = $libraryStrings.searchPlaceholder
            $searchInput.Foreground = $library.Resources["MutedBrush"]
            & $refreshList
        }
    }.GetNewClosure())
    $searchInput.Add_TextChanged({
        if (-not $libraryState.PlaceholderActive) { & $refreshList }
    }.GetNewClosure())
    $copyButton.Add_MouseLeftButtonDown({
        if ($null -ne $libraryState.SelectedItem) {
            [System.Windows.Clipboard]::SetText([string]$libraryState.SelectedItem.CopyText)
            $copyLabel.Text = $libraryStrings.copySuccess
        }
    }.GetNewClosure())
    $library.Add_PreviewKeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
            $library.Close()
            $_.Handled = $true
        }
        elseif (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -and $_.Key -eq [System.Windows.Input.Key]::F) {
            $searchInput.Focus() | Out-Null
            $_.Handled = $true
        }
    }.GetNewClosure())
    $library.Add_Closed({
        $script:NotesLibraryWindow = $null
        $window.Topmost = $script:RestoreTopmostAfterLibrary
    })

    & $refreshList
    return $library
}

function Show-NotesLibrary {
    try {
        if ($null -ne $script:NotesLibraryWindow -and $script:NotesLibraryWindow.IsVisible) {
            $script:NotesLibraryWindow.Activate() | Out-Null
            return
        }
        $script:RestoreTopmostAfterLibrary = $window.Topmost
        $window.Topmost = $false
        $script:NotesLibraryWindow = New-NotesLibraryWindow
        $script:NotesLibraryWindow.Show()
        $script:NotesLibraryWindow.Activate() | Out-Null
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "$($script:Strings.libraryError) $($_.Exception.Message)",
            $script:Strings.closeTitle,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

function Reset-ForNextSession {
    $PurposeInput.Text = ""
    $NotesInput.Text = ""
    $RestoreHint.Text = ""
    $script:CurrentPurpose = ""
    $script:CurrentStartTime = $null
    $script:NotesExpanded = $false
    Set-StartLayout
}

function Export-WindowImage {
    param(
        [string]$Path,
        [System.Windows.Window]$TargetWindow = $window
    )
    $TargetWindow.UpdateLayout()
    $width = [Math]::Max(1, [int][Math]::Ceiling($TargetWindow.ActualWidth))
    $height = [Math]::Max(1, [int][Math]::Ceiling($TargetWindow.ActualHeight))
    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        $width,
        $height,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )
    $bitmap.Render($TargetWindow)
    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

$tickTimer = [System.Windows.Threading.DispatcherTimer]::new()
$tickTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$tickTimer.Add_Tick({
    if ($script:IsActive) {
        $TimerText.Text = Format-Elapsed -Elapsed $script:Stopwatch.Elapsed
    }
})
$tickTimer.Start()

$saveTimer = [System.Windows.Threading.DispatcherTimer]::new()
$saveTimer.Interval = [TimeSpan]::FromSeconds(2)
$saveTimer.Add_Tick({
    if ($script:IsActive -and $script:DraftDirty) {
        try { Write-Draft } catch { $SaveStatus.Text = "!" }
    }
})
$saveTimer.Start()

$DragBar.Add_MouseLeftButtonDown({
    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        try { $window.DragMove() } catch { }
    }
})
$ThemeButton.Add_Click({
    $nextTheme = if ($script:CurrentTheme -eq "light") { "dark" } else { "light" }
    Apply-Theme -Theme $nextTheme -Persist
})
$MinimizeButton.Add_Click({ $window.WindowState = "Minimized" })
$CloseButton.Add_Click({ $window.Close() })
$StartButton.Add_Click({ Start-Session })
$StartLibraryButton.Add_Click({ Show-NotesLibrary })
$FinishButton.Add_Click({ Save-SessionRecord | Out-Null })
$ToggleNotesButton.Add_Click({
    $script:NotesExpanded = -not $script:NotesExpanded
    Set-TimerLayout
    if ($script:NotesExpanded) { $NotesInput.Focus() | Out-Null }
})
$OpenRecordsButton.Add_Click({ Show-NotesLibrary })
$DoneOpenButton.Add_Click({ Show-NotesLibrary })
$NextButton.Add_Click({ Reset-ForNextSession })
$NotesInput.Add_TextChanged({
    if ($script:IsActive) {
        $script:DraftDirty = $true
        $SaveStatus.Text = $script:Strings.dirty
    }
})
$PurposeInput.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Enter) {
        Start-Session
        $_.Handled = $true
    }
})
$window.Add_PreviewKeyDown({
    $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
    if ($ctrl -and $_.Key -eq [System.Windows.Input.Key]::S -and $script:IsActive) {
        try { Write-Draft } catch { }
        $_.Handled = $true
    }
    elseif ($_.Key -eq [System.Windows.Input.Key]::Escape -and $script:NotesExpanded) {
        $script:NotesExpanded = $false
        Set-TimerLayout
        $_.Handled = $true
    }
})
$window.Add_Closing({
    param($sender, $eventArgs)
    if (-not $script:IsActive) { return }

    $choice = [System.Windows.MessageBox]::Show(
        $script:Strings.closePrompt,
        $script:Strings.closeTitle,
        [System.Windows.MessageBoxButton]::YesNoCancel,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($choice -eq [System.Windows.MessageBoxResult]::Cancel) {
        $eventArgs.Cancel = $true
    }
    elseif ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
        $saved = Save-SessionRecord
        if ($null -eq $saved) { $eventArgs.Cancel = $true }
    }
    else {
        Discard-Draft
    }
})
$window.Add_Closed({
    $tickTimer.Stop()
    $saveTimer.Stop()
})

Apply-Theme -Theme (Get-InitialTheme)
Restore-Draft
Set-StartLayout

if (-not ($SmokeTest -or $RenderPreview -or $RenderDesignOptions)) {
    [void](Ensure-DesktopShortcut)
}

if ($SmokeTest) {
    $shortcutTestDirectory = Join-Path $script:DataDir "shortcut-test"
    if (-not (Ensure-DesktopShortcut -TargetDirectory $shortcutTestDirectory)) {
        throw "Desktop shortcut creation failed."
    }
    $shortcutTestPath = Join-Path $shortcutTestDirectory "Mindful Timer.lnk"
    $shortcutShell = New-Object -ComObject WScript.Shell
    $shortcutTest = $shortcutShell.CreateShortcut($shortcutTestPath)
    if (-not $shortcutTest.IconLocation.Contains("MindfulTimer.ico")) {
        throw "Desktop shortcut icon was not configured."
    }
    $window.Show()
    if (-not $window.Topmost) { throw "Start state should be topmost." }
    if ($null -eq $StartLibraryButton) { throw "Start screen Notes Library entry is missing." }
    Show-NotesLibrary
    if ($window.Topmost) { throw "Start window should pause topmost while Notes Library is open." }
    $script:NotesLibraryWindow.Close()
    if (-not $window.Topmost) { throw "Start window should restore topmost after Notes Library closes." }
    Apply-Theme -Theme "dark" -Persist
    $themeSettings = [System.IO.File]::ReadAllText($script:SettingsPath, [System.Text.Encoding]::UTF8)
    if (-not $themeSettings.Contains("dark")) { throw "Dark theme persistence check failed." }
    Apply-Theme -Theme "light" -Persist
    $PurposeInput.Text = $script:Strings.previewPurpose
    Start-Session
    if (-not $window.Topmost) { throw "Active timer should be topmost." }
    Show-NotesLibrary
    if ($window.Topmost) { throw "Timer should pause topmost while Notes Library is open." }
    if ($script:NotesLibraryWindow.Topmost) { throw "Notes Library should not be topmost." }
    $script:NotesLibraryWindow.Close()
    if (-not $window.Topmost) { throw "Active timer should restore topmost after Notes Library closes." }
    $NotesInput.Text = $script:Strings.previewNotes
    [System.Threading.Thread]::Sleep(1100)
    $savedRecord = Save-SessionRecord
    if ($null -eq $savedRecord) { throw "Smoke test did not create a record." }
    if ($window.Topmost) { throw "Completed state should not be topmost." }
    $savedMarkdown = [System.IO.File]::ReadAllText($script:RecordsMarkdownPath, [System.Text.Encoding]::UTF8)
    $savedJson = [System.IO.File]::ReadAllText($script:RecordsJsonPath, [System.Text.Encoding]::UTF8)
    if (-not $savedMarkdown.Contains($script:Strings.previewPurpose)) { throw "Markdown archive check failed." }
    if (-not $savedJson.Contains($script:Strings.previewPurpose)) { throw "JSON archive check failed." }
    $script:NotesLibraryWindow = New-NotesLibraryWindow
    $script:NotesLibraryWindow.Show()
    if ($script:NotesLibraryWindow.Topmost) { throw "Notes Library should not be topmost." }
    $libraryListTest = $script:NotesLibraryWindow.FindName("LibraryList")
    $libraryPurposeTest = $script:NotesLibraryWindow.FindName("DetailPurpose")
    $libraryThemeButtonTest = $script:NotesLibraryWindow.FindName("LibraryThemeButton")
    if ($libraryListTest.Items.Count -lt 1) { throw "Notes Library did not load archived records." }
    if (-not $libraryPurposeTest.Text.Contains($script:Strings.previewPurpose)) { throw "Notes Library detail selection check failed." }
    $libraryThemeButtonTest.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    if ($script:CurrentTheme -ne "dark") { throw "Notes Library theme toggle did not update global theme." }
    $libraryCanvasTest = $script:NotesLibraryWindow.Resources["CanvasBrush"].Color.ToString()
    if ($libraryCanvasTest -ne "#FF15181B") { throw "Notes Library dark theme sync check failed." }
    $mainCanvasTest = $window.Resources["CanvasBrush"].Color.ToString()
    if ($mainCanvasTest -ne "#FF15181B") { throw "Main window did not sync from Notes Library theme toggle." }
    $libraryThemeButtonTest.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    if ($script:CurrentTheme -ne "light") { throw "Notes Library theme toggle did not return to light theme." }
    $script:NotesLibraryWindow.Close()
    $window.Close()
    Write-Output "Mindful Timer smoke test passed: theme toggle, timer, notes library, Markdown and JSON archive."
    exit 0
}

if ($RenderDesignOptions) {
    $optionsDir = Join-Path $script:AppDir "preview\options"
    if (-not (Test-Path -LiteralPath $optionsDir)) {
        New-Item -ItemType Directory -Path $optionsDir | Out-Null
    }

    $window.Show()
    Set-StartLayout
    $PurposeInput.Text = $script:Strings.previewPurpose

    $colorOptions = @(
        [pscustomobject]@{
            Name = "a-mist-blue"
            Palette = @{
                CanvasBrush = "#F5F7F8"; SurfaceBrush = "#E9EFF2"; InkBrush = "#202830"
                MutedBrush = "#697780"; SageBrush = "#466F87"; PaleSageBrush = "#DCE8EE"
                LineBrush = "#D7E0E5"; InputBrush = "#FFFFFF"; ButtonTextBrush = "#FFFFFF"; FrameBrush = "#D9E1E5"
            }
        },
        [pscustomobject]@{
            Name = "b-warm-terracotta"
            Palette = @{
                CanvasBrush = "#FCF7EF"; SurfaceBrush = "#F3E9DE"; InkBrush = "#2B2521"
                MutedBrush = "#786C63"; SageBrush = "#A65F45"; PaleSageBrush = "#F1DDD2"
                LineBrush = "#E7DCD1"; InputBrush = "#FFFDFC"; ButtonTextBrush = "#FFFFFF"; FrameBrush = "#E8DED4"
            }
        },
        [pscustomobject]@{
            Name = "c-clear-mint"
            Palette = @{
                CanvasBrush = "#F4F8F5"; SurfaceBrush = "#E6EFEA"; InkBrush = "#1F2924"
                MutedBrush = "#66756D"; SageBrush = "#2F765D"; PaleSageBrush = "#D9ECE2"
                LineBrush = "#D8E3DD"; InputBrush = "#FFFFFF"; ButtonTextBrush = "#FFFFFF"; FrameBrush = "#D9E4DE"
            }
        }
    )

    foreach ($option in $colorOptions) {
        foreach ($entry in $option.Palette.GetEnumerator()) {
            Set-ThemeBrush -Name $entry.Key -Color $entry.Value
        }
        $window.UpdateLayout()
        Export-WindowImage -Path (Join-Path $optionsDir "color-$($option.Name).png")
    }

    $iconOptions = @(
        [pscustomobject]@{ Name = "1-minimal"; Moon = [char]0x25D0; Sun = [char]0x263C },
        [pscustomobject]@{ Name = "2-celestial"; Moon = [char]0x263D; Sun = [char]0x2600 },
        [pscustomobject]@{ Name = "3-symbolic"; Moon = [char]0x25D2; Sun = [char]0x2726 }
    )
    foreach ($option in $iconOptions) {
        foreach ($theme in @("light", "dark")) {
            Apply-Theme -Theme $theme
            $ThemeButton.Content = if ($theme -eq "light") { $option.Moon } else { $option.Sun }
            $window.UpdateLayout()
            Export-WindowImage -Path (Join-Path $optionsDir "icon-$($option.Name)-$theme.png")
        }
    }

    $window.Close()
    Write-Output "Mindful Timer design options rendered successfully."
    exit 0
}

if ($RenderPreview) {
    $previewDir = Join-Path $script:AppDir "preview"
    if (-not (Test-Path -LiteralPath $previewDir)) {
        New-Item -ItemType Directory -Path $previewDir | Out-Null
    }
    $window.Show()
    $window.Activate() | Out-Null

    function Render-ThemePreview {
        param(
            [string]$Theme,
            [string]$Prefix
        )
        Apply-Theme -Theme $Theme
        Reset-ForNextSession
        $PurposeInput.Text = $script:Strings.previewPurpose
        $RestoreHint.Text = ""
        $window.UpdateLayout()
        Export-WindowImage -Path (Join-Path $previewDir "$Prefix-01-start.png")

        Start-Session
        $TimerText.Text = "08:42"
        $window.UpdateLayout()
        Export-WindowImage -Path (Join-Path $previewDir "$Prefix-02-active-compact.png")

        $NotesInput.Text = $script:Strings.previewNotes
        $script:NotesExpanded = $true
        Set-TimerLayout
        $TimerText.Text = "08:42"
        $window.UpdateLayout()
        Export-WindowImage -Path (Join-Path $previewDir "$Prefix-03-active-expanded.png")

        $script:Stopwatch.Stop()
        $script:IsActive = $false
        $DoneSummary.Text = $script:Strings.previewPurpose
        $DoneMeta.Text = "08:42$($script:Strings.separator)$([DateTime]::Now.ToString("yyyy-MM-dd HH:mm"))"
        Set-DoneLayout
        $window.UpdateLayout()
        Export-WindowImage -Path (Join-Path $previewDir "$Prefix-04-done.png")

        foreach ($path in @($script:DraftPath, $script:CurrentNotePath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }

    Render-ThemePreview -Theme "light" -Prefix "light"
    Render-ThemePreview -Theme "dark" -Prefix "dark"

    $previewItems = @(
        [pscustomobject]@{
            Purpose = $script:Strings.previewPurpose
            ListMeta = $script:Strings.ongoingMeta
            Kind = $script:Strings.currentDraftKind
            DetailMeta = "2026-08-02 10:24"
            Notes = $script:Strings.previewNotes
            SavedHint = $script:Strings.autoSavedHint
            SearchText = "$($script:Strings.previewPurpose) $($script:Strings.previewNotes)".ToLowerInvariant()
            CopyText = "$($script:Strings.previewPurpose)`r`n`r`n$($script:Strings.previewNotes)"
        },
        [pscustomobject]@{
            Purpose = $script:Strings.previewPurpose2
            ListMeta = "2026-08-01$($script:Strings.separator)18:36"
            Kind = $script:Strings.sessionKind
            DetailMeta = "2026-08-01 22:10$($script:Strings.separator)18:36"
            Notes = $script:Strings.previewNotes2
            SavedHint = $script:Strings.archivedHint
            SearchText = "$($script:Strings.previewPurpose2) $($script:Strings.previewNotes2)".ToLowerInvariant()
            CopyText = "$($script:Strings.previewPurpose2)`r`n`r`n$($script:Strings.previewNotes2)"
        },
        [pscustomobject]@{
            Purpose = $script:Strings.previewPurpose3
            ListMeta = "2026-07-31$($script:Strings.separator)12:08"
            Kind = $script:Strings.sessionKind
            DetailMeta = "2026-07-31 19:42$($script:Strings.separator)12:08"
            Notes = $script:Strings.previewNotes3
            SavedHint = $script:Strings.archivedHint
            SearchText = "$($script:Strings.previewPurpose3) $($script:Strings.previewNotes3)".ToLowerInvariant()
            CopyText = "$($script:Strings.previewPurpose3)`r`n`r`n$($script:Strings.previewNotes3)"
        }
    )

    foreach ($libraryTheme in @("light", "dark")) {
        Apply-Theme -Theme $libraryTheme
        $libraryPreview = New-NotesLibraryWindow -PreviewItems $previewItems
        $libraryPreview.Show()
        $libraryPreview.UpdateLayout()
        Export-WindowImage -Path (Join-Path $previewDir "$libraryTheme-05-notes-library.png") -TargetWindow $libraryPreview
        $libraryPreview.Close()
    }
    $window.Close()
    Write-Output "Mindful Timer and Notes Library light/dark previews rendered successfully."
    exit 0
}

$window.ShowDialog() | Out-Null
