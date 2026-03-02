param (
  [String]$url
)

$comments = gh api $url --paginate | ConvertFrom-Json
foreach ($c in $comments) {
  $line = if ($c.line) { $c.line } else { $c.original_line }
  Write-Host "FILE: $($c.path) | LINE: $line | USER: $($c.user.login)"
  $body = if ($c.body.Length -gt 400) { $c.body.Substring(0, 400) } else { $c.body }
  Write-Host "BODY: $body"
  Write-Host "---"
}

