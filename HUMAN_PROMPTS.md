# Human Prompt Examples

Use these examples when asking Codex to use the `topaz-premiere-automation` skill.

## Premiere Full Workflow

```text
Use the topaz-premiere-automation skill.
For this Premiere project: C:\path\project.prproj
Upscale all real video clips on the timeline with the company upscale preset.
Keep each clip's pre-upscale nickname/file name unless I give a new naming rule.
Back up originals into a timestamped backup folder.
Relink the Premiere project to the upscaled files.
Set the sequence to 4K and make the clips fill the frame without letterbox/pillarbox gaps where appropriate.
Create a 2025-compatible XML handoff if the editor needs Premiere Pro 2025 compatibility.
Do not access X drive.
```

## Company Naming Workflow

```text
Use the topaz-premiere-automation skill.
For this Premiere project: C:\path\project.prproj
Rename timeline video clips in order as S48B_SAK_C0010_v001, S48B_SAK_C0020_v001, and so on.
Materialize each clip at the exact timeline length with no frame drift.
Upscale to 4K 24fps ProRes 4444 QuickTime MOV using the company preset.
Back up originals, relink the project to the upscaled files, and create a 2025 XML handoff only if needed.
Ignore captions, text, icons, still images, and Essential Graphics.
Do not access X drive.
```

## Folder Batch

```text
Use the topaz-premiere-automation skill.
Upscale every video in this folder with the company upscale preset:
C:\path\clips
Output QuickTime MOV files beside the originals or into an ups folder.
Keep the original base names.
If a source is already 24fps, skip frame interpolation.
Verify that every output is 3840x2160, exactly 24fps in both avg/r frame-rate fields, ProRes 4444, and Premiere-safe QuickTime MOV with `major_brand=qt  `.
Do not access X drive.
```

## Folder Batch With New Names

```text
Use the topaz-premiere-automation skill.
Upscale every video in this folder:
C:\path\clips
Name the outputs as S48B_SAK_C0010_v001, S48B_SAK_C0020_v001, incrementing by 10.
Use the company upscale preset: Rhea 4K, Apollo only for non-24fps sources, QuickTime MOV ProRes 4444, audio copy, duplicate frames off, final CFR 24fps.
Do not access X drive.
```

## What The Skill Can Do

- Detect Topaz Video CLI and required model files.
- Batch upscale without opening the Topaz GUI.
- Use Rhea for 4K upscaling.
- Use Apollo only when source fps is not already exact 24fps.
- Force final CFR 24fps and fail if verification reports another rate.
- Output QuickTime MOV ProRes 4444 per company rule.
- Copy audio when possible.
- Generate company cut names from folder order or timeline order.
- Back up originals before relinking.
- Replace Premiere project media links from a manifest.
- Produce a 2025 XML handoff strategy when a newer `.prproj` cannot be downgraded directly.

## Terms To Use

- "company upscale preset" means Rhea 4K, Apollo only for non-24fps sources, final CFR 24fps, QuickTime MOV ProRes 4444, audio copy, duplicate-frame replacement off.
- "fill frame" or "set to frame size/fill" means scale clips to cover the 4K sequence frame instead of leaving empty borders. Ask for "fit" instead if preserving full uncropped image is more important.
