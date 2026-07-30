#!/usr/bin/env pwsh
# Fetch PR information using GitHub CLI
# Usage: ./fetch-pr-info.ps1 <PR_NUMBER> [BASE_BRANCH]

param(
    [Parameter(Mandatory=$true)]
    [int]$PRNumber,

    [Parameter(Mandatory=$false)]
    [string]$BaseBranch = ""
)

# Check if gh CLI is available
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) not found. Install from: https://cli.github.com/"
    exit 1
}

Write-Host "=== PR Information ===" -ForegroundColor Cyan
gh pr view $PRNumber --json number,title,body,baseRefName,headRefName,author,createdAt

Write-Host "`n=== Changed Files ===" -ForegroundColor Cyan
gh pr view $PRNumber --json files --jq '.files[] | "\(.path) (\(.additions)+/\(.deletions)-)"'

Write-Host "`n=== Diff ===" -ForegroundColor Cyan
if ($BaseBranch) {
    Write-Host "Using custom base branch: $BaseBranch" -ForegroundColor Yellow
    $headBranch = gh pr view $PRNumber --json headRefName --jq '.headRefName'
    git diff "$BaseBranch...$headBranch"
} else {
    gh pr diff $PRNumber
}
