# Prints an exact, numbered line range from a file at a specific commit.
#
# Use this before writing a `suggestion` block. A suggested change replaces the
# anchored lines verbatim, so the replacement has to be built against the precise
# text - including indentation - of the revision being reviewed. Reading the working
# tree is not good enough: it may be a different commit, or dirty.
#
# Examples:
#   pwsh -File show-lines.ps1 -Sha e7fbdb0 -Path "src/App.fs" -Start 38 -End 45
#   pwsh -File show-lines.ps1 -Sha e7fbdb0 -Path "src/App.fs" -Start 42 -Raw

param (
  [Parameter(Mandatory)][String]$Sha,
  [Parameter(Mandatory)][String]$Path,
  [Parameter(Mandatory)][Int]$Start,
  [Int]$End,
  # -Raw prints the lines with no numbering, ready to paste into a suggestion block.
  [Switch]$Raw
)

$ErrorActionPreference = 'Stop'

if (-not $End) { $End = $Start }
if ($End -lt $Start) {
  Write-Error "-End ($End) must be >= -Start ($Start)"
  exit 1
}

$normalized = $Path -replace '\\', '/'
$content = git show "${Sha}:${normalized}" 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host $content
  Write-Error "Could not read ${normalized} at ${Sha}. For a PR from a fork, fetch the head commit first: git fetch origin pull/<N>/head"
  exit 1
}

$lines = @($content -split "`r?`n")
if ($Start -gt $lines.Count) {
  Write-Error "-Start ($Start) is past the end of the file ($($lines.Count) lines)"
  exit 1
}
if ($End -gt $lines.Count) {
  Write-Host "note: -End ($End) is past the end of the file; clamping to $($lines.Count)"
  $End = $lines.Count
}

for ($n = $Start; $n -le $End; $n++) {
  $text = $lines[$n - 1]
  if ($Raw) {
    # No numbering, no trimming - leading whitespace is significant to a suggestion.
    Write-Output $text
  }
  else {
    Write-Host ("{0,6}  {1}" -f $n, $text)
  }
}
