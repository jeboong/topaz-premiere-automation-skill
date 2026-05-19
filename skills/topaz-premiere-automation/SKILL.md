---
name: topaz-premiere-automation
description: Automate company AI clip workflows that combine Adobe Premiere Pro project/timeline media, company cut naming, exact timeline-length clip materialization, Topaz Video batch upscaling without opening the GUI, 4K 24fps ProRes 4444 MOV output, original backups, relinking, and 2025-compatible XML handoff. Use when a user mentions Topaz Video, Rhea, Apollo, upscaling, Premiere .prproj/.xml relinking, timeline clip renaming, S##_NAME_C####_v### naming, or batch AI clip export/upscale automation.
---

# Topaz Premiere Automation

## Core Rules

- Use **Topaz Video**, not Topaz Video AI. Prefer `C:\Program Files\Topaz Labs LLC\Topaz Video\ffmpeg.exe`.
- Never read from or write to `X:\` unless the user explicitly reverses that rule in the same task.
- Work on a copied `.prproj` or create a timestamped backup before editing project files or moving media.
- Treat text layers, captions, graphics, icons, adjustment items, and still images as non-video unless the user explicitly asks to process them.
- Output company upscales as `3840x2160`, exact `24fps`, `.mov`, ProRes 4444 flags, Rhea upscale, audio copy, duplicate-frame replacement off. Use Apollo frame interpolation only when the source is not already exact 24fps, unless the user explicitly requests FI anyway.
- Verify every output with `ffprobe`; if a file reports `23.976`, `24.12`, `30`, or anything other than 24fps, normalize/re-render it to exact CFR 24 before relinking. If the source is already exact 24fps, do not add an `fps` filter or `-r 24`, because that can add a duplicate frame on odd frame-count clips; use `setpts=N/(24*TB)` to keep frame count while writing clean 24fps timestamps.

## Quick Start

1. Read `references/company-naming.md` for naming and folder rules.
2. Read `references/topaz-video-cli.md` before calling Topaz on a new workstation.
3. For Premiere projects, read `references/premiere-project-workflow.md`.
4. Run `scripts/Test-TopazVideoCli.ps1` to confirm the Topaz install, model directory, Rhea, Apollo, and filters.
5. Build a manifest of source/output pairs. For folder-only batches, use `scripts/New-TopazBatchManifest.ps1`. For `.prproj` timelines, derive the manifest from timeline order after excluding non-video layers.
6. Run `scripts/Invoke-TopazVideoBatch.ps1` on the manifest.
7. Validate output dimensions/fps/codec, back up originals, then relink the Premiere project to the new files. Use `scripts/Update-PremiereLinksFromManifest.ps1` for path replacement when exact old paths are present in the project XML.

## Standard Topaz Batch

Use the bundled batch runner instead of reconstructing the Topaz command from memory:

```powershell
& .\scripts\Invoke-TopazVideoBatch.ps1 `
  -ManifestPath .\manifest.json `
  -AudioMode copy `
  -Force
```

The script sets:

- `TVAI_MODEL_DIR` and `TVAI_MODEL_DATA_DIR`
- `tvai_fi=model=apo-8:slowmo=1:rdt=-0.000001`
- `tvai_up=model=rhea-1:w=3840:h=2160`
- final `fps=fps=24`
- ProRes 4444 MOV flags: `prores_ks`, `-profile:v 4`, `-tag:v ap4h`, `yuv444p10le`

By default, `Invoke-TopazVideoBatch.ps1` probes each source. If it is already exact 24fps, it skips `tvai_fi` and runs Rhea only. For a smoke test, pass `-FrameLimit 2` on one short source before launching a full batch.

## Manifest Format

Use UTF-8 JSON:

```json
{
  "items": [
    {
      "source": "C:\\path\\input.mp4",
      "output": "C:\\path\\S48B_SAK_C0010_v001.mov"
    }
  ]
}
```

Optional fields are `trimStart` and `duration`, but for frame-exact timeline cuts prefer materializing exact-length source clips first, then upscaling those already-trimmed files.

Optional FI controls:

- `frameInterpolation: true`: force Apollo for that item.
- `frameInterpolation: false` or `noFrameInterpolation: true`: skip Apollo for that item.

## Premiere Workflow

For `.prproj` work:

- Decode the project as XML, preserving whether the file was gzipped or plain XML.
- Identify the active/main sequence and video clips in timeline order.
- Exclude captions, Essential Graphics, titles, stills, icons, and text layers.
- Rename/materialize clips by timeline order using the company naming rule.
- For exact trims, use frame counts at 24fps; Premiere ticks are commonly `254016000000` per second, so one 24fps frame is `10584000000` ticks.
- Relink the project to the new/upscaled file paths and update sequence settings to 3840x2160 square-pixel 24fps where those fields are present.
- Create a 2025 handoff XML only when the user asks for it or when the editor must open the work in Premiere Pro 2025 while the `.prproj` was saved by a newer Premiere version. If the user's Premiere is already 2025, XML export is optional. Do not promise true `.prproj` downgrades unless Premiere itself exports one.

## Resources

- `scripts/Test-TopazVideoCli.ps1`: workstation readiness check.
- `scripts/New-TopazBatchManifest.ps1`: create ordered company-named manifests from a folder.
- `scripts/Invoke-TopazVideoBatch.ps1`: run Topaz Video CLI batch upscales and verify 4K/24fps.
- `scripts/Update-PremiereLinksFromManifest.ps1`: back up a `.prproj` and relink source paths to manifest outputs.
- `scripts/Update-FcpXmlFromManifest.ps1`: relink a Premiere/FCP XML handoff to manifest outputs and set sequence width/height.
- `scripts/Install-ProRes4444Encoder.ps1`: optional UI encoder patch for Topaz's `video-encoders.json`.
- `assets/prores-4444-encoder-entry.json`: ProRes 4444 encoder entry if the UI preset disappears.
- `assets/topaz-rhea4k-apollo24-prores4444.preset.json`: portable record of the company preset.
