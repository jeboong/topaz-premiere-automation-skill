# Topaz Premiere Automation Skill

Company Codex skill for batch upscaling Premiere timeline clips with Topaz Video without opening the Topaz GUI.

## Install For Codex

Copy this folder into a worker's Codex skills directory:

```powershell
$dst = "$env:USERPROFILE\.codex\skills\topaz-premiere-automation"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
Copy-Item -Recurse -Force ".\skills\topaz-premiere-automation" $dst
```

Restart Codex after copying. Then ask Codex something like:

```text
Use the topaz-premiere-automation skill. In this Premiere project, rename timeline video clips by company naming rules, materialize exact timeline lengths, upscale to 4K 24fps Rhea/Apollo ProRes 4444 MOV with audio copy, back up originals, relink the project, and create a 2025 XML handoff. Do not access X drive.
```

## Direct Batch Use

Validate the workstation:

```powershell
.\skills\topaz-premiere-automation\scripts\Test-TopazVideoCli.ps1
```

Create a manifest from a folder:

```powershell
.\skills\topaz-premiere-automation\scripts\New-TopazBatchManifest.ps1 `
  -InputFolder "C:\path\clips" `
  -SceneName "S48B_SAK"
```

Run a two-frame smoke test:

```powershell
.\skills\topaz-premiere-automation\scripts\Invoke-TopazVideoBatch.ps1 `
  -ManifestPath "C:\path\clips\topaz_manifest.json" `
  -FrameLimit 2 `
  -Force
```

Run the full batch after the smoke test succeeds:

```powershell
.\skills\topaz-premiere-automation\scripts\Invoke-TopazVideoBatch.ps1 `
  -ManifestPath "C:\path\clips\topaz_manifest.json" `
  -Force
```

## Notes

- This skill targets **Topaz Video**, not **Topaz Video AI**.
- Output is forced to 3840x2160, CFR 24fps, MOV ProRes 4444, audio copy.
- Sources that are already exact 24fps skip Apollo frame interpolation and use Rhea only by default.
- Duplicate-frame replacement is off.
- The scripts refuse `X:\` paths by default.
