# Company Naming Rules

## Folder

Use:

```text
S00_NAME
```

Example:

```text
S48B_SAK
```

## File

Use:

```text
S00_NAME_C####_v###
```

Rules:

- Cut number starts at `C0010` unless the user gives another start.
- Cut number is four digits and usually increments by 10: `C0010`, `C0020`, `C0030`.
- Version is lowercase `v` plus three digits: `v001`, `v002`, `v003`.
- Do not overwrite old versions; create the next version unless the user explicitly asks to clean obsolete versions.
- Include the extension after the name, usually `.mov` for Topaz output.

Examples:

```text
S48B_SAK_C0010_v001.mov
S48B_SAK_C0020_v001.mov
```

## AFX and SRC

If a live-action plate was reprocessed by AI, insert `_AFX` before the version:

```text
S99_EXS_C0980_AFX_v001.mov
```

If the generated video is a compositing source, insert `_SRC` after the cut number:

```text
S99_EXS_C0980_SRC_v001.mov
```

Combine them in this order:

```text
S99_EXS_C0980_SRC_AFX_v001.mov
```

For multiple source variants:

```text
S99_EXS_C0980_SRC_A_AFX_v001.mov
S99_EXS_C0980_SRC_B_AFX_v001.mov
```

## Timeline Order

When renaming from a Premiere timeline, sort clips by actual timeline order, not folder order. If multiple clips share the same cut slot, keep versions in timeline order: `v001`, `v002`, `v003`.
