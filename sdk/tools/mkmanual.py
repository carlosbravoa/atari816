#!/usr/bin/env python3
"""mkmanual.py - build the Atari816 manual (a static HTML site) from the Markdown sources.

    python3 sdk/tools/mkmanual.py -o DIR [--check] [--repo-url BASE] [--allow-missing]
    python3 sdk/tools/mkmanual.py --list

The Markdown files stay the only source: this script turns the pages listed in MANIFEST
(below: an explicit list, nothing else of the tree is read) into DIR/*.html, with a
sidebar of every section and page, previous / next links, and DIR/style.css (from
sdk/tools/manual/style.css). The site is never committed; .github/workflows/pages.yml
builds it.

Links between the documents:
  - a relative link to another page of the manifest becomes a link to its HTML page
    (an #anchor is kept: headings get GitHub's ids, so the anchors of the Markdown work);
  - a link to an image (.png .jpg .gif .svg .webp) of the repository copies the image
    into DIR/img/ (the repository's path below it) and links it; only images that a page
    uses are copied;
  - a link to any other file or folder of the repository (source code, a Makefile) is
    shown as its text without a link, or, with --repo-url BASE, as a link to BASE + path
    (BASE such as https://github.com/OWNER/REPO/blob/main/);
  - http(s) and mailto links stay as they are.
A relative link whose target does not exist is printed as a warning (a fault of the
document) and shown as text.

Privacy guard: the build fails when a page's source holds a name of a private project
(PRIVATE below), naming the file and the line.

--check: after the build, every internal href and src of the generated HTML must resolve
(the file exists, and an #anchor exists in that page); exit 1 with a list of the broken
ones. --allow-missing: build without the manifest pages that do not exist (otherwise a
missing page is an error). --list: print the manifest.

Python 3 standard library only. The Markdown converter below handles what these
documents use (GitHub's flavour): ATX headings, paragraphs, nested lists, pipe tables,
fenced and indented code, block quotes, rules, inline code, emphasis, links, images,
autolinks and bare URLs; any other HTML in the text is escaped (shown as written), except
<br>, <kbd>, <sub>, <sup> and block-level HTML that starts a paragraph (<div>, <svg>,
<figure>, <details>, <table>, <picture>, <p>, <img>).
"""
import codecs
import html
import os
import re
import shutil
import sys
import time
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CSS = os.path.join(HERE, "manual", "style.css")

# ---- the manifest: (section title, [(source path from the repository's root, label)])
# The first page is the front page (index.html). Add a page here to publish it; read it
# first: the site may be public while the repository is not.
MANIFEST = [
    ("Start here", [
        ("sdk/docs/README.md", "The SDK manual"),
        ("README.md", "The project"),
        ("sdk/docs/getting-started.md", "Getting started"),
    ]),
    ("Architecture and components", [
        ("Docs/architecture/README.md", "The whole system"),
        ("Docs/architecture/hardware.md", "Hardware"),
        ("Docs/architecture/horizon.md", "Horizon"),
        ("Docs/architecture/emulator.md", "The emulator"),
        ("Docs/architecture/sdk.md", "The SDK"),
        ("Docs/architecture/solid.md", "What makes it solid"),
        ("Docs/01-architecture-design.md", "Architecture design"),
        ("Docs/02-register-spec.md", "Register specification"),
        ("horizon/ABI.md", "Horizon's ABI"),
    ]),
    ("Programming in C", [
        ("sdk/docs/c/getting-started.md", "Getting started with C"),
        ("sdk/docs/c/apps.md", "Window applications"),
        ("sdk/docs/c/games.md", "Games: hgame"),
        ("sdk/docs/c/porting.md", "Porting C"),
        ("sdk/docs/c/reference.md", "C reference"),
        ("sdk/docs/c/compiler.md", "The compiler, cc816"),
        ("sdk/docs/c/library.md", "The C library"),
        ("sdk/docs/c/syscalls.md", "Syscalls from C"),
    ]),
    ("Programming in assembly", [
        ("sdk/docs/reference/README.md", "Programmer's reference"),
        ("sdk/docs/reference/program.md", "Programs"),
        ("sdk/docs/reference/system.md", "Tasks, time, memory"),
        ("sdk/docs/reference/files.md", "Files and folders"),
        ("sdk/docs/reference/internet.md", "The internet"),
        ("sdk/docs/reference/windows.md", "The window system"),
        ("sdk/docs/reference/drawing.md", "Drawing"),
        ("sdk/docs/reference/controls.md", "The controls library"),
        ("sdk/docs/reference/ulib.md", "ulib and macros"),
        ("sdk/docs/reference/sound.md", "Sound"),
        ("sdk/docs/reference/classic.md", "The classic Atari"),
        ("sdk/docs/reference/printing.md", "Printing"),
        ("sdk/docs/reference/games.md", "Games calls"),
        ("sdk/docs/reference/hardware.md", "The hardware"),
        ("sdk/docs/reference/performance.md", "Performance"),
        ("sdk/docs/reference/game-patterns.md", "Game patterns"),
        ("sdk/docs/reference/limits.md", "Limits"),
    ]),
    ("Tools and testing", [
        ("sdk/docs/tools.md", "Tools"),
        ("sdk/docs/testing.md", "Testing"),
        ("sdk/docs/apps.md", "Apps and packaging"),
        ("emu/README.md", "emu816, the emulator"),
    ]),
    ("Ports", [
        ("ports/digger/README.md", "Digger"),
        ("ports/digger/PORTING-NOTES.md", "Digger: porting notes"),
        ("ports/xargon/README.md", "Xargon"),
        ("ports/xargon/PORTING-NOTES.md", "Xargon: porting notes"),
        ("ports/prince/README.md", "Prince of Persia"),
        ("ports/prince/PORTING-NOTES.md", "Prince of Persia: porting notes"),
        ("ports/simcity/README.md", "Micropolis"),
        ("ports/xcom/README.md", "X-COM (XCOM-XT)"),
        ("ports/skyroads/README.md", "SkyRoads (experiment)"),
    ]),
    ("Hardware and the PC link", [
        ("core/README.md", "The FPGA core"),
        ("core/KNOWN_ISSUES.md", "Known issues"),
        ("Docs/04-pc-link.md", "The PC link protocol"),
        ("tools/README.md", "The PC link gateway"),
    ]),
]

# text that must never reach the site (other projects' names, local paths, private host
# addresses): case-insensitive substrings
# They are kept in rot13, so that no file of the repository spells them (a search of the
# tree for them finds nothing): the names of private projects, a developer's home folder,
# a private network's addresses.
PRIVATE = tuple(codecs.decode(w, "rot13") for w in
                ("pvivyvm", "pviq", "oht jnef", "ohtjnef", "urqtrjnef",
                 "/ubzr/pneybf")) + (".".join(("192", "168", "")),)

IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")
BRAND = "Atari816"
SUBTITLE = "SDK and system manual"


def page_name(src, front=None):
    """the HTML file of a source: sdk/docs/c/compiler.md -> sdk-docs-c-compiler.html;
    the front page (the manifest's first page that exists) is index.html"""
    if src == front:
        return "index.html"
    return re.sub(r"[^a-z0-9.-]+", "-", src[:-3].lower()) + ".html"


# ---------------------------------------------------------------- inline Markdown

ESCAPABLE = "\\`*_{}[]()#+-.!|<>~\"'$&:;=?@^"


class Inline:
    """inline Markdown to HTML; link targets go through the page's resolver"""

    def __init__(self, resolve):
        self.resolve = resolve
        self.store = []

    def hold(self, s):
        self.store.append(s)
        return "\x00%d\x00" % (len(self.store) - 1)

    def restore(self, s):
        while "\x00" in s:
            s = re.sub(r"\x00(\d+)\x00", lambda m: self.store[int(m.group(1))], s)
        return s

    def render(self, text):
        return self.restore(self._render(text))

    def _render(self, t):
        # code spans first: nothing inside them is Markdown
        def code(m):
            body = m.group(2)
            if body.startswith(" ") and body.endswith(" ") and body.strip():
                body = body[1:-1]
            body = body.replace("\n", " ")
            return self.hold("<code>" + html.escape(body, quote=False) + "</code>")
        # backslash escapes (but not inside code spans: split around them)
        parts = re.split(r"((?<!`)(`+)(?!`)(?:.+?)(?<!`)\2(?!`))", t, flags=re.S)
        out = []
        i = 0
        while i < len(parts):
            seg = parts[i]
            if i % 3 == 1:
                out.append(re.sub(r"^(`+)(.+?)\1$", code, seg, flags=re.S))
                i += 2
                continue
            seg = re.sub(r"\\([" + re.escape(ESCAPABLE) + "])",
                         lambda m: self.hold(html.escape(m.group(1))), seg)
            out.append(seg)
            i += 1
        t = "".join(out)
        # autolinks <https://...>
        t = re.sub(r"<((?:https?|ftp)://[^\s<>]+)>",
                   lambda m: self.hold(self.link_html(m.group(1),
                                                      html.escape(m.group(1)))), t)
        # the few inline tags passed through
        t = re.sub(r"</?(?:kbd|sub|sup)>|<br\s*/?>", lambda m: self.hold(m.group(0)), t)
        # images, then links
        t = re.sub(r"!\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)",
                   self.image, t)
        t = re.sub(r"\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\s*<?([^)\s>]*(?:\([^)\s]*\)[^)\s>]*)?)>?"
                   r"(?:\s+\"[^\"]*\")?\s*\)", self.link, t)
        # bare URLs
        t = re.sub(r"(?<![\w/\"'=])(https?://[^\s<>\x00]*[^\s<>\x00.,;:!?)\]'\"*_])",
                   lambda m: self.hold(self.link_html(m.group(1), html.escape(m.group(1)))),
                   t)
        return self.emphasis(html.escape(t, quote=False))

    def emphasis(self, t):
        t = re.sub(r"\*\*(?=\S)(.+?)(?<=\S)\*\*", r"<strong>\1</strong>", t, flags=re.S)
        t = re.sub(r"(?<![\w])__(?=\S)(.+?)(?<=\S)__(?![\w])", r"<strong>\1</strong>", t, flags=re.S)
        t = re.sub(r"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])", r"<em>\1</em>", t, flags=re.S)
        t = re.sub(r"(?<![\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w])", r"<em>\1</em>", t, flags=re.S)
        t = re.sub(r"~~(?=\S)(.+?)(?<=\S)~~", r"<del>\1</del>", t, flags=re.S)
        return t

    def link_html(self, href, inner):
        return '<a href="%s">%s</a>' % (html.escape(href), inner)

    def image(self, m):
        alt, src = m.group(1), m.group(2)
        url = self.resolve(src, image=True)
        if url is None:
            return self.hold(html.escape("[image: %s]" % alt))
        return self.hold('<img src="%s" alt="%s" loading="lazy">' %
                         (html.escape(url), html.escape(alt)))

    def link(self, m):
        text, href = m.group(1), m.group(2)
        inner = self._render(text)
        url = self.resolve(href, image=False)
        if url is None:
            return self.hold(inner)
        return self.hold(self.link_html(url, inner))


def plain(html_text):
    """the text of rendered HTML (for slugs and titles)"""
    return html.unescape(re.sub(r"<[^>]+>", "", html_text))


def slug(text, used):
    s = text.strip().lower()
    s = re.sub(r"[^\w\- ]", "", s)
    s = s.replace(" ", "-")
    base, n = s, 1
    while s in used:
        s = "%s-%d" % (base, n)
        n += 1
    used.add(s)
    return s


# ---------------------------------------------------------------- block Markdown

LIST_RE = re.compile(r"^( {0,3})([-*+]|\d{1,9}[.)])( +|$)(.*)$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([^`\s]*)[^`]*$")
HR_RE = re.compile(r"^ {0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$")
HEAD_RE = re.compile(r"^ {0,3}(#{1,6})(?:\s+(.*?))?(?:\s+#+)?\s*$")
TABLE_SEP_RE = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")
HTML_BLOCK_RE = re.compile(r"^ {0,3}<(div|svg|figure|details|table|picture|p|img|section|"
                           r"!--)[\s>/]", re.I)


def expand_tabs(line):
    return line.expandtabs(4)


class Doc:
    def __init__(self, inline):
        self.inline = inline
        self.used_ids = set()
        self.headings = []          # (level, id, text)

    def blocks(self, lines, tight=False):
        out = []
        i = 0
        n = len(lines)
        para = []

        def flush():
            if para:
                text = "\n".join(l.strip() for l in para)
                body = self.inline.render(text)
                body = re.sub(r" {2,}\n", "<br>\n", body)
                out.append(body if tight else "<p>%s</p>" % body)
                para.clear()

        while i < n:
            line = lines[i]
            if not line.strip():
                flush()
                i += 1
                continue
            m = FENCE_RE.match(line)
            if m:
                flush()
                fence = m.group(1)
                lang = m.group(2)
                indent = len(line) - len(line.lstrip(" "))
                body = []
                i += 1
                while i < n and not re.match(r"^ {0,3}" + re.escape(fence[0]) + "{" +
                                             str(len(fence)) + r",}\s*$", lines[i]):
                    l = lines[i]
                    body.append(l[min(indent, len(l) - len(l.lstrip(" "))):])
                    i += 1
                i += 1
                cls = ' class="language-%s"' % html.escape(lang) if lang else ""
                out.append("<pre><code%s>%s</code></pre>" %
                           (cls, html.escape("\n".join(body), quote=False)))
                continue
            m = HEAD_RE.match(line)
            if m:
                flush()
                level = len(m.group(1))
                inner = self.inline.render(m.group(2) or "")
                hid = slug(plain(inner), self.used_ids)
                self.headings.append((level, hid, plain(inner)))
                out.append('<h%d id="%s">%s</h%d>' % (level, hid, inner, level))
                i += 1
                continue
            if HR_RE.match(line) and not (para and re.match(r"^ {0,3}-+\s*$", line)):
                flush()
                out.append("<hr>")
                i += 1
                continue
            if para and re.match(r"^ {0,3}(=+|-+)\s*$", line):
                # a setext heading
                level = 1 if line.strip()[0] == "=" else 2
                inner = self.inline.render("\n".join(l.strip() for l in para))
                para.clear()
                hid = slug(plain(inner), self.used_ids)
                self.headings.append((level, hid, plain(inner)))
                out.append('<h%d id="%s">%s</h%d>' % (level, hid, inner, level))
                i += 1
                continue
            if "|" in line and i + 1 < n and TABLE_SEP_RE.match(lines[i + 1]) and \
                    "-" in lines[i + 1]:
                flush()
                i = self.table(lines, i, out)
                continue
            if re.match(r"^ {0,3}>", line):
                flush()
                quote = []
                while i < n and lines[i].strip() and (re.match(r"^ {0,3}>", lines[i]) or
                                                      quote):
                    quote.append(re.sub(r"^ {0,3}> ?", "", lines[i]))
                    i += 1
                out.append("<blockquote>%s</blockquote>" % self.blocks(quote))
                continue
            lm = LIST_RE.match(line)
            if lm and (not para or (lm.group(4).strip() and
                                    (lm.group(2) in "-*+" or lm.group(2) in ("1.", "1)")))):
                flush()
                i = self.list(lines, i, out)
                continue
            if not para and line.startswith("    "):
                body = []
                while i < n and (lines[i].startswith("    ") or not lines[i].strip()):
                    body.append(lines[i][4:])
                    i += 1
                while body and not body[-1].strip():
                    body.pop()
                out.append("<pre><code>%s</code></pre>" %
                           html.escape("\n".join(body), quote=False))
                continue
            if not para and HTML_BLOCK_RE.match(line):
                block = []
                while i < n and lines[i].strip():
                    block.append(lines[i])
                    i += 1
                out.append("\n".join(block))
                continue
            para.append(line)
            i += 1
        flush()
        return "\n".join(out)

    def table(self, lines, i, out):
        def cells(row):
            row = row.strip()
            if row.startswith("|"):
                row = row[1:]
            if row.endswith("|") and not row.endswith("\\|"):
                row = row[:-1]
            parts = re.split(r"(?<!\\)\|", row)
            return [p.strip().replace("\\|", "|") for p in parts]
        head = cells(lines[i])
        aligns = []
        for c in cells(lines[i + 1]):
            c = c.strip()
            aligns.append("center" if c.startswith(":") and c.endswith(":") else
                          "right" if c.endswith(":") else
                          "left" if c.startswith(":") else "")
        i += 2
        rows = []
        while i < len(lines) and lines[i].strip() and "|" in lines[i]:
            rows.append(cells(lines[i]))
            i += 1

        def tr(cs, tag):
            res = []
            for k in range(len(head)):
                c = cs[k] if k < len(cs) else ""
                al = aligns[k] if k < len(aligns) and aligns[k] else ""
                st = ' style="text-align:%s"' % al if al else ""
                res.append("<%s%s>%s</%s>" % (tag, st, self.inline.render(c), tag))
            return "<tr>" + "".join(res) + "</tr>"
        h = ""
        if any(c.strip() for c in head):
            h = "<thead>" + tr(head, "th") + "</thead>"
        out.append('<div class="tbl"><table>%s<tbody>%s</tbody></table></div>' %
                   (h, "".join(tr(r, "td") for r in rows)))
        return i

    def list(self, lines, i, out):
        first = LIST_RE.match(lines[i])
        ordered = first.group(2)[0].isdigit()
        marker_kind = first.group(2)[-1] if ordered else first.group(2)
        base_indent = len(first.group(1))
        items = []
        loose = False
        n = len(lines)
        while i < n:
            m = LIST_RE.match(lines[i])
            if not m or len(m.group(1)) != base_indent or \
                    (m.group(2)[0].isdigit()) != ordered or \
                    (m.group(2)[-1] if ordered else m.group(2)) != marker_kind:
                break
            content_indent = len(m.group(1)) + len(m.group(2)) + len(m.group(3))
            if not m.group(4):
                content_indent = len(m.group(1)) + len(m.group(2)) + 1
            if len(m.group(3)) > 4:
                content_indent = len(m.group(1)) + len(m.group(2)) + 1
            body = [m.group(4) if len(m.group(3)) <= 4 else
                    " " * (len(m.group(3)) - 1) + m.group(4)]
            i += 1
            while i < n:
                l = lines[i]
                if not l.strip():
                    # a blank line: the item goes on if the next text is indented
                    j = i
                    while j < n and not lines[j].strip():
                        j += 1
                    if j < n and (len(lines[j]) - len(lines[j].lstrip(" "))) >= \
                            content_indent:
                        body.extend([""] * (j - i))
                        i = j
                        continue
                    break
                ind = len(l) - len(l.lstrip(" "))
                if ind >= content_indent:
                    body.append(l[content_indent:])
                    i += 1
                    continue
                lm = LIST_RE.match(l)
                if lm and len(lm.group(1)) <= base_indent:
                    break
                if lm:
                    # a sub-list indented less than the content (2 spaces under "1. ")
                    body.append(l[min(ind, content_indent):])
                    i += 1
                    continue
                if FENCE_RE.match(l) or HEAD_RE.match(l) or HR_RE.match(l):
                    break
                # lazy continuation of the item's paragraph
                body.append(l.strip())
                i += 1
            if "" in body[:-1]:
                k = len(body) - 1
                while k >= 0 and body[k] == "":
                    k -= 1
                if "" in body[:k]:
                    # a blank line between blocks of the item: loose, unless it only
                    # separates a nested list or code
                    loose = loose or self._is_loose(body[:k + 1])
            items.append(body)
            # blank lines between items make the list loose
            j = i - 1
            if i < n and j >= 0 and not lines[j].strip():
                m2 = LIST_RE.match(lines[i]) if i < n else None
                if m2 and len(m2.group(1)) == base_indent:
                    loose = True
        tag = "ol" if ordered else "ul"
        start = ""
        if ordered:
            num = int(re.match(r"\d+", first.group(2)).group(0))
            if num != 1:
                start = ' start="%d"' % num
        lis = []
        for body in items:
            lis.append("<li>%s</li>" % self.blocks(body, tight=not loose))
        out.append("<%s%s>\n%s\n</%s>" % (tag, start, "\n".join(lis), tag))
        return i

    def _is_loose(self, body):
        # loose when a blank line separates two paragraphs of the item
        prev_text = False
        blank = False
        for l in body:
            if not l.strip():
                blank = True
                continue
            starts_block = LIST_RE.match(l) or FENCE_RE.match(l) or l.startswith("    ")
            if blank and prev_text and not starts_block:
                return True
            prev_text = not starts_block
            blank = False
        return False


# ---------------------------------------------------------------- the site

class Site:
    def __init__(self, out, repo_url=None, allow_missing=False):
        self.out = out
        self.repo_url = repo_url
        self.warnings = []
        self.errors = []
        self.images = {}            # repository path -> site path
        self.pages = []             # (section, src, label)
        for title, pages in MANIFEST:
            for src, label in pages:
                if os.path.exists(os.path.join(REPO, src)):
                    self.pages.append((title, src, label))
                elif allow_missing:
                    self.warnings.append("missing page (left out): %s" % src)
                else:
                    self.errors.append("missing page: %s (--allow-missing builds "
                                       "without it)" % src)
        front = self.pages[0][1] if self.pages else None
        self.by_src = {src: page_name(src, front) for _, src, _ in self.pages}

    def resolver(self, src):
        base = os.path.dirname(src)

        def resolve(href, image):
            if re.match(r"^[a-z][a-z0-9+.-]*:", href, re.I) or href.startswith("//"):
                return href
            if href.startswith("#"):
                return href
            path, _, anchor = href.partition("#")
            path = path.split("?")[0]
            target = os.path.normpath(os.path.join(base, path)) if path else src
            target = target.replace(os.sep, "/")
            full = os.path.join(REPO, target)
            if target.startswith("..") or not os.path.exists(full):
                self.warnings.append("%s: link to a missing file: %s" % (src, href))
                return None
            if os.path.isdir(full) and target.rstrip("/") + "/README.md" in self.by_src \
                    and not image:
                target = target.rstrip("/") + "/README.md"
            if target in self.by_src and not image:
                return self.by_src[target] + ("#" + anchor if anchor else "")
            if target.lower().endswith(IMAGE_EXT) and os.path.isfile(full):
                site = "img/" + target
                self.images[target] = site
                return site
            if self.repo_url:
                return self.repo_url.rstrip("/") + "/" + target + \
                    ("#" + anchor if anchor else "")
            return None
        return resolve

    def privacy(self, src, text):
        for k, line in enumerate(text.splitlines(), 1):
            low = line.lower()
            for p in PRIVATE:
                if p in low:
                    self.errors.append("%s:%d: private name %r in a page of the site" %
                                       (src, k, p))

    def nav(self, current):
        out = ['<nav class="side" aria-label="Contents">']
        num = 0
        for title, pages in MANIFEST:
            present = [(s, l) for s, l in pages if s in self.by_src]
            if not present:
                continue
            num += 1
            out.append('<div class="sec"><span class="num">%d</span>%s</div><ol>' %
                       (num, html.escape(title)))
            for s, l in present:
                cur = ' class="cur" aria-current="page"' if s == current else ""
                out.append('<li><a href="%s"%s>%s</a></li>' %
                           (self.by_src[s], cur, html.escape(l)))
            out.append("</ol>")
        out.append("</nav>")
        return "\n".join(out)

    def build(self):
        if self.errors:
            return
        texts = {}
        for _, src, _ in self.pages:
            texts[src] = open(os.path.join(REPO, src), encoding="utf-8").read()
            self.privacy(src, texts[src])
        if self.errors:
            return                  # nothing is written when a page holds a private name
        os.makedirs(self.out, exist_ok=True)
        # a page or image of an earlier build that is not in this one must not stay
        for f in os.listdir(self.out):
            if f.endswith(".html"):
                os.remove(os.path.join(self.out, f))
        shutil.rmtree(os.path.join(self.out, "img"), ignore_errors=True)
        shutil.copyfile(CSS, os.path.join(self.out, "style.css"))
        order = [s for _, s, _ in self.pages]
        labels = {s: l for _, s, l in self.pages}
        for idx, (section, src, label) in enumerate(self.pages):
            text = texts[src]
            lines = [expand_tabs(l) for l in text.replace("\r\n", "\n").split("\n")]
            doc = Doc(Inline(self.resolver(src)))
            body = doc.blocks(lines)
            title = next((t for lv, _, t in doc.headings if lv == 1), label)
            prev = order[idx - 1] if idx > 0 else None
            nxt = order[idx + 1] if idx + 1 < len(order) else None
            foot = ['<footer class="pn">']
            foot.append('<a href="%s">&larr; %s</a>' % (self.by_src[prev],
                                                        html.escape(labels[prev]))
                        if prev else "<span></span>")
            foot.append('<a href="%s">%s &rarr;</a>' % (self.by_src[nxt],
                                                        html.escape(labels[nxt]))
                        if nxt else "<span></span>")
            foot.append("</footer>")
            src_note = '<p class="srcnote">Source: <code>%s</code></p>' % html.escape(src)
            page = PAGE % {
                "title": html.escape(title), "brand": BRAND, "sub": SUBTITLE,
                "section": html.escape(section), "nav": self.nav(src), "body": body,
                "foot": "".join(foot), "srcnote": src_note,
            }
            with open(os.path.join(self.out, self.by_src[src]), "w",
                      encoding="utf-8") as f:
                f.write(page)
        for target, site in sorted(self.images.items()):
            dst = os.path.join(self.out, site)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(os.path.join(REPO, target), dst)


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%(title)s &mdash; %(brand)s manual</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&amp;family=IBM+Plex+Mono:wght@400;500&amp;display=swap">
<link rel="stylesheet" href="style.css"></head>
<body>
<header class="top"><a class="brand" href="index.html">%(brand)s</a><span class="sub">%(sub)s</span><span class="crumb">%(section)s</span></header>
<div class="wrap">
%(nav)s
<main>
%(body)s
%(srcnote)s
%(foot)s
</main></div></body></html>
"""


# ---------------------------------------------------------------- the link check

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        for k in ("id", "name"):
            if a.get(k) and (k == "id" or tag == "a"):
                self.ids.add(a[k])
        for k in ("href", "src"):
            if a.get(k) and not (tag == "link" and k == "href" and "://" in a[k]):
                self.refs.append(a[k])


def check(out):
    pages = {}
    for root, _, files in os.walk(out):
        for f in files:
            if f.endswith(".html"):
                p = Links()
                path = os.path.join(root, f)
                p.feed(open(path, encoding="utf-8").read())
                pages[os.path.relpath(path, out)] = p
    broken = []
    count = 0
    for name, p in sorted(pages.items()):
        for ref in p.refs:
            if re.match(r"^[a-z][a-z0-9+.-]*:", ref, re.I) or ref.startswith("//"):
                continue
            count += 1
            path, _, anchor = html.unescape(ref).partition("#")
            target = os.path.normpath(os.path.join(os.path.dirname(name), path)) \
                if path else name
            if not os.path.exists(os.path.join(out, target)):
                broken.append("%s: %s (no such file)" % (name, ref))
                continue
            if anchor and target in pages and anchor not in pages[target].ids:
                broken.append("%s: %s (no such anchor in %s)" % (name, ref, target))
    return broken, count, len(pages)


def main():
    args = sys.argv[1:]
    out = None
    repo_url = None
    do_check = allow = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "-o" and i + 1 < len(args):
            out = args[i + 1]
            i += 2
            continue
        if a == "--repo-url" and i + 1 < len(args):
            repo_url = args[i + 1]
            i += 2
            continue
        if a == "--check":
            do_check = True
        elif a == "--allow-missing":
            allow = True
        elif a == "--list":
            for title, pages in MANIFEST:
                print(title)
                for s, l in pages:
                    print("  %-42s %s%s" % (s, l, "" if os.path.exists(
                        os.path.join(REPO, s)) else "  (missing)"))
            return 0
        else:
            sys.exit(__doc__)
        i += 1
    if not out:
        sys.exit(__doc__)
    t0 = time.time()
    site = Site(os.path.abspath(out), repo_url, allow)
    site.build()
    for w in site.warnings:
        print("warning: " + w)
    for e in site.errors:
        print("error: " + e)
    if site.errors:
        print("MANUAL: FAILED (%d errors)" % len(site.errors))
        return 1
    print("MANUAL: %d pages, %d images in %s (%.1f s)" %
          (len(site.pages), len(site.images), out, time.time() - t0))
    if do_check:
        broken, count, npages = check(site.out)
        for b in broken:
            print("broken: " + b)
        print("MANUAL LINK CHECK: %d internal links in %d pages, %d broken: %s" %
              (count, npages, len(broken), "FAILED" if broken else "PASSED"))
        if broken:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
