# “Listen with Alto” service plan

Date: 2026-09-13. Status: implemented (service, cleaner with rich-text signals,
setting, tests, install registration). Manual host checks are listed in
[verification](verification.md). Companion to the
[implementation plan](implementation-plan.md).

## What changed after review

The first draft was revisited before implementation. Four things were done
differently:

- One setting, **Skip page clutter**, governs the service, Read Clipboard and
  Paste. The draft had the cleaner always on for the service and gated
  elsewhere, which is two mental models for one feature. The selection
  shortcut stays untouched; users select exactly what they want there.
- Article titles survive. Dropping every run of short lines also drops the
  headline that follows site navigation. The cleaner peels up to two
  heading-like lines off the end of a navigation run when prose follows, and
  a link-only line never counts as a heading.
- Legal footers are recognised by wording (license, copyright, cookie or
  privacy policy, “powered by”) rather than by position, since a “drop the
  last block after the footer menu” rule is fragile and takes real closing
  paragraphs with it.
- Rich-text signals shipped in the first release rather than as a later
  milestone: WebKit hosts hand Services RTF, so link density and attachment
  removal were cheap to include, and they are what makes “related posts”
  lists and images disappear reliably.

## Outcome

Add **Listen with Alto** to the Services submenu that macOS shows in the
right-click menu and in `App menu → Services` of any Cocoa or WebKit app with
selected text. Choosing it sends the selection to Alto, which strips page
clutter (navigation, share prompts, captions, forms, footers) and reads the
remaining prose with the existing capture → `SpeechText.prepare` →
`TextChunker` → worker → player pipeline. The example is selecting an entire
[Sentiers issue](https://sentiers.media/lifted-af-cyborgs-centaurs-and-cyberpunks/)
in a browser and hearing only the article.

The service needs neither Accessibility permission nor the clipboard-borrowing
fallback: the host app writes the selection to a private pasteboard that macOS
hands to Alto. This becomes the third reading route beside the shortcut and
Read Clipboard, and the only one that works everywhere without setup.

## What a whole-page selection contains

Fetching the example page and flattening it to plain text the way a browser's
Select All → Copy roughly does yields 54 blocks and about 2,000 words. The
article proper is about 1,800 words in 40 blocks. Everything else is noise:

| Position | Noise blocks |
| --- | --- |
| Top | Site title, then six one-word navigation links (`About`, `Articles`, `Back issues`, `Membership`, `Sign in`, `Subscribe`), the date, `7 min read`, a repeated title |
| Inside | An image caption (`Ernst Chladni, 1787, … Image sourced from …`), `Share by email`, a share request paragraph, section headings |
| Bottom | Newsletter tagline, an email placeholder plus `Subscribe`, four footer links, a license and land-acknowledgement paragraph |

A live browser selection adds more than this flattening shows: list bullets,
tab-separated table cells, `Skip to content`, cookie banners, comment widgets,
and hidden-by-CSS text that some browsers still copy. Images do not arrive as
images in plain text, but their alt text and captions do; in RTFD they arrive
as attachments that must be dropped. Any cleaner has to tolerate all of that
and still leave short, legitimate lines (headings, footnote markers, `Asides`)
when they sit inside the article.

## Options for the menu entry

| Option | How it appears | Cost | Verdict |
| --- | --- | --- | --- |
| **A. NSServices provider (recommended)** | `Services → Listen with Alto` in right-click menus and the app menu of every app that supports text services; user can attach a keyboard shortcut in System Settings | ~40 lines: an `NSServices` entry in Info.plist, one `@objc` handler, `NSApp.servicesProvider` | Native, zero user setup, no Accessibility needed |
| B. URL scheme + user-installed Shortcuts Quick Action | Appears under `Services → Quick Actions` only after the user builds or imports a Shortcut that receives text and opens `alto://read` | URL scheme handler in Alto plus a documented Shortcut; URL length caps the text, so the Shortcut would have to stage text through a file or the clipboard | Fallback for scripting; not the primary route |
| C. Share extension | Share sheet, not the Services menu; Safari shares the page URL rather than selected text unless text is selected | Separate sandboxed extension target, app-group handoff, notarization implications | Wrong menu and heavier; skip |
| D. Keep the shortcut only | Already works via AX/Copy, but needs Accessibility, and Chrome's Select All + shortcut still reads everything | Nothing | Does not meet the request |

Option A details:

- Info.plist gains one `NSServices` entry: `NSMenuItem.default = "Listen with Alto"`,
  `NSMessage = "listenWithAlto"`, `NSPortName = "Alto"`, no return types, no
  default key equivalent (users assign one in Keyboard Shortcuts → Services).
  `NSSendTypes` lists the legacy names first, `NSStringPboardType` and
  `NSRTFPboardType`, then `public.utf8-plain-text` and `public.rtf`. Declaring
  only the UTI spellings hid the item in Chrome: AppKit asks the host whether
  it can provide each declared type by name, and Chromium compares the
  request to the legacy constant literally, as do Apple's own services and
  Raycast in `pbs -dump`. Cocoa hosts accept either spelling.
- `project.yml` currently sets `GENERATE_INFOPLIST_FILE: YES`. Add an `info:`
  block with a `properties` dictionary so XcodeGen writes the entry into the
  generated plist, then regenerate the project. The generated keys still merge.
- `AppDelegate.applicationDidFinishLaunching` sets `NSApp.servicesProvider` to a
  small `ServiceProvider` object exposing
  `@objc func listenWithAlto(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>)`.
  If Alto is not running, macOS launches it and delivers the request after
  launch, so the provider must be installed before the diagnostic early returns
  in that method finish, and before setup prompts.
- New third-party services are listed but **unchecked** in System Settings →
  Keyboard → Keyboard Shortcuts → Services on macOS 26, so the item stays out
  of every menu until the user ticks it. There is no API for an app to enable
  its own service. `install-app.sh` writes the `pbs` `NSServicesStatus` entry
  on the developer's machine; end users need the one-time checkbox, which the
  guide and README now state up front.
- Exactly one copy of Alto may be registered. `install-app.sh` used to keep
  the previous build in a hidden `/Applications/.alto-install.*` folder, and
  LaunchServices scans those, so `pbs -dump_cache` listed six providers for
  the same bundle identifier and service, and the item stayed out of every
  app's Services submenu. The script now stages in `/private/tmp`,
  unregisters the previous copy and the build and `dist` bundles, and flushes
  `pbs`.
  Spotlight re-registers `dist/Alto.app` after every build regardless, so
  the script now deletes it once the install succeeds.
- LaunchServices registers services when the bundle lands in `/Applications`.
  During development, `lsregister -f /Applications/Alto.app` and
  `/System/Library/CoreServices/pbs -update` refresh the registry; `pbs -dump`
  lists what macOS currently knows. Add the refresh to `scripts/install-app.sh`.
- Apps expose only the types they can produce. Safari, Mail, Notes and other
  WebKit or `NSTextView` hosts offer RTF and plain text; Chromium (Chrome, Arc,
  Electron apps) is expected to offer plain text only. HTML is not available
  through Services in practice. Milestone 1 verifies this on the real hosts.
- Hardened runtime stays on; Services need no entitlement and no sandbox change.

## Options for cleaning the text

The cleaner runs before `AppModel.read`, so `SpeechText.prepare`, language
detection, chunking and the 100,000-character cap remain unchanged. Options 1
and 2 are implemented in `Sources/AltoCore/PageText.swift`.

| Option | Input | Approach | Verdict |
| --- | --- | --- | --- |
| **1. Block heuristics on plain text (required)** | Any string | Split into blocks, score each block, keep the contiguous prose region, drop link-list runs and boilerplate | Works for every host, including Chrome; the base layer |
| **2. Rich-text signals (implemented)** | RTF/RTFD when the host offers it | Parse with `NSAttributedString(rtf:)`, drop attachments, compute per-paragraph link density and font size, feed those as extra features into option 1 | Cheap once 1 exists; makes navigation and small-print detection reliable in Safari, Mail, Notes |
| 3. HTML DOM extraction | `public.html` from the general pasteboard after a browser Copy | `XMLDocument(data:options:.documentTidyHTML)`, remove `nav/header/footer/aside/form/figure/img/script/style`, prefer `article`/`main`, then option 1 on the result | Not reachable from Services, but improves Read Clipboard and the editor's Paste; later phase |
| 4. Off-screen `WKWebView` + Readability.js | HTML | Load in a hidden web view, inject Mozilla Readability, read `textContent` | Rejected: HTML is rarely available, adds JavaScript and a notice, main-thread web view work, and 200 ms or more per request |

### Block heuristics (option 1), as implemented

Inspired by the text-density rules in Boilerpipe's article extractor, adapted
to text without link markup. Everything is deterministic and unit-tested.

1. Normalise with `SpeechText.prepare(trim: false)` and split on newlines
   into blocks. Rich text is split by paragraph first so each block carries a
   link density; attachments (images) are removed before flattening.
2. Classify every block as **prose**, **short** or **clutter**. Prose has at
   least 12 words, or at least 6 words ending in terminal punctuation, or is a
   bulleted or numbered item with at least 4 words. Clutter is: no letters at
   all; up to 8 words that are a bare URL, an email address, a date, a
   “7 min read” line, a `©` line, or a short menu phrase (`Skip to content`,
   `Sign in`, `Subscribe`, `Share`, `Menu`, `Read more`, …); up to 60 words
   mentioning cookies with accept/consent wording, or legal wording (`all
   rights reserved`, `creative commons`, `privacy policy`, `powered by`); up
   to 40 words that read like an image caption (`Photo by`, `Image sourced`,
   `Credit:`, stock-photo names). A block whose characters are at least 60%
   links is never prose. Everything else is short.
3. Remove runs of three or more consecutive non-prose blocks (navigation and
   footer menus). When prose follows the run, up to two trailing short blocks
   with at least three words each are kept as the title or heading. Clutter
   blocks are removed even outside runs.
4. Before the first kept prose block, keep at most two heading-like blocks;
   after the last one, keep nothing.
5. Drop later exact duplicates (titles repeated in headers).
6. Guardrail: if no prose survives, or fewer than 50 words or under a quarter
   of the input words survive, return the prepared original text instead.
   Menus, short notes and ordinary selections therefore pass through
   unchanged. The fallback is silent; the developer preview above the player
   shows what will be read.
7. Kept blocks are joined with blank lines, so `TextChunker` still sees
   paragraph boundaries.

On the example page these rules remove the site chrome, date and read time,
the caption, `Share by email`, the newsletter form, the footer menu and the
license paragraph, and keep the title, subtitle, every section heading, the
footnote and all body paragraphs in order. The share request paragraph stays:
it is prose, and a longer phrase list would over-fit one site.

### Rich-text signals (option 2)

When the pasteboard offers `public.rtf`, it is parsed into an attributed
string and walked by paragraph. Each block gets a link density (fraction of
non-whitespace characters carrying `.link`); attachments are dropped before
flattening so images never become “￼” in the speech text. Blocks at or above
60% links are never prose and never headings, so tag clouds and related-post
lists go even when their lines are long. Cocoa's RTF reader turns `HYPERLINK`
fields back into `.link`, which a unit test confirms through a real pasteboard
round trip. Font-size small-print detection was left out: it needs the
document's median size and gained little on the pages tried.

## Recommended design

Flow: host app → private pasteboard → `ServiceProvider` → `PageText.extract`
(AltoCore) → `AppModel.read(text, source: .service)` → existing reading.
Reading starts immediately, like the shortcut. The player appears; the
developer preview shows the filtered text so the user can see what was dropped.

Code placement:

| Piece | Location |
| --- | --- |
| `PageText` (block model, scoring, guardrail, RTF feature extraction) | `Sources/AltoCore/PageText.swift`, pure, no AppKit UI |
| `ServiceProvider` and `NSApp.servicesProvider` wiring | `Sources/AltoUI/ServiceProvider.swift`, called from `AppDelegate` |
| `AppModel.readService(_:)` and the shared pasteboard reading path | `Sources/AltoUI/AppModel.swift` |
| Setting: **Skip page clutter** (default on) under Settings → Reading | `SettingsView.swift`, key `skipPageClutter` |
| Info.plist service entry | `project.yml` `info.properties` → generated `Support/Info.plist`, regenerated project |
| Registry refresh after install | `scripts/install-app.sh` |

Scope of the cleaner: the **Skip page clutter** setting (default on) applies
to the service, Read Clipboard and the editor's Paste. The shortcut path keeps
its current behaviour, since users usually select exactly what they want
there; revisit after real use.

Errors: the service handler must return quickly and never throw across the
service boundary. It validates with `SelectionReader.checked`, hands the text
to `AppModel`, and reports failures through the existing `message` and settings
window. If no model is installed, the existing “Download and select a voice
model” path is reused. The private service pasteboard is never written back to
the general pasteboard.

## Milestones

Milestones 1 to 3 and the setting from 4 are done; the HTML path in 4 and the
host matrix in 5 remain.

1. **Service plumbing.** Info.plist entry, provider, install-script refresh.
   Acceptance: `Listen with Alto` appears in Safari, Chrome, TextEdit, Notes and
   Mail right-click menus on the installed copy, launches Alto if needed, and
   reads the selection unchanged. Record which hosts offer RTF versus plain
   text only, and which Electron apps show no Services submenu.
2. **Plain-text cleaner.** `PageText` with the rules above and unit tests on
   fixtures: the example page as flattened text, a Wikipedia-style page with
   sidebar and references, a short email, a pure-prose selection that must pass
   through untouched, and a navigation-only selection that must trigger the
   guardrail. Add the **Skip page clutter** setting.
3. **Rich-text signals.** Parse RTF/RTFD when offered, add link density, font
   size and attachment handling, and extend tests with a generated RTF fixture.
4. **Clipboard and editor parity.** Apply the cleaner to Read Clipboard and
   Paste behind the setting. Optionally read `public.html` there via the tidy
   DOM path; decide after measuring how much it adds over the RTF path.
5. **Docs and verification.** Update `docs/guide.md` (new route, no
   Accessibility needed, how to enable or add a shortcut in Keyboard Settings),
   the README feature list, and `docs/verification.md` with host results.
   Update `.ultra/todo.md` with actual completion.

## Verification

- `swift test` covers `PageText` classification, guardrail, duplicate removal,
  paragraph preservation and the pass-through case. Fixtures live in the test
  target as string literals or `resources:` in `Package.swift`.
- Manual, silent by default: on the installed app, select all in the example
  page in Safari and Chrome, choose the service, and compare the developer
  preview with the article body. Repeat with a PDF selection in Preview, a
  Notes note, a Mail message, Slack, and a secure text field (the service must
  not appear or must receive nothing).
- Confirm the service still works when Alto is not running and when it is mid
  reading (replaces the session, like the shortcut).
- Confirm nothing lands on the general pasteboard: `pbpaste` before and after
  must match.

## Limits to document

- Services only exist in apps that implement them; some Electron and
  cross-platform apps show no Services submenu. Read Clipboard remains the
  fallback there.
- Cleaning is heuristic. Sidebars written as full sentences, pull quotes and
  comment threads can survive; short legitimate lines inside dense link lists
  can be lost. The preview shows what will be read; the guardrail prevents
  reading nothing.
- Plain-text hosts give no link or image information, so results in Chrome are
  slightly worse than in Safari.
- macOS may need `pbs -update` or a logout before a freshly installed service
  appears, and users can disable any service in Keyboard Shortcuts → Services.

## Decisions taken

- The service starts reading immediately, like the shortcut. An editor route
  (`Open in Alto Editor`) can be added later as a second service entry.
- The cleaner does not run on the shortcut path.
- No default key equivalent ships; users can assign one in System Settings →
  Keyboard → Keyboard Shortcuts → Services.

## Still to verify by hand

- Which hosts show the item and what they send: Safari, Chrome, TextEdit,
  Notes, Mail, Preview, Slack. Chromium hosts are expected to send plain text
  only. Record results in [verification](verification.md).
- Behaviour when Alto is not running (launch on demand) and when it is mid
  reading (session replacement).
- Listening acceptance of the cleaned example page, including that headings
  read as pauses rather than run into the next paragraph.
