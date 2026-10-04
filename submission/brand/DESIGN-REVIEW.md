# Mathguard presentation design review

Reviewed 4 October 2026. The ten-page PDF keeps the corporate navy-and-ivory direction and introduces one consistent identity system. This revision changes presentation design and wording precision. It does not change runtime code or formal definitions.

## Design decisions

| Element | Choice | Purpose |
| --- | --- | --- |
| Logo | Open squared G enclosing a proof turnstile | Connect the guard boundary with evidence required for admission |
| Display type | Nimbus Roman, regular | Give titles an institutional editorial character |
| Body type | Nimbus Sans, regular and bold | Keep technical explanations and evidence easy to scan |
| Technical type | Nimbus Mono PS | Align financial figures and distinguish commands, indices and page numbers |
| Main palette | Navy `#101D32`, ivory `#F6F4ED` | Support a calm, high-contrast reading field |
| Accent | Brass `#9B814F`, darker text brass `#806638` | Tie identity, rules and chapter labels together without competing with evidence |
| Secondary text | Slate `#556172` | Separate explanations from headings while retaining legibility |
| Background | Restrained nested gate contours | Extend the logo's boundary metaphor on the cover and closing page |
| Composition | 72 px outer margin, fixed column starts and repeated footer coordinates | Make alignment and spacing consistent throughout the deck |
| Evidence | Open tables with fine horizontal rules and explicit column gutters | Let readers compare rows without a heavy grid |

Titles use 49 px (36.75pt), the cover uses 78 px (58.5pt), and main body text generally uses 24–29 px (18–21.75pt). Smaller type serves chapter labels, captions and footers. The serif, sans serif and monospaced faces each have a specific role.

The cover gives the logo one clear focal position and preserves its proportions. Technical pages use solid ivory. The pattern appears on the cover and closing page only. The closing page keeps sufficient text contrast over the quiet linework.

## Page review

| Page | Review result |
| --- | --- |
| 01 Identity | Logo, title and supporting text occupy distinct fields. Navy pattern preserves a quiet reading area. |
| 02 Architecture | Arrow direction is correct. Kernel emphasis identifies the enforcement point. Diagram remains native and editable. |
| 03 Decision kernel | Independent flags and the deterministic denial boundary remain clear. “At or above” matches the runtime threshold. |
| 04 Live policy | All four observed changes retain their versions and outcomes. The fixture scope remains visible. |
| 05 Resources | Numbered rows separate reservation, limits and timeout recovery. Line breaks preserve complete phrases. |
| 06 Ledger | Monospaced balances align by column. Approval and retry behavior remain explicit below the table. |
| 07 Attack boundaries | Indirect content, artifacts and finite coverage have distinct rows. No universal detection claim appears. |
| 08 Evidence | The 83-test result has clear visual priority. Other evidence and the 156-record distinction remain readable. |
| 09 Reporting | Operator visibility, sanitized export and volatile audit limits remain separate and explicit. |
| 10 Submission | Commands and remaining work occupy separate columns. The brass PR link remains clickable. |

All ten final PDF pages were rendered at 1280×720 and individually inspected. No visible text clipping, overlap, distorted logo, broken line break or body/footer collision remains at this review size.

## Export and coherence checks

- Ten pages at 16:9. Text remains searchable in the PDF.
- PDF fonts are embedded subsets of Nimbus Roman, Nimbus Sans and Nimbus Mono PS. No fallback face appears in the final PDF's text spans.
- Four tables on pages 3, 4, 6 and 8 remain native in the editable presentation. The architecture also remains editable.
- Presentation package and layout checks returned zero findings and zero layout warnings. Re-import succeeded.
- Text bounds checks found zero out-of-page spans and zero body/footer collisions.
- The PDF link points to `https://github.com/ljaniec/Mathguard/pull/5`.
- Original speaker notes and source links remain in the editable deck.
- Independent content review confirmed the 83/14/16 counts,156-record catalog distinction, balances, policy/feed versions and evidence limits. It found no material factual drift.

An early draft substituted the display face during PDF conversion. The final revision uses Nimbus Roman and verifies the embedded font. Inherited table borders and hyperlink colors were also corrected, followed by another complete export review.

| Text pair | Contrast ratio |
| --- | ---: |
| Navy on ivory | 15.34:1 |
| Slate on ivory | 5.71:1 |
| Dark brass labels on ivory | 4.92:1 |
| Light supporting text on navy | 13.08:1 |
| Brass link on navy | 9.25:1 |

These ratios describe the specified text colors against the solid background fields. They are not a full accessibility certification of the deck.

## Use and review limits

The PDF is the reviewed visual output. The PPTX is editable and may substitute fonts on a computer without the Nimbus families. The artwork is raster imagery, with the transparent logo supplied at 1254×1254. This review covers rendered exports and presentation structure, rather than native PowerPoint execution or a physical projector test.

Live-model quality, unseen evaluation, browser/operator acceptance and submission registration remain pending as stated in the deck. The redesign does not change those evidence boundaries.

See [LOGO-PROMPT.md](LOGO-PROMPT.md) for the meaning, original prompts and asset-use rules.
