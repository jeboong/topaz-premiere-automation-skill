# Topaz Video CLI Reference

## Discovery

Use Topaz Video, not Topaz Video AI:

```text
C:\Program Files\Topaz Labs LLC\Topaz Video\ffmpeg.exe
```

The model directory is normally:

```text
C:\ProgramData\Topaz Labs LLC\Topaz Video\models
```

Before running Topaz filters, set:

```powershell
$env:TVAI_MODEL_DIR='C:\ProgramData\Topaz Labs LLC\Topaz Video\models'
$env:TVAI_MODEL_DATA_DIR='C:\ProgramData\Topaz Labs LLC\Topaz Video\models'
```

Without those variables, `tvai_up` or `tvai_fi` may report `Model not found`.

## Models

Use:

- Rhea upscale: `rhea-1`
- Apollo frame interpolation: `apo-8`

Verify filters:

```powershell
& 'C:\Program Files\Topaz Labs LLC\Topaz Video\ffmpeg.exe' -hide_banner -h filter=tvai_up
& 'C:\Program Files\Topaz Labs LLC\Topaz Video\ffmpeg.exe' -hide_banner -h filter=tvai_fi
```

## Company Output

Use:

- 3840x2160
- exact CFR 24fps
- MOV
- ProRes 4444 flags
- audio copy
- duplicate-frame replacement off
- Rhea upscale always
- Apollo frame interpolation only when source fps is not already exact 24fps, unless the user requests otherwise

`duplicate frames` maps to the `tvai_fi` `rdt` threshold. Use `rdt=-0.000001` or another non-positive value to keep it off. Higher values ask Topaz to detect repeated/held frames and synthesize replacements, which can alter cadence and produce awkward reported rates such as `24.12`.

Before building the filter chain, probe the source with `ffprobe`. If `avg_frame_rate` is exact `24/1`, skip `tvai_fi`; it wastes time and can slightly alter cadence for no benefit. Also skip the final `fps=fps=24` filter and `-r:v 24` for exact 24fps sources; using them on odd frame-count clips can add a duplicate frame. Instead append `setpts=N/(24*TB)` so the output keeps the same frame count but reports clean 24fps timestamps. If the source reports `23.976`, `24.12`, `30`, or any other non-24 rate, produce a final CFR 24 output and verify it before relinking.

## ProRes 4444

The required encoder flags are:

```text
-c:v prores_ks -profile:v 4 -vendor apl0 -tag:v ap4h -pix_fmt yuv444p10le -metadata:s:v:0 encoder=AppleProRes4444
```

This is a real ProRes 4444 MOV signal. It does not restore chroma or alpha missing from an 8-bit 4:2:0 source, but it is the company-required high-quality intermediate format.

If the Topaz UI no longer shows ProRes 4444, use `scripts/Install-ProRes4444Encoder.ps1` or the asset `assets/prores-4444-encoder-entry.json`. CLI automation does not require the UI encoder list because the script passes these flags directly.

## FPS Normalization

The final filter chain should include:

```text
fps=fps=24
```

Also use output CFR options:

```text
-r:v 24 -fps_mode:v cfr
```

After output, check `avg_frame_rate` or `r_frame_rate` with `ffprobe`. If neither reports 24, rerun or normalize before relinking.

Topaz Video 1.5.0 may print `Unable to parse "fps" option value "0"` from `tvai_fi` even when no `fps` option is supplied to that filter. Treat it as noise only if the process exits successfully and `ffprobe` verifies exact 24fps.
