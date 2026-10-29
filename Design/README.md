# Editable Sketch designs

Keep one document per device directly in this folder: `Gus-<device>.sketch`.
Light and Dark appearances belong inside that document. Reusable components for
both appearances live in `Gus-Shared-Library.sketch`.

- `Gus-iPhone.sketch`: current iPhone Screens, States, and Components, including
  both appearances. The older separate appearance files are archived locally.
- `Gus-iPadOS.sketch`: 95 Screens and 62 States in each appearance. Light/Dark
  partners are adjacent in a compact canvas grid; their internal layouts match.
- `Gus-Shared-Library.sketch`: existing Light/Dark components plus editable paired
  Dark sources and their color/style dependencies. iPad Dark instances link to
  this library rather than flattened images.

`appearance-coverage.json` maps the iPad appearance partners by persistent layer
ID. Screens, States, and Components remain the document's three pages.

## Appearance maintenance

The library retains its original linked Apple resources. The paired Dark sources
preserve the existing controls' nested geometry, text, visibility, and override
paths. They use Dark text/surface/accent values and Dark vibrancy blending.
`References / iPad / Dark` and `References / Shared / Dark` contain editable
supporting sources; existing Dark variants remain available for compatibility.
When updating a source control, update and review its paired Dark source too;
these local appearance derivatives do not automatically switch with macOS's
appearance setting.

Refresh tracked snapshots by copying the canonical saved files byte for byte.
Sketch's copy-save operation can assign a new document identity; retain the
shared library's identity so the device documents keep their component links.

The delivered files were opened and saved by Sketch, checked for symbol/image
references and appearance coverage, and reviewed using representative native PNG
exports. Design completion does not establish runtime or physical-device
acceptance. Review images and recovery checkpoints stay outside Git.
