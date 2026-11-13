# FORMATS BLUEPRINT: every format, small app, on-demand Format Packs

Package: `com.fyleon.app` | Written: 11 Nov 2026 | Based on: `Fyleon_All_File_Formats.md` (26 categories, A-Z) + the 8 feature specs.
Put this file in the repo root next to `FEATURES.md` / `ARCHITECTURE.md`. It is a PLAN: nothing here is built yet unless it says so.

---

## 0. Decisions in one screen

1. **"Read" has levels.** Every format of the list gets at least level R1 (identify + safe inspect + hand-off). Rendering (R2) is added wherever a real, safe parser/renderer exists. Editing (R3) and creating (R4) are limited to formats where Fyleon can really round-trip.
2. **Three tiers.** Tier 1 = inside the APK (small, common). Tier 2 = **Format Packs** the user downloads when needed. Tier 3 = identify + hand-off only (proprietary, licensed or dangerous formats).
3. **Settings > Format Packs** page: categories, search on top, filters (incl. **My formats**), Download / Delete. Built-in formats are listed too but are locked (no delete).
4. **IMPORTANT CHANGE to the idea "download code from the git repo":** app stores forbid downloading *executable* code (native `.so`, dex/jar) from outside the store. So packs are split into three kinds (Section 3). Only the safe kinds are downloaded; heavy native engines need another route (Section 3.3).
5. **Pack downloads need a PUBLIC place** (public GitHub repo / Release / GitHub Pages). A private repo cannot be used from inside the app, because the app must never contain a token.
6. **Honest wording everywhere:** the app shows "Supported: Preview" or "Hand-off only" per format. Never "all formats" as a promise; publish the tested support matrix instead.

---

## 1. Read levels (what "supports a format" means)

| Level | Name | What the user gets | Typical examples |
|---|---|---|---|
| R0 | Identify | Real type by magic bytes + extension, size, dates, checksum | every file |
| R1 | Inspect | Metadata, safe text/hex view, entry list, hand-off to another app | `.dwg`, `.pst`, `.exe`, `.pt` |
| R2 | Preview | Rendered view (page, image, table, 3D, map, list of tracks...) | PDF, DOCX, STL, GPX |
| R3 | Edit | Change and save safely (Save Copy by default, atomic write) | text, code, JSON, CSV, SQLite, image basics |
| R4 | Create / Convert | New file or conversion with a fidelity warning | ZIP, MD, TXT, PDF tools, DOCX subset |

Rules: the UI shows Edit / Create / Convert **only** where that level is really implemented for that format. A parser that extracts text from `.docx` is R2, not "Word editing".

Status words (same as the QA rules): `planned` -> `in progress` -> `code written` -> `CI passed` -> `device tested` -> `known limitation`. A format is marked supported only at `device tested`.

---

## 2. The three tiers

| Tier | Where it lives | Size effect | What goes here |
|---|---|---|---|
| **1 Built-in** | inside the APK/AAB | small, fixed | Format catalog + identify engine for ALL formats; hex/hash/metadata inspector; everyday formats (images, PDF, EPUB, text/code/data, Office OOXML/ODF previews, ZIP/TAR family, audio/video via the phone's own decoders, subtitles, certificates, SQLite read-only) |
| **2 Format Packs** | downloaded by the user, stored in app-private storage | grows only for the user who downloads | grammars, language data, fonts, sandboxed parsers/renderers for less common formats (Section 3) |
| **3 Hand-off** | nothing to install | none | proprietary / licensed / risky formats: identify, show metadata, "Open with another app", "Save a copy" |

Target (proposal, to be measured in CI, not a promise): keep the **core APK as small as possible** and print an APK-size report on every build, so a growing core is noticed at once.

---

## 3. Pack kinds and store rules

### 3.1 Why packs are split by kind
Google Play's policy does not allow an app to download executable code (dex, JAR, native `.so`) from a source other than Google Play. It does allow data, and code that runs inside a sandboxed interpreter/VM that only gets indirect access to Android APIs. Amazon Appstore and other stores have their own rules: **check each store's current policy before shipping packs** (open item in Section 12). Fyleon's own spec also says: never use remote configuration to download or execute code.

### 3.2 The three kinds

| Kind | What is downloaded | Runs as | Store-safe? | Examples |
|---|---|---|---|---|
| **D (data)** | JSON / text / binary data | not code | yes | syntax grammars (TextMate JSON), OCR language data, fonts, soundfonts (MIDI), dictionaries, ICC profiles, templates, format-catalog updates, icon packs |
| **W (sandboxed module)** | a WebAssembly module (and its data) | inside an embedded WASM interpreter, memory + time limited, **only bytes in / bytes out**: no files, no network, no Android API | most likely yes (interpreter with indirect access); confirm per store | parsers/renderers for DXF, MOBI, XLS, DICOM, PSD composite, EMF/WMF, DBF... |
| **N (native)** | native `.so` / dex | native code | **NOT downloadable on Google Play** | LibVLC / FFmpeg software decoders, LibRaw develop, OpenCascade (STEP/IGES), libarchive-based RAR/7z |

### 3.3 Where Kind N goes (options, owner decision needed)

| Option | How | Pros | Cons |
|---|---|---|---|
| A. Ship it inside the store build | engine is part of APK/AAB | simple, store-safe | every user pays the size |
| B. Play Feature Delivery (on-demand module) | Play downloads the module | real "download when needed", Play-approved | Google Play only (not Amazon / GitHub APK) |
| C. Companion app per engine | e.g. "Fyleon Pack: Video+" is a separate APK; Fyleon talks to it by intent | works on any store; user stays in control | more apps, install friction, more review work |
| D. "Full" APK on GitHub Releases | CI build variant that includes all N engines | easy for power users | not for stores; big file |

Recommendation: ship D + W first, keep N engines out of the core, and decide A/B/C per engine only when a real user need appears. The workflow already has `release | debug`; a `flavor core | full` choice can be added later.

---

## 4. Settings > Format Packs (the page)

Goal: the user sees every format family, knows what is built in, and can download or delete the rest.

### 4.1 Wireframe

```
+--------------------------------------------------+
| <  Format Packs                                  |
| [ search: format, extension (.dwg), pack...   ]  |
| ( All )( My formats )( Available )( Updates )    |
| ( Built in )                                     |
| Category: Images | Documents | eBooks | Data |...|  <- horizontal chips
|--------------------------------------------------|
| Storage used by packs: 38 MB     [Delete all]    |
|--------------------------------------------------|
| IMAGES                                           |
| [img] Everyday images                 BUILT IN   |
|       JPG PNG WebP GIF BMP ICO SVG   (lock)      |
| [img] Camera RAW                  4.1 MB [Get]   |
|       DNG CR2 CR3 NEF ARW ORF RW2 RAF            |
|       Preview: yes   Edit: no                    |
| [img] Pro images                  2.8 MB [Get]   |
|       TIFF JXL JP2 EXR HDR DDS KTX TGA          |
| CODE                                             |
| [</>] Core languages (40)             BUILT IN   |
| [</>] More languages (120)        0.9 MB [Delete]|
|       installed 2026-11-12   v3     (green tick) |
| ...                                              |
+--------------------------------------------------+
Tap a row -> detail sheet: formats list, what you can do
(Open / Preview / Edit / Create / Convert), size, version,
license of the engine, source, [Download] or [Delete].
```

### 4.2 Behaviour rules
- **Built-in rows** show a lock + "Built in". No delete, no download. They are always listed so the user sees the complete picture.
- **Downloaded rows** show size + date + version, with **Delete** (confirm; frees space at once) and **Update** when a newer version exists.
- **Not downloaded rows** show size + **Download**.
- **My formats** filter = everything built in + everything downloaded (what this phone can open now). **Available** = not downloaded yet. **Updates** = downloaded packs with a newer version.
- **Search** (top, always visible): matches pack name, format name, extension with or without dot (`dwg`, `.dwg`), category, and tags ("autocad"). Result shows the pack that handles it.
- **Category chips**: the same A-Z families as Section 7 (Images, Documents, PDF/Publishing, Sheets, Slides, eBooks, Data, Code, Audio, Video, Archives, 3D/CAD, Fonts, Databases, GIS, Science, AI/ML, Games, System, Disk images, Email, Security, Web, Subtitles, Animation, Misc).
- **Download**: Wi-Fi-only toggle (default on), size shown before, progress + pause/cancel, resume, storage check, never blocked or interrupted by ads. No rewarded ad required for any pack.
- **Delete any time**; deleting a pack never deletes the user's own files, only the pack.
- **Open-time prompt**: tap a `.dwg` whose pack is missing -> sheet: "CAD files need the CAD pack (3.2 MB). [Download and open] [Open with another app] [View hex / info]". Always an exit that does not need the pack (R1 fallback).
- Counters on the page: "N formats usable now, M more available".

### 4.3 Where the files live

```
app-private storage (not visible to other apps, removed on uninstall)
  files/packs/<pack-id>/<version>/        <- unpacked pack
  files/packs/installed.json              <- installed packs + versions + sha256
  cache/packs/downloads/                  <- partial downloads (cleaned on start)
```

---

## 5. Data model

### 5.1 Format catalog (inside the APK, always present)
`assets/catalog/file_formats.json` (generated from `Fyleon_All_File_Formats.md`, versioned):

```json
{
  "catalogVersion": 1,
  "formats": [
    {
      "id": "dxf",
      "name": "AutoCAD Exchange",
      "category": "cad",
      "extensions": ["dxf"],
      "mime": ["image/vnd.dxf"],
      "magic": [{"offset": 0, "ascii": "0\r\nSECTION"}],
      "level": {"builtin": 1, "withPack": 2},
      "pack": "cad-view",
      "fallback": "text-view",
      "tags": ["autocad", "drawing"],
      "tested": false,
      "notes": "Preview only; no editing"
    }
  ]
}
```
Extensionless names are first-class: `Dockerfile`, `Makefile`, `LICENSE`, `README`, `known_hosts`, `.gitignore`. Extension is only a hint; magic bytes win.

### 5.2 Pack index (remote, small, signed)
`packs_index.json` published on a public URL:

```json
{
  "indexVersion": 1,
  "minAppVersion": "0.9.0",
  "packs": [
    {
      "id": "cad-view",
      "name": "CAD preview",
      "category": "cad",
      "kind": "W",
      "version": 3,
      "sizeBytes": 3400000,
      "sha256": "...",
      "url": "https://.../cad-view-3.zip",
      "formats": ["dxf", "gcode", "gbr", "kicad_pcb"],
      "abis": ["any"],
      "license": "see packs/cad-view/LICENSE",
      "limits": {"maxInputMB": 64, "maxMillis": 15000, "maxMemoryMB": 256}
    }
  ],
  "signature": "ed25519:..."
}
```
- The app holds the **public** signing key. Download = HTTPS + sha256 + index signature. A pack that fails any check is deleted and never loaded.
- A remote kill switch may **disable** a pack (security fix). Remote config can never enable code, add a new kind, or change a download URL.

### 5.3 Repo layout (source of packs)
```
packs/
  <pack-id>/
    pack.json         id, name, kind, formats, limits, license
    LICENSE
    data/ or module.wasm
tool/build_packs.py   builds zips + packs_index.json (+ signs with a CI secret key)
.github/workflows/build-packs.yml   manual run: builds packs, publishes a GitHub Release "packs-latest"
```
Signing private key = a GitHub secret (never in the repo), like the keystore.

---

## 6. Install flow (engineering)

1. Fetch `packs_index.json` (only when the user opens the page or taps Download; no background polling).
2. Verify the index signature -> list packs.
3. Download to `cache/packs/downloads/` (HTTP range resume), check free space (size x 2).
4. Verify sha256 -> unzip into a temp folder -> validate `pack.json` (id, kind, limits, only allowed file types: kind D = data files; kind W = `.wasm` + data; any `.so/.dex/.jar/.apk` inside = reject).
5. Atomic move to `files/packs/<id>/<version>/`, update `installed.json`, register formats in the runtime registry.
6. Delete = remove folder + registry entry + thumbnails produced by that pack.
7. Every open request goes through the existing pipeline: identify -> registry -> handler. If the handler needs a missing pack -> Section 4.2 open-time prompt.

W-pack sandbox rules: input copied into WASM memory (bounded), output returned as bytes/structured data, no clock/random/network imports, hard time + memory limit, run in a separate isolate so a crash cannot take down the UI, result validated before display.

---

## 7. Coverage plan by category (all 26 families of the list)

Legend: **T1** built-in | **P:D / P:W / P:N** pack kind | **T3** hand-off only. Pack sizes are not promised here; measure when built.

### A. Images
| Formats | Plan |
|---|---|
| JPEG, PNG, WebP, GIF, APNG, animated WebP, BMP, ICO, CUR, SVG (sandboxed), PBM/PGM/PPM/PNM, TGA | **T1** (R2; basic edit R3 for JPEG/PNG already exists) |
| HEIF/HEIC, AVIF | **T1 if the phone's decoder supports it**, otherwise pack **img-pro** (W) |
| TIFF (multipage), JXL, JP2/J2K, EXR, HDR, DDS, KTX/KTX2, FAX | **img-pro** (P:W) R2 |
| RAW (CR2, CR3, NEF, ARW, DNG, ORF, RW2, RAF, `.raw`) | **img-raw** (P:W): embedded JPEG preview first; full "develop" needs a native engine (P:N, later, Section 3.3) |
| PSD/PSB, XCF, KRA/ORA, PDN, CDR, AI, EPS/PS, EMF/WMF, DjVu image | **design-preview** (P:W): show the flattened/merged preview stored in the file (KRA/ORA keep a merged PNG; many PSD keep a composite; AI is PDF-based). **No layer editing.** EPS/PS full rendering needs an engine -> T3 until one exists |

### B. Documents
| Formats | Plan |
|---|---|
| TXT, MD/markdown family, HTML, RTF (basic), DOCX/DOCM/DOTX/DOTM, ODT/OTT, FB2, AbiWord (`.abw`), AsciiDoc/RST/LaTeX/TeX/Typst/Org (as source with highlight; MD/HTML also rendered) | **T1** (macros never run) |
| SXW/STW (OpenOffice), Apple Pages (preview image inside), HWPX | **doc-extra** (P:W) R2 limited |
| DOC, WPS, WPD, HWP, Works, Lotus WordPro | **doc-legacy** (P:W) text extraction R2 where a parser exists; otherwise T3 |
| Editing | DOCX edit subset is T1 code (no pack); everything else read-only |

### C. PDF and publishing
| Formats | Plan |
|---|---|
| PDF (incl. PDF/A, /X, /E), AI (PDF-based) | **T1** (pdfium); tools in the Documents plan |
| XPS/OXPS, DjVu | **doc-extra** (P:W) |
| PUB, INDD, QXD/QXP, FM/MIF, PMD, SLA/SLAZ, IDML | IDML/SLA (XML) text inspect **T1**; others **T3** (identify + hand-off) |

### D. Spreadsheets
| Formats | Plan |
|---|---|
| CSV, TSV, XLSX/XLSM/XLTX, ODS/OTS, SYLK, DIF, Gnumeric (gzip XML) | **T1** (macros never run; R3 for CSV and XLSX subset later) |
| XLS, XLSB, SXC/STC, ET (WPS) | **sheet-legacy** (P:W) R2 |
| Numbers (preview image inside), Lotus 1-2-3 (`.123 .wk*`), Quattro (`.qpw .wb1`) | preview image if present, else **T3** |

### E. Presentations
| Formats | Plan |
|---|---|
| PPTX/PPSX/POTX/PPTM, ODP/OTP | **T1** (slide renderer exists) |
| PPT, POT, PPS, SXI/STI, DPS | **slides-legacy** (P:W) |
| Keynote `.key` | preview thumbnail only (T1), else T3 |

### F. eBooks
| Formats | Plan |
|---|---|
| EPUB 2/3, FB2, FB2.ZIP, CBZ, CBT, OPF, HTML/MD books, PDF books | **T1** |
| MOBI, AZW, AZW3, PDB/Plucker, CBR, CB7 | **ebook-extra** (P:W; CBR/CB7 also need RAR/7z decoding, see K) |
| KFX, iBooks, Audible-style DRM files | **T3**: DRM is never bypassed |

### G. Text, data and configuration
| Formats | Plan |
|---|---|
| TXT, MD, HTML, XML, JSON/JSONC/JSON5/JSONL/NDJSON, YAML, CSV/TSV, TOML, INI/CFG/CONF/properties, LOG, SQL, GraphQL, RSS/Atom, ICS, VCF, RDF/TTL/NT, GeoJSON (text), JSON Schema | **T1** text + tree/table views, validate/format, R3 |
| MessagePack, CBOR, BSON | **T1** small pure parsers (R2 tree view) |
| Protobuf (`.pb`/`.proto`), Avro, Parquet, ORC | **data-binary** (P:W) R2 schema + row preview; `.proto` is text T1 |
| HDF5, FITS | **sci-core** (P:W), see P |

### H. Programming and coding
| Formats | Plan |
|---|---|
| About 40 core languages + all web/config/build files by name (`pom.xml`, `package.json`, `pubspec.yaml`, `Cargo.toml`, `Dockerfile`, `Makefile`, `.gitignore`...) | **T1** highlight + editor (exists) |
| Remaining languages of the list (COBOL, Fortran, VHDL, Verilog, Solidity, Move, Prolog, Nix, Bicep, Wolfram...) | **grammars-extra** (P:D): data only, tiny |
| Compiled artifacts (`.class`, `.pyc`, `.wasm`, `.dex`) | **T1 inspector**: header/version/sections, never executed |
| JAR/WAR/EAR/AAR | archive (K) |
| Jupyter `.ipynb`, Colab | **T1** viewer (no execution) |
| Project files (`.sln .csproj .xcodeproj .iml`, Unity/Unreal/Godot text assets) | text viewers T1; binary assets T3 |

### I. Audio
| Formats | Plan |
|---|---|
| MP3, AAC/M4A, FLAC, WAV, OGG, Opus, AMR, MIDI, AIFF, WMA | **T1 through the phone's own decoders**; "device dependent" is shown honestly. MIDI sound quality improves with the optional **soundfont** pack (P:D) |
| APE, WavPack, DSD (`.dsf .dff`), AC3/E-AC3/DTS, tracker music (MOD XM S3M IT), AU, CAF, VOC, RealAudio | **audio-extra** (P:N, Section 3.3). DTS/Dolby need licenses |
| MusicXML/MXL | **score-view** (P:W) later; text view T1 meanwhile |
| Audible AA/AAX | **T3** (DRM) |

### J. Video
| Formats | Plan |
|---|---|
| MP4/M4V, MOV, MKV, WebM, 3GP/3G2, TS/M2TS/MTS, MPEG | **T1 through Media3/the phone's decoders**; codec support depends on the device (HEVC, AV1, ...) and an exact "unsupported codec" message is shown |
| AVI (Xvid/DivX), WMV/ASF, FLV/F4V, VOB, MXF, OGV, RealMedia | **video-extra** (P:N software decoders; Section 3.3) |
| ProRes, DNxHD, BRAW, R3D, CineForm, VVC | **T3** or best-effort; pro formats need vendor SDKs |
| Subtitles | see X |

### K. Archives and compression
| Formats | Plan |
|---|---|
| ZIP, JAR, WAR, EAR, AAR, APK, AAB, APKS, XAPK, IPA, TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, DEB | **T1** pure-Dart, with the full safety limits (path traversal, zip bomb, symlinks) |
| ZIPX | read when it only uses Deflate; other methods -> pack |
| 7z, RAR/RAR5 (read-only), ZST, LZ4, LZMA/LZIP/LZO, CAB, ISO (list/extract), CPIO, RPM, WIM | **archive-plus** (P:W where a safe port exists, else P:N) |
| DMG, ARJ, ACE, ARC, ALZ, ZOO | identify + hand-off (**T3**) until a maintained legal library exists |
| Create | ZIP first; 7z/TAR family later; password ZIP only after a library audit |

### L. 3D, CAD and engineering
| Formats | Plan |
|---|---|
| OBJ, STL, PLY, 3MF, GLB/GLTF, DAE, X3D/VRML, VTK | **model-3d** (P:W + Flutter renderer): orbit/zoom, wireframe, scene tree, metadata |
| FBX, 3DS, USD/USDZ, Alembic, AMF, OpenVDB | later packs, case by case |
| DXF, G-code (`.gcode .nc .tap`), Gerber, Excellon, KiCad, OpenSCAD source | **cad-view** (P:W / text T1). G-code is only *viewed*, never sent to a machine |
| STEP/STP, IGES/IGS, Parasolid | needs a CAD kernel (P:N, big) -> optional, Section 3.3 |
| DWG, Revit, Inventor, SolidWorks, CATIA, NX, Fusion, Rhino, SketchUp, ArchiCAD, Blender `.blend`, Maya `.ma/.mb` | embedded thumbnail/metadata if present, else **T3**; `.ma` (ASCII) and FreeCAD (zip + thumbnail) are viewable |

### M. Fonts
| Formats | Plan |
|---|---|
| TTF, OTF, TTC/OTC, WOFF | **T1** metadata + sample text + glyph list |
| WOFF2 | **font-extra** (P:W; needs Brotli) |
| EOT, PFA/PFB, BDF, PCF, FON/FNT, SFD | **font-extra** (P:W) |

### N. Databases
| Formats | Plan |
|---|---|
| SQLite (`.sqlite .sqlite3 .db`), SQL dumps (text) | **T1**: read-only browser first, then explicit "Enable editing" with backup + transaction |
| DBF/dBASE/FoxPro, Access (`.mdb .accdb`), Paradox | **db-extra** (P:W) read-only R2 |
| LevelDB, RocksDB, Realm, H2, Firebird, SQL Server, Oracle, Berkeley, Redis RDB, DuckDB | identify + header info + hex (**T3**); server database files are never "faked" |

### O. GIS, GPS and maps
| Formats | Plan |
|---|---|
| GPX, KML/KMZ, GeoJSON/TopoJSON, GML | **gis-core** (P:W/D + map view) R2: tracks, placemarks, properties |
| Shapefile set (`.shp .shx .dbf .prj`), GPKG, MBTiles, GeoTIFF metadata, FIT, LAS/LAZ, OSM/PBF, NetCDF, HDF | **gis-extra** (P:W); GPKG/MBTiles reuse the SQLite engine; big OSM/LiDAR = metadata only |
| Map tiles | offline from legal datasets only; no scraping |

### P. Scientific, medical, research
| Formats | Plan |
|---|---|
| FASTA/FASTQ/GenBank/VCF, PDB, mmCIF, SDF, MOL, CML | text with highlight **T1** |
| NumPy `.npy/.npz`, MATLAB `.mat`, R (`.rds .rdata`), SAS, SPSS, Stata | **sci-core** (P:W) schema + bounded preview |
| FITS, HDF5, NetCDF | **sci-core** hierarchical explorer |
| DICOM, NIfTI, NRRD, MINC, Analyze | **medical-view** (P:W) slice viewer + metadata. Not for diagnosis (stated in the UI) |
| Pickle `.pkl` | **never unpickled**; safe opcode/header view only |

### Q. AI / ML
| Formats | Plan |
|---|---|
| Safetensors, GGUF | **T1** metadata/tensor catalog (header parse only) |
| ONNX, TFLite, TF `.pb`, Keras `.h5/.keras`, Core ML, OpenVINO, Paddle, Caffe, Darknet | **ml-inspect** (P:W) graph/IO/ops overview |
| PyTorch `.pt/.pth/.ckpt` | container/tensor names only; **never unpickle**; no execution |
| HF configs/tokenizers (`.json`), Darknet `.cfg`, prototxt | text **T1** |
| Running a model | separate feature (runtime, RAM check, consent), not part of "open" |

### R. Games
| Formats | Plan |
|---|---|
| Unity package (tar.gz), Minecraft `.mcworld/.mcpack` (zip) | **T1** as archives |
| WAD, PAK, VPK, Unreal `.pak`, `.uasset/.umap`, Godot `.tscn/.tres/.gd` | text ones T1; archives listed by **games-lists** (P:W); `.uasset` identify |
| ROMs, save games, `.dat`, `.wem/.bnk` | identify + hex (**T3**); no emulation |

### S. Executables, system, applications
| Formats | Plan |
|---|---|
| APK/AAB/APKS/XAPK | **T1 inspector**: package, version, SDK, permissions, signing digest; install only through Android's installer |
| EXE, DLL, SYS, MSI, ELF, SO, DYLIB, PKG, DEB/RPM, firmware, kernel, IPA, DMG | **T1 header inspector** (PE/ELF/Mach-O basics) + hash. **Never executed.** |
| REG, INI/CFG, Intel HEX | text **T1** |

### T. Disk images and VMs
| Formats | Plan |
|---|---|
| VHD, VHDX, VMDK, VDI, QCOW/QCOW2, ISO, IMG, DMG, RAW | **T1** header metadata (size, type); ISO file listing via archive-plus |
| OVA (tar), OVF/VBOX/VMX/AVD (text/xml) | **T1** |

### U. Email and communication
| Formats | Plan |
|---|---|
| EML, EMLX, MBOX, MIME, ICS, VCF | **T1** (HTML mail in a sandbox, remote images blocked) |
| MSG, PST, OST | **mail-extra** (P:W) limited; PST/OST may stay T3 |

### V. Security, certificates, encryption
| Formats | Plan |
|---|---|
| PEM, CRT/CER, DER, CSR, PKCS#7/#8/#12 structure, SSH public keys, known_hosts | **T1** metadata (subject, issuer, expiry, fingerprint) |
| Private keys, PFX/P12 | metadata only after an explicit "reveal sensitive file" step; never logged |
| GPG/PGP, KDBX, `.enc` | detect + hand-off. Fyleon does not handle passwords of password managers |

### W. Web and internet
| Formats | Plan |
|---|---|
| HTML/XHTML, CSS, JS, TS, JSON, XML, SVG, webmanifest, MHTML, HAR (tokens redacted), CRX/XPI (zip + manifest), WASM (section inspector) | **T1** |
| WARC, Web Bundle (`.wbn`) | **web-extra** (P:W) / T3 |

### X. Subtitles
| Formats | Plan |
|---|---|
| SRT, VTT, SSA/ASS, MicroDVD `.sub`, MPL2, TTML/DFXP, SAMI, SCC | **T1** viewer/editor with encoding choice and offset |
| EBU STL (binary), DVD `.sup` (image-based) | **sub-extra** (P:W) |

### Y. Animation and motion
| Formats | Plan |
|---|---|
| GIF, APNG, animated WebP, Lottie JSON, SVG animation (safe subset) | **T1** |
| Rive `.riv`, Spine/DragonBones JSON+atlas | **anim-extra** (P) |
| AEPX/XFL/FLA (XML/zip), Maya ASCII | text/thumbnail **T1**; AEP/MB binary -> **T3** |

### Z. Miscellaneous
| Formats | Plan |
|---|---|
| BAK, TMP, LOCK, BIN, DAT, LOG, PATCH/DIFF, checksum files (md5/sha*), README/CHANGELOG/LICENSE, `.url`, `.torrent` (bencode), `.lnk` (parser) | **T1**: text/hex/diff viewers, checksum verify, torrent + shortcut metadata |
| Unknown | R0/R1: signature, size, hash, hex, hand-off. Never an empty error screen |

---

## 8. Formats added beyond your list (proposal)
`jfif`, `svgz`, `heics`, `wbmp`, `opml`, `bib`, `tcx`, `m3u/m3u8/pls/xspf/cue/lrc` (playlists + lyrics), `mka`, `mpc`, `tta`, `7z.001` (split), `rar` multi-part, `lzh`, `squashfs`, `apkm`, `obb`, `smali`, `arsc`, `fodt/fods/fodp` (flat ODF), `rtfd`, `webloc`, `desktop`, `gdoc/gsheet/gslides` (JSON pointers: explain they only point to Google Drive), `env`, `editorconfig`, `ipynb`, `kdbx` (identify only), `msix/appx`, `vsix`, `nupkg`, `gem`, `whl`, `egg`, `crate`, `tgz` family of packages.

---

## 9. Size and quality guardrails
- APK-size report in every CI build (core size per ABI); a jump above a set limit is flagged.
- Each pack has its own fixtures, limits and a documented "what works / what is lost" text shown in its detail sheet.
- Corrupt, truncated, zero-byte, wrong-extension and huge fixtures per format before `device tested`.
- Parsing always off the UI isolate, bounded memory, cancel button for anything slow.
- Licenses: every engine/pack has a license entry (MIT/BSD/Apache/LGPL/GPL/proprietary) checked before adoption; LGPL/GPL engines need an explicit decision. Names in this file are candidates, not approvals.

---

## 10. Build order for the format system

| Step | Work | Result |
|---|---|---|
| F0 | Generate `file_formats.json` from the list; magic-byte identify engine; registry lookup; "Unknown / hand-off" screen; hex + hash + metadata inspector | every format of the list reaches **R0/R1** |
| F1 | Settings > Format Packs page with a **local fake index** (UI, search, filters, My formats, lock for built-in) | the page can be tested before any download exists |
| F2 | Pack installer: download, verify, install, delete, update, storage meter; public `packs/` repo layout + `build-packs.yml` | real downloads |
| F3 | First **kind D** packs: extra grammars, OCR language data, fonts, soundfont | biggest win, zero store risk |
| F4 | WASM runtime proof of concept with ONE parser (for example DXF or MOBI) + sandbox limits | decide W for the rest |
| F5 | More W packs by user value: image-raw preview, doc-legacy, sheet-legacy, ebook-extra, gis-core, model-3d, sci-core | R2 for many more formats |
| F6 | Owner decision for kind N engines (Section 3.3) | video-extra, audio-extra, archive-plus, STEP/IGES |

---

## 11. UI additions outside the Packs page
- **File details** gets a "Format" block: detected type, confidence (exact signature / MIME hint / extension only / unknown), handler, level (R0-R4), pack needed.
- **Open as...** menu: Text, Hex, Image, Archive (when the guess is wrong).
- **Format support matrix** screen (Settings > About > Supported formats): the tested list, generated from the catalog's `tested` flags.
- Home search understands extensions (`.dwg`) and offers "Get the pack" when a file type is not usable yet.

---

## 12. Open items for the owner
1. Is the pack repo **public**? (required, Section 0.5)
2. Primary store now is Amazon Appstore: confirm Amazon's current rule for downloaded content, then Google Play's. Plan A fallback = data packs only + W packs shipped inside the build.
3. Which categories first? Suggested: Code grammars (D), then eBooks/Documents extras, then Images RAW/pro, then GIS and 3D.
4. Kind N engines: wait for real demand, or ship one "Full" GitHub flavor now?
5. Minimum Android version (affects HEIC/AVIF decoders and Photo Picker).
