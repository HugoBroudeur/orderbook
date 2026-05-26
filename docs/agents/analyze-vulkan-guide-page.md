# How to explain a Vulkan Guide page

Reusable instructions for analyzing a [Vulkan Guide](https://vkguide.dev/) webpage (or similar tutorial page). Paste or reference this file when asking for a broad-strokes write-up.

---

## Goal

Produce a **page-faithful** analysis: help the reader understand what *that specific page* teaches, in plain language, without turning it into a general Vulkan lecture.

---

## Input (fill in per request)

| Field | Example |
|-------|---------|
| **URL** | `https://vkguide.dev/docs/new_chapter_3/blending/` |
| **Output path** | `delivery/analysis/Vulkan Guide — Blending (Chapter 3).md` |
| **Reader context** *(optional)* | e.g. “I use dynamic rendering; avoid legacy render-pass framing unless in External notes.” |
| **Depth** | Broad strokes (default) — not a line-by-line transcript |

---

## Rules for the analyst

### 1. The page is the single source of truth

- Base **claims, terms, and scope** on the page content only.
- **Mirror the page’s vocabulary.** If the page says “the image we are rendering into,” use that — do not substitute “framebuffer,” “render pass,” “color attachment,” etc. in the main summary.
- If the page names a symbol (`PipelineBuilder`, `init_mesh_pipeline()`, `srcColor`), use those names.
- Do not attribute concepts to the page that it never mentions.

### 2. Separate page content from external context

Structure the output in distinct sections:

| Section | Purpose |
|---------|---------|
| **A. Page summary** | What the page says — main deliverable |
| **B. What the page does *not* say** | Topics absent from the page (inferred from omission) |
| **C. Takeaways** | Short page-only recap (one paragraph) |
| **D. External notes** *(optional)* | Broader Vulkan context, modern API mapping, reader-specific notes — **clearly labeled, skippable** |

Never blend external knowledge into sections A–C without marking it.

### 3. Citation discipline

For each important claim in section A, either:

- **Paraphrase faithfully** from the page, or
- **Quote** a short phrase when the exact wording matters (e.g. definitions of source/destination).

When adding anything not on the page, prefix with: *External note*, *Inferred*, or *Not on page*.

### 4. Formula and code

- Reproduce formulas **as the page gives them** (including simplified RGB forms if the page derives them).
- Mention code changes the page asks the reader to make (function names, which line to swap).
- Do not invent extra refactors, abstractions, or “best practices” the page does not discuss.

### 5. Anti-goals (do not do these in the main summary)

- Do not “upgrade” tutorial language to textbook or spec language.
- Do not explain legacy vs modern Vulkan paths unless the reader asked and it goes in section D.
- Do not fill gaps with production-engine advice (sorting, premultiplied alpha, etc.) unless listed under “does not say” or External notes.
- Do not assume prior chapters beyond what the page itself references.

### 6. Tone and length

- Broad strokes: enough to grasp purpose, core idea, main steps, and what comes next on the page.
- Prefer tables and short bullets over long prose.
- Write for someone who has **not** read the page but may follow the tutorial later.

---

## Output template

Use this skeleton for each new analysis file:

```markdown
# Vulkan Guide — [Topic] ([Chapter])

**Date:** YYYY-MM-DD
**Source:** [URL]
**Audience:** Broad-strokes understanding of what the page teaches.

**Analysis rules used:** Page-faithful summary; external context only in section D.

---

## A. Page summary

### A.1. Why this page exists
### A.2. Core idea(s)
### A.3. Key terms (page definitions)
### A.4. Main mechanics / formulas / APIs the page introduces
### A.5. What the page has you do (hands-on steps)
### A.6. What comes next (if stated on the page)

---

## B. What the page does *not* say

| Topic | On the page? |
|-------|----------------|
| … | No / Yes |

---

## C. Takeaways (page-only)

One paragraph.

---

## D. External notes (not on the page)

*Optional. Omit entirely if nothing useful to add.*

### D.1. Mapping page terms to common Vulkan docs
### D.2. Reader-specific context (e.g. dynamic rendering)
### D.3. Other inferred context, clearly labeled
```

Adjust subsection titles to fit the page (e.g. a shader page might use “Shader stages” instead of “Formulas”).

---

## Example prompt (copy-paste)

```text
Read [URL] and write a broad-strokes analysis to:
delivery/analysis/Vulkan Guide — [Topic].md

Follow the rules in delivery/analysis/how to explain vulkan guide.md:

- Sections A–C: page-faithful only; use the page’s terminology
- Section D: optional external notes only, clearly labeled
- Include “what the page does not say”
- Reader context: [e.g. dynamic rendering — no render pass / framebuffer language in A–C]

Do not add general Vulkan lectures or concepts the page never mentions.
```

---

## Quick checklist (for reviewer or agent)

- [ ] Section A uses only terms the page uses (or direct paraphrases)
- [ ] `dstColor` / destination defined as the page defines it
- [ ] No framebuffer / render pass / attachment jargon in A–C (unless the page uses them)
- [ ] Formulas match the page’s derivations
- [ ] Hands-on steps match the page’s instructions
- [ ] Section B lists meaningful omissions, not invented criticisms
- [ ] Section C is one paragraph, no external concepts
- [ ] Section D is clearly skippable and labeled

---

## Why these rules exist

Tutorial pages often use **intentionally simple language**. Replacing that with spec or legacy API terms (e.g. saying “framebuffer” when the page says “the image we are rendering into”) adds confusion and misattributes ideas to the tutorial. Keeping external context in section D preserves accuracy for readers who want more depth without polluting the page summary.
