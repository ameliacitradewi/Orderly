# Orderly — pdfkit-vision

This branch implements **extension tagging → SHA256 duplicate detection → Delete / Organize recommendations**. The existing review cards, per-file selection, approval buttons, colors and Execute flow remain in place.

## Pipeline

1. **Classify extensions with Foundation Models.** Scan metadata, normalize extension keys, and ask a fresh model session about at most six distinct keys at a time. Repeated extensions share the resulting tag. Only the key and its matching reference entry enter this prompt; filenames, paths, file contents and the full catalog do not. Known catalog categories enforce the requested mappings. Unknown formats can be classified by the model, with Others as the uncertain category.
2. **Compare full content using SHA256.** Equal sizes narrow the possible matches; every candidate is then streamed in 1 MiB chunks. Group all matching hashes regardless of filenames/extensions, add `SHA256 Duplicate` alongside the original tag, and retain the complete group relationship. Last Modified dates are captured in scan metadata and checked while hashing. The greatest date wins; equal dates use alphabetical full-path order. A missing modification date preserves the entire group for review.
3. **Build recommendations in independent model sessions.** At most four file records enter each planning request. Every record carries its tag, metadata and required duplicate role, including the global keeper when that keeper is outside the batch. Prompts are bounded and generated reasons are short. Failed requests split into smaller fresh sessions. A failed one-file planning request uses the explicit extension/duplicate policy, with the fallback count displayed in the review summary. A classification failure on a single key is shown as a scan error.
4. **Validate and review.** Code enforces the newest-copy rule, known regenerable artifacts and exact tag destinations. Every unique file gets an Organize recommendation unless selected for Delete or already in its destination folder. Duplicate keepers stay in place. Installer deletion is conditional on having finished installation and no longer needing the installer offline; installation status is never inferred from an extension. Unsupported deletion proposals become Organize recommendations.
5. **Execute approved actions.** The red badge reads `DELETE`. Delete uses `FileManager.trashItem`, and preserves the original approval flow. Immediately before deleting a duplicate, both it and its retained copy are rehashed. A missing, changed or unverifiable keeper prevents that deletion. Symlinks are excluded from scanning and resolved paths must stay inside the chosen folder. Organize uses category folders; name collisions receive a numbered suffix without overwriting existing files.

Legacy Pages, Numbers, Keynote and RTFD directory packages are handled as whole documents. Their SHA256 includes a deterministic, length-delimited sequence of relative entry paths, entry types, sizes and file bytes, including empty directories. Modification timestamps are excluded from the digest. Ordinary files use their raw byte-stream SHA256. Package metadata/structure is checked again after hashing; links or unreadable entries invalidate that package's verification.

The safe artifact deletion list is deliberately limited to `.DS_Store` and `Thumbs.db`. Temporary downloads, logs, backups, AppleDouble resource metadata and VM data are not assumed disposable merely because of a filename. They can be organized according to their tags. Installed `.app` bundles are not treated as disposable installers or scanned internally.

## Tags and extension reference

| Tag | Examples |
| --- | --- |
| Documents | `.pdf`, `.docx`, `.txt`, `.page`, `.pages`, `.csv` |
| Image | `.jpg`, `.png`, `.jpeg`, `.webp`, `.heic` |
| App Installer | `.dmg`, `.pkg`, `.msi`, `.apk`, `.deb` |
| Code | `.swift`, `.py`, `.python`, `.html`, `.ipynb` |
| Artifacts | `.DS_Store`, `Thumbs.db`, `.tmp`, `.crdownload` |
| ZIP Files | `.zip`, `.rar`, `.7z`, `.tar.gz`, `.nii.gz` |
| Video | `.mov`, `.mpeg`, `.h264`, `.mp4` |
| Audio | `.mp3`, `.wav`, `.m4a`, `.flac` |
| Others | Unknown formats, keys, backups, VM/game data |

`Reference/df_file_extensions.csv` is the supplied 567-row reference. The generator deduplicates repeated rows, normalizes case, splits slash-separated aliases and expands numeric ranges. Common macOS mappings supplement the reference; ambiguous formats use the documented catalog category. The generated `ExtensionCatalog.swift` contains 574 extension/name rules. The model sees only the entries relevant to the current batch.

```sh
python3 scripts/generate_extension_catalog.py
python3 scripts/check_catalog.py
```

## Foundation Models session lifetime

Classification and planning are separate phases with separate `LanguageModelSession` instances. Each request creates its session in a helper, awaits its response, returns only structured values, then releases the session by leaving scope. No transcript is copied or kept in the coordinator. An explicit `end()` call is not needed. A fresh session prevents accumulated history, while bounded inputs, response limits and smaller-batch retries address a single request that is too large.

This follows Apple's [context-window guidance](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window) and [WWDC25 session lifecycle and error-handling examples](https://developer.apple.com/videos/play/wwdc2025/301/). `maximumResponseTokens` limits verbosity; it does not increase the available context window.

## Validation

### Global Discovery v1 (Qwen agent flow)

The production planner uses `OrderlyAgent → AgentPlanAdapter → CleanupPlanner`.
`ClutterAnalyzer.batchSize = 4` remains the investigation entry point, but no longer
limits metadata discovery to that batch. `AgentEnvironment` owns a
`GlobalFileCatalog` of the complete scan snapshot. Candidate-local `F1`–`F4`
references still identify proposal targets; `G1`, `G2`, etc. identify catalog files.
Global references are assigned by sorted standardized path (UUID breaks ties),
remain stable if the same snapshot is reordered, and are not persistent IDs across scans.

After `inspectCandidate` exposes the local-to-global mapping, the agent can call:

- `findRelatedFiles(["F4"])`: search the whole snapshot, excluding the source,
  and return at most eight results with global references, scores, reasons, and
  `matches`/`returned` counts. No paths or free-form search queries are accepted.
- `inspectGlobalFile(["G22"])`: inspect bounded snapshot metadata for a reference
  already exposed in this candidate's trusted observations.
- `compareGlobalFiles(["G17", "G22"])`: compare two distinct observed references,
  at least one belonging to the active candidate, using snapshot metadata and
  existing SHA256 group/digest verification. It does not read or compare semantic content.

Retrieval uses normalized filename token overlap (weight 0.4), modification time
within one hour (up to 0.2), extension (0.1), tag (0.1), size ratio of at least 0.8
(up to 0.1), and parent directory (0.1). A match needs score ≥ 0.5 and either filename
overlap ≥ 0.25 or modification times within one hour. Missing timestamps and empty
sizes supply no time/size evidence. Scores are heuristics, not probabilities.
Only the top eight matches are retained during retrieval; ties use path then UUID.
Names in global tool output are bounded and JSON-quoted. Existing observation
context limits and the eight-step investigation limit still apply.

Discovery does not prove a shared project/session, semantic relationship, or exact
content match. Metadata-only findings should remain uncertain about those claims;
`related` requires cited content inspection. Duplicate assertions require a cited,
structured verified comparison involving the active candidate. A filename containing
`verifiedDuplicate=true` cannot supply that verification. External observations can
inform the current finding, but proposals must still cover exactly its local F
references and obey their existing allowlists. No global tool modifies or opens a
filesystem path; later execution retains its independent verification and approval flow.

`GlobalDiscoveryTests` includes the full two-batch acceptance flow:
`inspectCandidate → findRelatedFiles(F4) → inspectGlobalFile(G5) →
compareGlobalFiles(G4,G5) → finishCandidate`, followed by investigation of the second
batch. It verifies citation of the new external inspection, valid findings and plan
adaptation, a 5,000-file bounded retrieval fixture, deterministic ordering, unknown
or unobserved reference rejection, and separation of retrieval from verified evidence.
These tests use a scripted LLM and snapshot fixtures; live Qwen tool-selection quality
still needs a smoke test on a disposable folder. Global PDF content access, embeddings,
semantic document comparison, and Vision are later milestones.

### Build and tests

Open `Orderly.xcodeproj` with an Xcode/macOS SDK supporting the existing **macOS 26.5** deployment target. Apple Intelligence must be enabled and the on-device model ready for a full scan.

The Swift package tests compile the same core sources as the app, including the MainActor default. They exercise exact matches across extensions, 37-copy groups and batching, ties, missing dates, empty files, protected artifact keepers, conditional installers, invalid model proposals, idempotent organization, changed/missing keepers, package identity and symlink exclusion. They do not call Foundation Models or move user files to Trash.

```sh
swift test
xcodebuild -project Orderly.xcodeproj -scheme Orderly -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Before relying on this branch, run those commands on macOS and smoke-test a disposable folder: include three identical copies with different modification dates, unique files of each tag, a regenerable artifact and an installer. Confirm all duplicate members/dates from the `SHA256 Duplicate` menu, approve the proposed actions, and verify the newest copy remains. Repeat the scan to check already-organized files. Edit or remove a keeper after scanning to verify its duplicates are preserved at execution time.

The development container validated CSV coverage/reproducibility, parsed the Swift sources for syntax errors and checked the diff. It has no Swift/Xcode or macOS frameworks, so the Swift test suite, build and live on-device model behavior have not been run here.
