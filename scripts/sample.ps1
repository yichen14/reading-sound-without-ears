# Draw a seeded random sample of questions. Writes:
#   out\questions.json  - what the answerer is allowed to see (no answers, no transcripts)
#   out\answer_key.json - ground truth, only read by score.ps1
#   out\downloads.json  - audio sources to fetch
# Prints only counts.
param([string]$Root, [int]$Seed = 20261110, [int]$MiniPerTask = 20, [int]$ProPerCat = 10)
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)
$letters = 'ABCDEFGHIJKLMNOP'

$questions = New-Object System.Collections.ArrayList
$key = New-Object System.Collections.ArrayList
$dl = New-Object System.Collections.ArrayList

# ---- MMAU test-mini ----
$mini = Get-Content (Join-Path $Root 'data\mmau_mini\rows_full.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$miniItems = foreach ($x in $mini) {
    $a = $x.row.other_attributes | ConvertFrom-Json
    [pscustomobject]@{ idx = $x.row_idx; row = $x.row; attr = $a }
}
$s = $Seed
foreach ($task in 'sound', 'music', 'speech') {
    $pool = @($miniItems | Where-Object { $_.attr.task -eq $task } | Sort-Object idx)
    $pick = $pool | Get-Random -Count $MiniPerTask -SetSeed $s; $s++
    foreach ($p in ($pick | Sort-Object idx)) {
        $qid = 'mini_{0:d4}' -f $p.idx
        [void]$questions.Add([pscustomobject]@{
            qid = $qid; dataset = 'MMAU-test-mini'; task = $task
            category = $p.attr.category; subcategory = $p.attr.'sub-category'; difficulty = $p.attr.difficulty
            question = $p.row.instruction; choices = @($p.row.choices)
            audio = @("data\mmau_mini\audio\$qid.wav")
        })
        [void]$key.Add([pscustomobject]@{ qid = $qid; answer = $p.row.answer })
        [void]$dl.Add([pscustomobject]@{ qid = $qid; kind = 'url'; src = $p.row.context.src; dest = "data\mmau_mini\audio\$qid.wav" })
    }
}

# ---- MMAU-Pro (single-audio multiple-choice, sound/music/speech) ----
$pro = Get-Content (Join-Path $Root 'data\mmau_pro\rows_full.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($cat in 'sound', 'music', 'speech') {
    $pool = @($pro | Where-Object { $_.row.category -eq $cat -and @($_.row.audio_path).Count -eq 1 -and @($_.row.choices).Count -ge 2 } | Sort-Object row_idx)
    $pick = $pool | Get-Random -Count $ProPerCat -SetSeed $s; $s++
    foreach ($p in ($pick | Sort-Object row_idx)) {
        $qid = 'pro_{0:d4}' -f $p.row_idx
        $ch = @($p.row.choices)
        $ch = @($ch | Get-Random -Count $ch.Count -SetSeed ($Seed + $p.row_idx))   # shuffle so position carries no information
        $lab = for ($i = 0; $i -lt $ch.Count; $i++) { '({0}) {1}' -f $letters[$i], $ch[$i] }
        $ext = [System.IO.Path]::GetExtension(@($p.row.audio_path)[0])
        [void]$questions.Add([pscustomobject]@{
            qid = $qid; dataset = 'MMAU-Pro'; task = $cat
            category = (@($p.row.reasoning_skills) -join '; '); subcategory = (@($p.row.perceptual_skills) -join '; '); difficulty = $p.row.length_type
            question = $p.row.question; choices = @($lab)
            audio = @("data\mmau_pro\audio\$qid$ext")
        })
        [void]$key.Add([pscustomobject]@{ qid = $qid; answer = $p.row.answer })
        [void]$dl.Add([pscustomobject]@{ qid = $qid; kind = 'zip'; src = @($p.row.audio_path)[0]; dest = "data\mmau_pro\audio\$qid$ext" })
    }
}

New-Item -ItemType Directory -Force (Join-Path $Root 'out') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'out\questions.json'), (ConvertTo-Json -InputObject $questions -Depth 6), $enc)
[System.IO.File]::WriteAllText((Join-Path $Root 'out\answer_key.json'), (ConvertTo-Json -InputObject $key -Depth 4 -Compress), $enc)
[System.IO.File]::WriteAllText((Join-Path $Root 'out\downloads.json'), (ConvertTo-Json -InputObject $dl -Depth 4), $enc)
"questions: $($questions.Count)"
$questions | Group-Object dataset, task | ForEach-Object { "  $($_.Name): $($_.Count)" }
