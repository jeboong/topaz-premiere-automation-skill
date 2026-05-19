# Premiere Project Workflow

## Safety

- Never touch `X:\`.
- Create a timestamped backup of the project and affected media before relinking or moving files.
- Do not permanently delete obsolete versions until the relinked project and output files have been verified.

## Reading `.prproj`

Premiere `.prproj` files may be gzipped XML or plain XML. Detect by checking the first bytes:

- `1F 8B`: gzip-compressed XML
- otherwise: plain XML

When writing back, preserve the original encoding style unless the user asks for XML export only.

## Timeline Extraction

Find the intended sequence, then collect video media clips by timeline order. Exclude:

- captions/subtitles
- Essential Graphics/text/title layers
- icons
- still images
- adjustment layers
- generated solids/bars/slugs

If the user asks to process only clips after a specific cut such as `C0040`, keep earlier clips and start the manifest at the next timeline clip.

## Exact-Length Materialization

Premiere uses high-resolution ticks. A common Premiere tick base is:

```text
254016000000 ticks/second
10584000000 ticks/frame at 24fps
```

Use integer frame counts when possible. Avoid floating-point duration math for frame-critical edits.

For arbitrary non-keyframe cuts, a pure stream-copy trim is not truly frame-exact. If the clip will be upscaled anyway, exactness is best achieved by decoding and rendering the used video segment, then feeding that exact-length segment to Topaz. Audio `copy` can be kept for full-length sources; trimmed audio copy may be container/keyframe dependent.

## Relinking

After output verification:

1. Back up originals or move superseded files into a timestamped backup folder.
2. Replace project media paths with the new `.mov` outputs.
3. Preserve media IDs where possible so timeline references keep working.
4. Update sequence dimensions to 3840x2160 square-pixel 24fps where the project XML exposes those fields.
5. Search the project/XML for stale old file names and missing paths.

## 2025 Compatibility

Do not promise a true Premiere project downgrade by editing version numbers. For Premiere 2025 handoff, create an `xml` folder beside the project and write/export a Final Cut Pro XML-style handoff that links the verified media. If Premiere is available and can export an official XML, prefer that.

Only make the XML when it is useful: the user asks for it, the editor uses Premiere Pro 2025, or the `.prproj` was saved from a newer Premiere version and must be opened in 2025. If the current project is already for 2025 and the user does not need an interchange file, skip XML.
