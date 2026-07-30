# Submits a batch of inline PR review comments as a single review.
#
# Reads a JSON array of queued comments and posts them in one API call, so
# reviewers get one notification rather than one per comment.
#
# Queue file format - a JSON array where each entry is:
#   {
#     "path":       "src/App.fs",   # required, repo-relative
#     "line":       42,             # required, line number on `side` of the diff
#     "body":       "...",          # required, markdown
#     "side":       "RIGHT",        # optional, RIGHT (default) or LEFT
#     "start_line": 38,             # optional, for a multi-line comment ending at `line`
#     "start_side": "RIGHT"         # optional, defaults to `side`
#   }
#
# The commented line MUST appear in the PR's diff. Commenting on an unchanged line
# outside any hunk's context returns HTTP 422.
#
# Examples:
#   pwsh -File submit-review.ps1 -Owner o -Repo r -Pr 123 -CommentsFile q.json -DryRun
#   pwsh -File submit-review.ps1 -Owner o -Repo r -Pr 123 -CommentsFile q.json `
#     -Body "Walkthrough notes" -CommitId abc123

param (
  [Parameter(Mandatory)][String]$Owner,
  [Parameter(Mandatory)][String]$Repo,
  [Parameter(Mandatory)][Int]$Pr,
  [Parameter(Mandatory)][String]$CommentsFile,
  [ValidateSet('COMMENT', 'REQUEST_CHANGES', 'APPROVE')][String]$Event = 'COMMENT',
  [String]$Body = '',
  [String]$CommitId = '',
  [Switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CommentsFile)) {
  Write-Error "Comments file not found: $CommentsFile"
  exit 1
}

$queued = @(Get-Content $CommentsFile -Raw | ConvertFrom-Json)
if ($queued.Count -eq 0) {
  Write-Error "No comments queued in $CommentsFile - nothing to submit."
  exit 1
}

# Validate before touching the network: a partial batch is worse than no batch.
$problems = @()
for ($i = 0; $i -lt $queued.Count; $i++) {
  $c = $queued[$i]
  if (-not $c.path) { $problems += "comment[$i]: missing 'path'" }
  if (-not $c.line) { $problems += "comment[$i]: missing 'line'" }
  if (-not $c.body) { $problems += "comment[$i]: missing 'body'" }
  if ($c.side -and $c.side -notin @('LEFT', 'RIGHT')) {
    $problems += "comment[$i]: 'side' must be LEFT or RIGHT, got '$($c.side)'"
  }
  if ($c.start_line -and $c.start_line -gt $c.line) {
    $problems += "comment[$i]: 'start_line' ($($c.start_line)) must be <= 'line' ($($c.line))"
  }

  # Suggested changes have extra rules: GitHub can only apply them to the new side of
  # the diff, and only one per comment.
  if ($c.body -and $c.body -match '```suggestion') {
    $side = if ($c.side) { $c.side } else { 'RIGHT' }
    if ($side -eq 'LEFT') {
      $problems += "comment[$i]: " + 'a ```suggestion block cannot be applied to a LEFT-side (deleted) line - anchor it to the new side'
    }
    $opens = ([regex]::Matches($c.body, '(?m)^\s*```suggestion')).Count
    $fences = ([regex]::Matches($c.body, '(?m)^\s*```')).Count
    if ($opens -gt 1) {
      $problems += "comment[$i]: " + "$opens suggestion blocks in one comment - GitHub applies only one per comment, so split them"
    }
    if ($fences -lt ($opens * 2)) {
      $problems += "comment[$i]: " + 'unterminated ```suggestion block (missing closing fence)'
    }
  }
}
if ($problems.Count -gt 0) {
  Write-Error ("Queue file is invalid:`n  " + ($problems -join "`n  "))
  exit 1
}

$comments = foreach ($c in $queued) {
  $entry = [ordered]@{
    path = $c.path -replace '\\', '/'
    line = [int]$c.line
    side = if ($c.side) { $c.side } else { 'RIGHT' }
    body = $c.body
  }
  if ($c.start_line) {
    $entry['start_line'] = [int]$c.start_line
    $entry['start_side'] = if ($c.start_side) { $c.start_side } else { $entry['side'] }
  }
  $entry
}

$payload = [ordered]@{
  event    = $Event
  comments = @($comments)
}
if ($Body) { $payload['body'] = $Body }
# Pinning the commit keeps comments anchored to the code that was actually reviewed.
# If the PR has been pushed to since, GitHub marks them outdated rather than silently
# anchoring them to different lines.
if ($CommitId) { $payload['commit_id'] = $CommitId }

$json = $payload | ConvertTo-Json -Depth 6

if ($DryRun) {
  Write-Host "DRY RUN - would POST to repos/$Owner/$Repo/pulls/$Pr/reviews:"
  Write-Host $json
  Write-Host ""
  Write-Host "$($comments.Count) comment(s), event=$Event"
  exit 0
}

$tmp = [System.IO.Path]::GetTempFileName()
try {
  # -Encoding utf8NoBOM: gh chokes on a BOM in --input.
  Set-Content -Path $tmp -Value $json -Encoding utf8NoBOM
  $result = gh api --method POST "repos/$Owner/$Repo/pulls/$Pr/reviews" --input $tmp 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host $result
    Write-Error @"
Failed to submit review (exit $LASTEXITCODE).

A 422 usually means a commented line is not part of the diff - GitHub only accepts
inline comments on added, removed, or nearby-context lines. Check the 'line' and
'side' of each queued comment against the actual hunks.
"@
    exit 1
  }
  $review = $result | ConvertFrom-Json
  Write-Host "Submitted review $($review.id) with $($comments.Count) comment(s): $($review.html_url)"
}
finally {
  Remove-Item $tmp -ErrorAction SilentlyContinue
}
