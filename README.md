# Reading Sound Without Ears

Code, prompts, raw model outputs and scores for the blog post **Reading Sound Without Ears**: two frontier language models (Claude Fable 5.2 and Claude Opus 5.5) answer all 1,000 questions of [MMAU test-mini](https://arxiv.org/abs/2410.19168) **without any audio input**, from spectrogram images, a numeric spectrogram they can query with a tool, a Whisper transcript, or nothing at all.

- **Read the post:** [yichen14.github.io/posts/reading-sound-without-ears.html](https://yichen14.github.io/posts/reading-sound-without-ears.html) (English and Chinese, with playable, draggable examples)
- Standalone single-file version: [`blog/reading-sound-without-ears.html`](blog/reading-sound-without-ears.html); static PDF: [`blog/reading-sound-without-ears.pdf`](blog/reading-sound-without-ears.pdf)

## Main results (MMAU test-mini, accuracy %)

| Condition | What the model gets | Opus 5.5 | Fable 5.2 |
|---|---|---|---|
| A | question and options only | 62.9 | 66.9 |
| L | A + clip length | 65.1 | 69.6 |
| B | L + two spectrogram images (0–8 kHz, 0–2 kHz zoom) | 64.3 | 70.3 |
| E | L + `query_spectrogram` tool over the numeric spectrogram | 66.6 | 69.8 |
| D | L + Whisper-small transcript | 73.8 | 75.8 |
| C | B + D | 74.7 | **79.4** |

Against the clip-length control L, spectrograms add a lot on questions about *when* things happen (Fable: 46% → 70% on event timing and counting) and cost 8–10 points on questions about *how* things sound (melody, harmony, timbre, texture, genre, emotion). Per-question results are in [`full/api_results.csv`](full/api_results.csv) and [`full/api_results_L.csv`](full/api_results_L.csv).

## Repository layout

```
scripts/                 all code (Windows PowerShell 5.1 + inline C#; no Python needed)
  legacy/                tools from the early hand-run pilot, kept for reference
full/                    MMAU test-mini run
  api/<model>/<cond>/    one JSON per question: answer, stop reason, tool calls, token counts, raw text
  api/<model>/*_explain/ 32-question re-runs that also return the evidence the model used
  api_results*.csv       per-question answers and correctness for every model and condition
  ans_<model>_<cond>.tsv answers in the scorer's input format
  asr/<qid>.srt          Whisper transcripts used in conditions C and D
  durations.csv          clip lengths given in every condition except A
  e_splits/              how condition E was split across parallel processes
  explain_ids.txt        the 32 questions re-run with explanations
pro/                     30-question MMAU-Pro pilot (A, L, B, D, C)
  results.csv            per-question answers; long_audio_check.csv: corrupted-audio scan (see below)
blog/                    standalone post (template.html -> built HTML/PDF), the bilingual site version
                         (site_post.html + site_figures.js), the example clips and spectrograms
```

## Reproducing

Requirements: Windows PowerShell 5.1, `curl.exe`, FFmpeg 8.0 or newer built with the `whisper` filter (for transcripts), the whisper.cpp `ggml-small.bin` model in `data/models/` (from [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)), and an Anthropic API key in `ANTHROPIC_API_KEY`.

```powershell
$root = (Get-Location).Path
# 1. questions, answer key and audio for all 1,000 test-mini questions (about 1.7 GB of WAV)
.\scripts\full_prepare.ps1 -Root $root
# 2. evidence: spectrogram images, durations, numeric spectrograms (about 1.7 GB), transcripts
.\scripts\full_thumbs.ps1  -Root $root            # full\spec_small (0-8 kHz) + full\durations.csv
.\scripts\full_lowspec.ps1 -Root $root            # full\spec_low (0-2 kHz zoom)
.\scripts\specfile.ps1     -Root $root            # full\specdata, read by the query tool in condition E
.\scripts\asr.ps1          -Root $root -Out full  # full\asr
# 3. model runs (resumable; existing results are skipped)
.\scripts\api_launch.ps1   -Root $root
# 4. scoring
.\scripts\api_collect.ps1  -Root $root
.\scripts\full_score.ps1   -Root $root -Conds A,L,B,E -Csv api_results_L.csv
.\scripts\full_score.ps1   -Root $root -Conds A,B,C,D,E -Csv api_results.csv
# 5. the post (needs the explanation re-runs, see the end of api_launch.ps1);
#    -SiteDir also writes the bilingual version into a checkout of the personal site
.\scripts\build_blog.ps1   -Root $root [-SiteDir <path to site checkout>]
```

One question per request, adaptive thinking, effort `high`, answers constrained to the option letters with a JSON schema. The full run on this page cost about $249 at standard API prices, two thirds of it Fable's tool-use runs in condition E. Each condition was run once; re-asking 32 questions changed 14% of answers, so treat differences of one or two points as noise.

### MMAU-Pro pilot

```powershell
.\scripts\fetch_meta.ps1     -Root $root   # question metadata for MMAU test-mini and MMAU-Pro
.\scripts\zip_index.ps1      -Root $root   # central directory of the 47 GB MMAU-Pro data.zip (byte-range requests)
.\scripts\sample.ps1         -Root $root   # seeded sample: out\questions.json (60 test-mini + 30 MMAU-Pro)
.\scripts\download_audio.ps1 -Root $root   # pulls only the sampled files out of data.zip
.\scripts\pro_prepare.ps1    -Root $root   # pro\: questions, spectrograms, durations, transcripts
# then api_eval.ps1 -Out pro for conditions A, L, B, D, C, and pro_score.ps1
```

**Corrupted audio in MMAU-Pro.** Every MMAU-Pro audio file larger than 90 MB (205 single-audio sound questions, row indices 742–946, the roughly 10-minute "which sound comes before/after …" and "how many … sounds" items) is mostly identical-channel full-band noise at about −6.5 dBFS RMS, with only about 30 s of real audio. Our extracted files match the CRC32 checksums in the archive, so the problem is in the public release itself. `scripts/pro_check_long.ps1` re-checks every such file by fetching only its first few hundred kilobytes. The pilot numbers in the post exclude the three affected questions it sampled.

## Data and licences

This repository does not redistribute MMAU or MMAU-Pro questions or audio; the scripts download them from the official Hugging Face releases (`gamma-lab-umd/MMAU-test-mini`, `gamma-lab-umd/MMAU-Pro`) under their own terms. The 16 short example clips in `blog/assets/` are excerpts used for commentary in the post. Model outputs in `full/api` and `pro/api` were produced with the Claude API.

## Citation

If you use the results or the corrupted-audio finding, please cite this repository and the benchmark:

```bibtex
@misc{reading_sound_without_ears_2026,
  title        = {Reading Sound Without Ears: What Language Models Read in Spectrograms},
  author       = {Lu, Yichen},
  howpublished = {Blog post},
  year         = {2026},
  month        = nov,
  url          = {https://yichen14.github.io/posts/reading-sound-without-ears.html}
}

@article{sakshi2025mmau,
  title   = {MMAU: A Massive Multi-Task Audio Understanding and Reasoning Benchmark},
  author  = {Sakshi, S and Tyagi, Utkarsh and Kumar, Sonal and Seth, Ashish and Selvakumar, Ramaneswaran and Nieto, Oriol and Duraiswami, Ramani and Ghosh, Sreyan and Manocha, Dinesh},
  journal = {arXiv preprint arXiv:2410.19168},
  year    = {2024}
}
```
