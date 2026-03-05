# Documentation Reorganization Plan

This document describes the comprehensive rework of PSGadget documentation,
consolidating user-facing content under the `docs/wiki/` directory and leaving
only a slim `README.md` in the repository root. Its purpose is to provide enough
context, a detailed checklist, and milestones so that another agent or developer
can pick up the work and finish the reorganization with confidence.

> **Scope**: The entire `docs/` folder will be reshuffled. Loose markdown files
> will either be merged into the wiki directory or deleted. The `README.md`
> will be simplified to a landing page linking into the wiki.

---

## Goals

1. Eliminate duplication across several docs (INSTALL, QUICKSTART, PLATFORMS,
   PERSONAS, REFERENCE).
2. Provide a single authoritative set of documentation under `docs/wiki/`, which
   serves both as GitHub wiki content and as part of the repository.
3. Keep `README.md` minimal: introduction, very brief quick start, and a table
   of links to the wiki pages.
4. Remove or redirect old pages to avoid confusion.
5. Maintain persona-specific content via inline callouts in the examples and
   keep a short summary in the wiki where appropriate.
6. Preserve all technical content; no information loss.
7. Ensure links between pages are updated and not broken.

---

## Directory Structure After Rework

```
psgadget/
  README.md                 # slim entry point
  docs/
    wiki/
      Home.md               # navigation landing page
      Getting-Started.md    # merged INSTALL + QUICKSTART + PLATFORMS
      Hardware-Kit.md       # moved from HARDWARE_KIT.md
      Architecture.md       # moved from ARCHITECTURE.md + library-maint section
      Troubleshooting.md    # moved from TROUBLESHOOTING.md
      Function-Reference.md # existing, canonical
      Configuration.md      # existing, plus extra config details
      Daemon.md             # moved from about_PsGadgetDaemon.md
      Classes.md            # moved from REFERENCE/Classes.md
      (images/ copied or left in parent docs/images)
```

Old files outside `wiki/` will be deleted:

- INSTALL.md
- QUICKSTART.md
- PLATFORMS.md
- PERSONAS.md
- about_PsGadgetConfig.md (contents moved into Configuration.md if needed)
- docs/REFERENCE/Cmdlets.md
- docs/REFERENCE/Classes.md (moved)
- any stray about_*.md or persona files

---

## Work Items

1. **Update `README.md`**
   - Trim to introduction, simple bullets, small quick start code block, and a
     link table pointing to the nine wiki pages.
   - Remove full function table, architecture section, reproduction of
     configuration examples, and development instructions.

2. **Create or modify wiki pages**
   - `Home.md`: ensure navigation table is representative of final pages.
   - `Getting-Started.md`: compose new merged document as per earlier outline.
   - `Hardware-Kit.md`: move content with minor path updates.
   - `Architecture.md`: import existing architecture text and append the
     "Maintaining bundled libraries" section from INSTALL.md.
   - `Troubleshooting.md`: move as-is, adjusting internal links.
   - `Function-Reference.md`: keep current; ensure all cross-links from other
     pages point here.
   - `Configuration.md`: optionally merge additional content from
     about_PsGadgetConfig.md if lacking.
   - `Daemon.md`: move about_PsGadgetDaemon.md and update title.
   - `Classes.md`: move REFERENCE/Classes.md; update links.
   - Verify images remain accessible relative to new location (probably still
     `../images` or absolute paths). Adjust as necessary.

3. **Delete redundant files**
   - Remove the now-merged pages from `docs/` and `docs/REFERENCE/`.
   - Update `.gitignore` if necessary (likely unaffected).

4. **Link updates**
   - Search the repository for references to the old filenames and update them
     to point to the wiki versions (e.g. `[INSTALL.md]` -> `[Getting-Started.md]`).
   - Pay special attention to relative path changes inside the moved files.

5. **Redirect or stub**
   - In moved pages' original locations leave short stub files that either
     redirect or state "see docs/wiki/..." to help existing external links
     until the next release.
   - Optionally add GitHub redirect YAML in frontmatter (if using GitHub Pages)
     but not required.

6. **Testing and verification**
   - Render the markdown locally (e.g. using `markdown-preview-enhanced` or
     `grip`) and verify links work.
   - Run a grep for old filenames to ensure none remain in repo.
   - Optional: build a static site preview if used.

7. **Commit and document**
   - Create a dedicated branch (e.g., `docs-reorg`) for these changes.
   - Add a descriptive git commit message summarizing the renaming/deletion.
   - Add a note to CHANGELOG or release notes if applicable.
   - Update `.github/copilot-instructions.md` or other developer docs to refer to
     wiki locations if they previously referenced old paths.

---

## Milestones & Checklist

1. **Milestone 1 — Planning & initial file tree**
   - [x] Review all current documentation (completed already).
   - [x] Finalize new directory structure (see above).
   - [ ] Create `doc_organization_rework_plan.md` (this file).

2. **Milestone 2 — Wiki page preparation**
   - [ ] Create blank destination files in `docs/wiki/` for those not existing.
   - [ ] Copy/move text from original docs into new files as outlined.
   - [ ] Merge INSTALL.md and QUICKSTART.md content into Getting-Started.md.
   - [ ] Move architecture library-maint section.
   - [ ] Move persona table sections into Getting-Started.md as necessary.
   - [ ] Adjust image paths and link anchors.

3. **Milestone 3 — README and stub cleanup**
   - [ ] Rewrite README.md to new slim form.
   - [ ] Create stubs in old doc locations indicating relocation.
   - [ ] Delete redundant files from repo.

4. **Milestone 4 — Link updates & verification**
   - [ ] Perform global search/replace of old paths and filenames.
   - [ ] Verify no 404s or broken anchors in the wiki pages.
   - [ ] Run `grep -r "INSTALL.md" -n` and similar to ensure removal.
   - [ ] Optionally run `markdownlint` if project uses it to catch style issues.

5. **Milestone 5 — Commit & review**
   - [ ] Stage all changes, commit with descriptive message.
   - [ ] Push branch and open a PR against `main`/`dev1` for review.
   - [ ] After merge, update any external references (e.g., README badges,
         workspace config, etc.).

6. **Milestone 6 — Post-release cleanup**
   - [ ] Once merged and published, optionally delete stub files or convert
         them to GitHub redirects.
   - [ ] Update CHANGELOG entry to note documentation restructure.

---

## Notes for Future Contributors

- The `docs/wiki` subdirectory is meant to mirror the GitHub wiki. Editing
  files there will update both the repo and the wiki automatically.
- When writing new documentation, always check which persona it targets and
  tag sections accordingly rather than creating whole new persona pages.
- Before deleting an old file, ensure no external documentation (e.g. in the
  old PSGadget reference site) links to it; use search engine index to
  verify.
- Keep the `README.md` extremely short; the project discovery page should
  point users into the wiki as soon as possible.

---

This plan should provide enough detail for an agent or human to carry out the
reorganization while ensuring continuity and minimal user confusion.