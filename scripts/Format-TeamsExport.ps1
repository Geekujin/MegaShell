<#
.SYNOPSIS
	Converts Mimecast Teams export into a readable conversation.
	
.DESCRIPTION
	Reads messageevents.csv file output from Mimecast and exports contents to a human readable HTML file.
	The output file shows 2-person conversation in different colours, or single colour for group chats.
	Colours for the dark and light themes can be changed in the [CONFIG] section of the code.
	
.PARAMETER CSVPath
	MANDATORY. Specifies the full path and filename of the csv file.
	
.PARAMETER AttachmentsDir	
	OPTIONAL. Specifies a folder containing the attachments if different from the original.
	Defaults to .\attachment
	  
.PARAMETER TranscriptName
	OPTIONAL. Gives the output file a unique name. Produces filename of TranscriptName_transcript.html
	Defaults to CSVFilename_transcript.html
	  
.PARAMETER DarkTheme
	OPTIONAL. Enables the dark theme for the output file.

.PARAMETER CreateZip
    OPTIONAL. If specified, zips the resulting HTML and the Attachments folder into a single archive.
	
.EXAMPLE
	Format-TeamsExport -CSVPath C:\users\messageevents.csv
	Convert the file using the default options

.EXAMPLE
	Format-TeamsExport -CSVPath C:\users\messageevents.csv -DarkTheme
	Convert the file and use the dark mode theme

.EXAMPLE
	Format-TeamsExport -CSVPath C:\users\messageevents.csv -TranscriptName TH13 -CreateZip
	Convert the file, save as TH13_transcript.html, and create TH13_transcript.zip

.NOTES
    Version: 2.0
	Author: Marc Jones
#>

Param(
  [Parameter(Mandatory=$false)] [string]$CsvPath,

  # Optional overrides; if omitted they are derived from the CSV folder
  [string]$AttachmentsDir,
  [string]$OutFile,
  [string]$TranscriptName,

  # Enable Dark Mode
  [switch]$DarkTheme,

  # Save as Zip
  [switch]$CreateZip
)

# [CONFIG]
# Theme map - Light theme is used by default unless -DarkTheme switch is used
if ($DarkTheme) {
  $theme = @{
    Background = "#0b0c0e"; 
    Panel = "#121417"; 
    Left = "#1e293b"; 
    Right = "#14532d";
    Text = "#e5e7eb"; 
    Meta = "#9ca3af"; 
    Chip = "#334155"; 
    ChipMissing = "#7f1d1d";
    Divider = "#374151"; 
    Link = "#93c5fd"
  }
} else {
  $theme = @{
    Background = "#f3f4f6"; 
    Panel = "#ffffff"; 
    Left = "#e5e7eb"; 
    Right = "#d1fae5";
    Text = "#111827"; 
    Meta = "#6b7280"; 
    Chip = "#d1d5db"; 
    ChipMissing = "#fecaca";
    Divider = "#cbd5e1"; 
    Link = "#2563eb"
  }
}

# Effective colours
$BackgroundColor   = $theme.Background
$PanelColor        = $theme.Panel
$LeftColor         = $theme.Left
$RightColor        = $theme.Right
$TextColor         = $theme.Text
$MetaColor         = $theme.Meta
$ChipColor         = $theme.Chip
$ChipMissingColor  = $theme.ChipMissing
$DividerColor      = $theme.Divider
$LinkColor         = $theme.Link

# Displays the Comment Based Help block
function Show-ScriptHelp {
    param(
        [string]$Path = $PSCommandPath
    )

    # Read all content of the script file
    $Content = Get-Content -Path $Path

    # Find the start and end of the Comment-Based Help block
    $StartLine = 0
    $EndLine = 0

    for ($i = 0; $i -lt $Content.Length; $i++) {
        if ($Content[$i].Trim() -eq '<#') {
            $StartLine = $i + 1
        } elseif ($Content[$i].Trim() -eq '#>') {
            $EndLine = $i - 1
            break
        }
    }

    if ($StartLine -le $EndLine) {
        Write-Host "`nAbout this script`n" -ForegroundColor Yellow
        # Output the content line by line, removing leading whitespace
        $Content[$StartLine..$EndLine] | ForEach-Object {
            $Line = $_.TrimStart()
            if ($Line.StartsWith('.')) {
                # Highlight Section Headers (.SYNOPSIS, .PARAMETER, etc.)
                 Write-Host $Line -ForegroundColor Cyan
            } elseif ($Line.StartsWith('#')) {
                # Skips printing of lines beginning with '#'
            } else {
                # Display other content (empty lines, etc.)
                Write-Host $Line
            }
        }
        Write-Host ""
    } else {
        Write-Host "[ERROR] Could not parse help block." -ForegroundColor Red
    }
}

# If no CSVPath is specified, show the help text and exit.
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    Show-ScriptHelp
    exit
}

# Check path of CSV file, and extract the base path if it exists.
# BaseDir is also used as the root for the attachment subfolder and the location of the outfile
if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "CSV not found: $CsvPath"
}
$csvItem     = Get-Item -LiteralPath $CsvPath
$CsvFullPath = $csvItem.FullName
$BaseDir     = $csvItem.DirectoryName
$BaseName    = [System.IO.Path]::GetFileNameWithoutExtension($csvItem.Name)



# Use filename provided in -TranscriptName for the OutFile, else default to CSV base name
if (-not $PSBoundParameters.ContainsKey('TranscriptName') -or [string]::IsNullOrWhiteSpace($TranscriptName)) {
  $TranscriptName = $BaseName
}

# Defaults based on CSV location, unless overriden
if (-not $PSBoundParameters.ContainsKey('AttachmentsDir') -or [string]::IsNullOrWhiteSpace($AttachmentsDir)) {
  $AttachmentsDir = Join-Path -Path $BaseDir -ChildPath 'attachments'
  # graceful fallback to singular if that folder exists instead
  if (-not (Test-Path -LiteralPath $AttachmentsDir)) {
    $singular = Join-Path -Path $BaseDir -ChildPath 'attachment'
    if (Test-Path -LiteralPath $singular) { $AttachmentsDir = $singular }
  }
}

if (-not $PSBoundParameters.ContainsKey('OutFile') -or [string]::IsNullOrWhiteSpace($OutFile)) {
  # Use TranscriptName as the base for the default file name
  $safeName = ($TranscriptName -replace '[\\/:*?"<>|]+','_').Trim()
  if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = $BaseName }
  $OutFile = Join-Path -Path $BaseDir -ChildPath ("{0}_transcript.html" -f $safeName)
}

# Ensure output directory exists (needed for relative path calculation)
$outDir = Split-Path -Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
# Resolve outDir to full path to ensure relative URI calc works
$outDir = (Resolve-Path $outDir).Path

# Displays the filepaths for all files
Write-Host "`nUsing the following file locations:"
Write-Host "CSV:           $CsvFullPath"
Write-Host "Attachments:   $AttachmentsDir"
Write-Host "Output HTML:   $OutFile"
Write-Host " "



# Helpers
Add-Type -AssemblyName System.Web

function Fix-OffsetIso([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return $s }
  return ($s -replace '([+-]\d{2})(\d{2})$', '$1:$2')  # +0100 -> +01:00
}

function Parse-Date([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return $null }
  $s = Fix-OffsetIso $s
  try { return [DateTime]::Parse($s) } catch { return $null }
}

function HtmlEnc([string]$s){ return [System.Web.HttpUtility]::HtmlEncode($s) }

function DeMojibake([string]$s){
  if([string]::IsNullOrEmpty($s)){ return "" }
  try {
    return [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::GetEncoding(28591).GetBytes($s))
  } catch { return $s }
}

function ConvertTo-SafeHtml([string]$inputHtml) {
    if ([string]::IsNullOrWhiteSpace($inputHtml)) { return "" }

    # Decode to get raw tags (Mimecast often encodes the source)
    $raw = [System.Web.HttpUtility]::HtmlDecode($inputHtml)

    # Define HTML tags to KEEP.
    $formattingTags = @('b', 'strong', 'i', 'em', 'u', 'br', 'p', 'span', 'div', 'ul', 'ol', 'li', 'font', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td')
    $systemTags     = @('emoji', 'attachment', 'at') 

    # Regex MatchEvaluator to process every tag
    $evaluator = { param($match)
        $fullTag   = $match.Value
        $tagName   = $match.Groups[1].Value.ToLower()
        $isClosing = $fullTag.StartsWith("</")

        if ($formattingTags -contains $tagName) {
            # Valid formatting tags are stripped of attributes (no style/onclick) to be safe.
            if ($isClosing) { return "</$tagName>" }
            return "<$tagName>"
        } 
        elseif ($systemTags -contains $tagName) {
            # System tags need preserved attributes (id="...") to work properly.
            return $fullTag
        } 
        else {
            # Invalid/Dangerous tags (e.g. <script>, <object>, <iframe>) are encoded to display as harmless text.
            return [System.Web.HttpUtility]::HtmlEncode($fullTag)
        }
    }

    # Regex to find tags: </?tagName attributes...>
    return [regex]::Replace($raw, '</?([a-z0-9]+)[^>]*>', $evaluator, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# Maps Teams emoji from the <emoji id="..."> field
$EmojiMap = @{
  "smile"="🙂"; "thumbsup"="👍"; "thumbsdown"="👎"; "heart"="❤️";
  "laugh"="😆"; "cry"="😢"; "clap"="👏"; "shrug"="🤷"; "wink"="😉"
}
function Replace-Emoji([string]$s){
  if([string]::IsNullOrEmpty($s)){ return "" }
  return [regex]::Replace($s, '<\s*emoji\b([^>]*)>\s*(?:</\s*emoji\s*>)?', {
    param($m)
    $attrs = $m.Groups[1].Value
    $id    = [regex]::Match($attrs, 'id="([^"]+)"', 'IgnoreCase').Groups[1].Value.ToLower()
    $alt   = [regex]::Match($attrs, 'alt="([^"]+)"', 'IgnoreCase').Groups[1].Value
    $title = [regex]::Match($attrs, 'title="([^"]+)"', 'IgnoreCase').Groups[1].Value
    if($EmojiMap.ContainsKey($id)) { return $EmojiMap[$id] }
    if(-not [string]::IsNullOrEmpty($alt)) { return (DeMojibake $alt) }
    if(-not [string]::IsNullOrEmpty($title) -and $EmojiMap.ContainsKey($title.ToLower())) { return $EmojiMap[$title.ToLower()] }
    if(-not [string]::IsNullOrEmpty($title)){ return "($title)" }
    return ""
  })
}

function Replace-Mentions([string]$s){
  if([string]::IsNullOrEmpty($s)){ return "" }
  # Pattern: <at id="...">Name</at>
  return [regex]::Replace($s, '<\s*at\b[^>]*>(.*?)</\s*at\s*>', {
    param($m)
    $text = $m.Groups[1].Value
    return "<span class=""mention"">$text</span>" 
  })
}

# Generates a relative path (e.g. attachments/img.png) instead of file://
function Get-RelativeUri([string]$basePath, [string]$targetPath){
    try {
        # Ensure base path ends in slash for Uri class to treat it as a container
        if(-not $basePath.EndsWith('\')) { $basePath += '\' }
        $baseUri = New-Object System.Uri($basePath)
        $targetUri = New-Object System.Uri($targetPath)
        return $baseUri.MakeRelativeUri($targetUri).ToString()
    } catch {
        return "file:///" + ($targetPath -replace '\\','/') -replace ' ', '%20'
    }
}

# Identifies attachment location from filename and ensures attachments resolved are actually INSIDE the attachments directory.
function Resolve-Attachment([string]$id, [string]$name, [string]$attachmentsDir){
  if(-not (Test-Path $attachmentsDir)){ return $null }
  
  # Get the true path of the attachments root
  $root = (Resolve-Path $attachmentsDir).Path
  $target = $null
  
  if(-not [string]::IsNullOrWhiteSpace($id)){
    $pattern = "$id*"
    $target = Get-ChildItem -Path $root -File -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  
  if($null -eq $target -and -not [string]::IsNullOrWhiteSpace($name)){
    $cand = Join-Path $root $name
    $full = $null
    try { $full = (Resolve-Path $cand -ErrorAction Stop).Path } catch { $full = $null }
    
    # Check: Is the resolved file path starting with the root path?
    if ($null -ne $full -and $full.StartsWith($root)) {
        $target = Get-Item $full
    }
  }
  return $target
}

# Replace attachment placeholders in text with clickable links. Uses $htmlDir to calculate relative path
function Replace-AttachPlaceholders([string]$s, [string]$attachmentsDir, [string]$htmlDir){
  if([string]::IsNullOrEmpty($s)){ return "" }
  return [regex]::Replace($s, '<\s*attachment\s+id="([^"]+)"\s*/?\s*>\s*(?:</\s*attachment\s*>)?', {
    param($m)
    $id = $m.Groups[1].Value
    $f = Resolve-Attachment $id $null $attachmentsDir
    if($null -ne $f){
      $disp = HtmlEnc $f.Name
      # Calculate relative path
      $href = Get-RelativeUri $htmlDir $f.FullName
      return "<a class=""attach-chip"" href=""$href"" target=""_blank"">📎 $disp</a>"
    } else {
      $safe = HtmlEnc $id
      return "<span class=""attach-chip missing"">📎 $safe</span>"
    }
  })
}


# Read CSV and shape rows
$rows = Import-Csv -Path $CsvFullPath

# Column names from CSV
$COL = @{
  Sender            = "Sender"
  DateTime          = "Date/Time"
  Type              = "Type"
  Content           = "Message content"
  Event             = "Event"
  AttachmentName    = "Attachment name"
  AttachmentId      = "Attachment Id"
  AttachmentStatus  = "Attachment Status"
}

# Import data from each row and set variable
$items = @()
foreach($r in $rows){
  $sender = $r."$($COL.Sender)"
  $dt     = Parse-Date $r."$($COL.DateTime)"
  $type   = ($r."$($COL.Type)" -as [string]); if($null -ne $type){ $type = $type.ToLower() } else { $type = "" }
  $body   = $r."$($COL.Content)"
  $event  = $r."$($COL.Event)"
  $aname  = $r."$($COL.AttachmentName)"
  $aid    = $r."$($COL.AttachmentId)"

  $items += New-Object psobject -Property @{
    Sender = $sender
    DT     = $dt
    Type   = $type
    Body   = $body
    Event  = $event
    AName  = $aname
    AId    = $aid
  }
}

$items = $items | Sort-Object -Property DT, Sender # Sort by date ascending, and then by sender

# If there are two parties, use left/right message format. Otherwise all messages display on the left
$senders = $items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sender) } | Select-Object -ExpandProperty Sender -Unique
$sideMap = @{}
if($senders.Count -eq 2){ $sideMap[$senders[0]]="left"; $sideMap[$senders[1]]="right" } else { foreach($s in $senders){ $sideMap[$s]="left" } }


# [Build HTML for the output file]

# Create the CSS style based on colours set at start of script and assign to CSS variable
$css = @"
<style>
:root {
  --bg:$BackgroundColor; --panel:$PanelColor; --left:$LeftColor; --right:$RightColor;
  --text:$TextColor; --meta:$MetaColor; --chip:$ChipColor; --chip-missing:$ChipMissingColor;
  --divider:$DividerColor; --link:$LinkColor;
}
* { box-sizing:border-box; }
body { margin:0; padding:2rem 1rem; background:var(--bg); color:var(--text);
  font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,"Helvetica Neue",Arial,"Apple Color Emoji","Segoe UI Emoji"; }
.container { max-width:980px; margin:0 auto; background:var(--panel); border-radius:12px; padding:1rem 1rem 2rem; }

/* Use text variable so LightTheme shows dark heading text */
h1 { font-size:18px; margin:0 0 1rem 0; padding:.5rem .75rem; border-bottom:1px solid var(--divider); color:var(--text); }

.date-divider { text-align:center; margin:1rem 0; color:var(--meta); position:relative; }
.date-divider:before, .date-divider:after { content:""; position:absolute; top:50%; width:40%; height:1px; background:var(--divider); }
.date-divider:before{ left:0 } .date-divider:after{ right:0 }
.msg { display:flex; gap:.5rem; margin:.5rem 0; }
.msg.left { justify-content:flex-start; } .msg.right { justify-content:flex-end; }
.bubble { max-width:80%; padding:.6rem .8rem; border-radius:12px; white-space:normal; word-wrap:break-word; overflow-wrap:anywhere; }
.left .bubble  { background: var(--left); }
.right .bubble { background: var(--right); }
.meta { font-size:12px; color:var(--meta); margin-bottom:.35rem; }
.content a { color:var(--link); }
.content p { margin:.25rem 0; }
.system { font-style:italic; color:var(--meta); }
.attach-chip { display:inline-block; background:var(--chip); border-radius:999px; padding:.2rem .55rem; margin:.15rem .15rem 0 0; font-size:12px; white-space:nowrap; }
.attach-chip.missing { background:var(--chip-missing); }
.attachment-preview { display:block; margin-top:.4rem; max-width:320px; border-radius:8px; }

/* Mentions */
.mention { font-weight: 700; color: var(--link); }

/* Table Styles */
table { border-collapse: collapse; width: 100%; margin: 0.5rem 0; font-size: 0.9em; background: rgba(0,0,0,0.05); }
th, td { border: 1px solid var(--divider); padding: 4px 8px; text-align: left; vertical-align: top; }
th { background: var(--bg); font-weight: 600; }
</style>
"@


# Create HTML document
$html = New-Object System.Collections.Generic.List[string]
$html.Add('<!DOCTYPE html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
$html.Add("<title>Teams Chat Transcript - $(HtmlEnc $TranscriptName)</title>")
$html.Add($css)
$html.Add('<body><div class="container">')
$html.Add("<h1>Teams Chat Transcript - $(HtmlEnc $TranscriptName)</h1>")

$lastDate = $null
foreach($it in $items){
  $day = $null; if($null -ne $it.DT){ $day = $it.DT.Date }
  if($null -ne $day -and ($null -eq $lastDate -or $day -ne $lastDate)){
    $html.Add("<div class=""date-divider"">$($day.ToString('dddd, dd MMMM yyyy'))</div>")
    $lastDate = $day
  }

  $side = "left"; if($sideMap.ContainsKey($it.Sender)){ $side = $sideMap[$it.Sender] }
  $dtText = if($null -ne $it.DT){ $it.DT.ToString('ddd, dd MMM yyyy HH:mm') } else { "" }
  $meta = ""
  if(-not [string]::IsNullOrWhiteSpace($it.Sender)){ $meta = $it.Sender }
  if(-not [string]::IsNullOrWhiteSpace($dtText)){ $meta = "$meta • $dtText" }

  $html.Add("<div class=""msg $side""><div class=""bubble""><div class=""meta"">$(HtmlEnc $meta)</div>")

  if($it.Type -eq "message"){
    $s = $it.Body
    $s = ConvertTo-SafeHtml $s
    $s = Replace-Emoji $s
	$s = Replace-Mentions $s
    # Pass $outDir so we can calculate relative paths
    $s = Replace-AttachPlaceholders $s $AttachmentsDir $outDir
    $html.Add("<div class=""content"">$s</div>")
  }
  elseif($it.Type -eq "attachment"){
    $file = Resolve-Attachment $it.AId $it.AName $AttachmentsDir
    if($null -ne $file){
      $disp = HtmlEnc $file.Name
      # Calculate relative path
      $href = Get-RelativeUri $outDir $file.FullName
      $chip = "<a class=""attach-chip"" href=""$href"">📎 $disp</a>"
      $preview = ""
      switch ($file.Extension.ToLower()) {
        ".png" { $preview = "<img class=""attachment-preview"" src=""$href"" alt=""$disp"">" }
        ".jpg" { $preview = "<img class=""attachment-preview"" src=""$href"" alt=""$disp"">" }
        ".jpeg"{ $preview = "<img class=""attachment-preview"" src=""$href"" alt=""$disp"">" }
        ".gif" { $preview = "<img class=""attachment-preview"" src=""$href"" alt=""$disp"">" }
        ".webp"{ $preview = "<img class=""attachment-preview"" src=""$href"" alt=""$disp"">" }
      }
      $html.Add("<div class=""content system"">Shared an attachment: $chip $preview</div>")
    } else {
      $label = if(-not [string]::IsNullOrWhiteSpace($it.AName)){ $it.AName } elseif(-not [string]::IsNullOrWhiteSpace($it.AId)){ $it.AId } else { "Attachment" }
      $label = HtmlEnc $label
      $html.Add("<div class=""content system"">Shared an attachment: <span class=""attach-chip missing"">📎 $label</span></div>")
    }
  }
  else {
    $evt = if([string]::IsNullOrWhiteSpace($it.Event)){ "(event)" } else { $it.Event }
    $evt = HtmlEnc $evt
    $html.Add("<div class=""content system"">$evt</div>")
  }

  $html.Add("</div></div>")
}

$html.Add('<div class="footer-note" style="margin-top:1rem;font-size:12px;color:#9ca3af;border-top:1px dashed #374151;padding-top:.5rem;">Generated locally. Links point to files in your attachments folder.</div>')
$html.Add('</div></body></html>')

# Write output file
$html -join "`r`n" | Out-File -FilePath $OutFile -Encoding utf8
Write-Host "✅ File saved: $OutFile"

# Create Zip if flag specified
if ($CreateZip) {
    $zipName = [System.IO.Path]::GetFileNameWithoutExtension($OutFile) + ".zip"
    $zipPath = Join-Path $outDir $zipName
    
    # We zip the HTML file AND the attachments directory (if it exists)
    $toZip = @($OutFile)
    if (Test-Path $AttachmentsDir) { $toZip += $AttachmentsDir }
    
    Compress-Archive -Path $toZip -DestinationPath $zipPath -Force
    Write-Host "`n📦 Zip created: $zipPath"
}

Write-Host "`n🌍 Launching browser window!"

# Auto-launch the result
try { Start-Process -FilePath $OutFile | Out-Null }
catch { try { Invoke-Item -LiteralPath $OutFile } catch { Write-Warning "Could not launch $($OutFile): $_" } }