# Computes the GitHub diff anchor for one or more file paths.
#
# GitHub anchors each file on a PR's Files tab as #diff-<sha256 of the repo-relative
# path>. Appending R<n> targets line n on the right (new) side of the diff; L<n>
# targets the left (old) side.
#
# Call this once with every changed path, then build per-chunk links by appending
# R<line> or L<line> to the anchor for that file.
#
# Examples:
#   pwsh -File diff-anchors.ps1 -Path "src/App.fs","src/Types.fs"
#   pwsh -File diff-anchors.ps1 -Owner ntwilson -Repo my-repo -Pr 123 -Path "src/App.fs"

param (
  [Parameter(Mandatory)][String[]]$Path,
  [String]$Owner,
  [String]$Repo,
  [Int]$Pr
)

# `pwsh -File` passes every argument as a literal string, so `-Path "a","b"` arrives as
# the single string 'a,b'. Split on commas so both invocation styles behave the same.
$paths = $Path | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  foreach ($p in $paths) {
    # GitHub hashes the forward-slash repo-relative path exactly as it appears in the diff.
    $normalized = $p -replace '\\', '/'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hex = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()

    if ($Owner -and $Repo -and $Pr) {
      Write-Host "$normalized -> https://github.com/$Owner/$Repo/pull/$Pr/files#diff-$hex"
    }
    else {
      Write-Host "$normalized -> diff-$hex"
    }
  }
}
finally {
  $sha.Dispose()
}
