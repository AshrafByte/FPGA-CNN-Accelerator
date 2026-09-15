// =====================================================================
//  IEEE SSCS Egypt Chapter, 2026 Student Design Competition
//  Report template: classic technical style (serif body, navy accent,
//  blue-themed tables)
//
//  Usage (main.typ):
//    #import "template.typ": *
//    #show: report.with(title: [...], ...)
// =====================================================================

// ---------------------------------------------------------------------
//  Colours & fonts
// ---------------------------------------------------------------------
#let navy      = rgb("#1F3A5F")   // headings, table header, accents
#let blue      = rgb("#2B5A8F")   // secondary accent
#let ink       = rgb("#1A1A1A")   // body text
#let muted     = rgb("#5F6368")   // captions, header, secondary text
#let hairline  = rgb("#BFC5CC")   // neutral rules
#let row-tint  = rgb("#F1F5FA")   // alternate table rows
#let row-rule  = rgb("#D5DFEC")   // table row separators
#let todo-bg   = rgb("#FFF1B8")   // TODO highlight

#let font-body = ("Libertinus Serif", "New Computer Modern", "Cambria")
#let font-mono = ("Cascadia Mono", "Consolas", "DejaVu Sans Mono")

// Draft mode shows writing guides; set `draft: false` for submission.
#let draft-state = state("sscs-draft", true)

// ---------------------------------------------------------------------
//  Value helpers
// ---------------------------------------------------------------------

// Placeholder text that must be replaced before submission.
#let todo(body) = highlight(fill: todo-bg, extent: 1pt, text(style: "italic", body))

// Shows a value, or a TBD placeholder when it is `none`.
#let val(x, unit: none, digits: none) = {
  if x == none { return todo[TBD] }
  let s = if digits != none and type(x) in (int, float) {
    [#calc.round(x, digits: digits)]
  } else [#x]
  if unit != none [#s #unit] else { s }
}

// Percentage of used/available, or TBD.
#let pct(used, avail) = {
  if used == none or avail == none { todo[TBD] } else [#calc.round(100 * used / avail, digits: 1) %]
}

// Compact scientific formatting for small / large numbers.
#let sci(x, digits: 3) = {
  if x == none { return todo[TBD] }
  if x == 0 { return [0] }
  let e = calc.floor(calc.log(calc.abs(x), base: 10))
  let m = x / calc.pow(10.0, e)
  if calc.abs(m) >= 10 { m = m / 10; e += 1 }
  if e >= -2 and e <= 3 { [#calc.round(x, digits: digits)] } else {
    $#calc.round(m, digits: digits) times 10^(#e)$
  }
}

// ---------------------------------------------------------------------
//  Remarks & callouts
// ---------------------------------------------------------------------

// Indented remark with a thin left rule and a bold run-in title.
#let callout(title: none, accent: hairline, fill: none, body) = block(
  width: 100%, fill: fill, stroke: (left: 0.8pt + accent),
  inset: (left: 1em, right: if fill != none { 8pt } else { 0pt }, y: if fill != none { 6pt } else { 1pt }),
  above: 1em, below: 1em, breakable: true,
  if title != none [#text(weight: "bold", fill: if accent == hairline { ink } else { accent }, title) #body] else { body },
)

#let note(body)    = callout(title: [Note.], body)
#let info(body)    = callout(title: [Info.], accent: navy, body)
#let tip(body)     = callout(title: [Tip.], accent: rgb("#2F855A"), body)
#let warning(body) = callout(title: [Warning.], accent: rgb("#B7791F"), body)

// Highlighted result, set between thin rules.
#let key-result(body) = block(
  width: 100%, inset: (y: 6pt), above: 1.1em, below: 1.1em,
  stroke: (top: 0.5pt + navy, bottom: 0.5pt + navy),
  [#text(weight: "bold", fill: navy)[Result.] #body],
)

// Numbered design assumption (A1, A2, …), required by the announcement.
#let assumption-counter = counter("sscs-assumption")
#let assumption(body) = {
  assumption-counter.step()
  block(width: 100%, inset: (left: 1em), above: 0.9em, below: 0.9em,
    [*Assumption #context assumption-counter.display(n => "A" + str(n) + ".")* #body])
}

// Writing guide, visible only in draft mode.
#let guide(body) = context if draft-state.get() {
  block(
    width: 100%, inset: 8pt, radius: 2pt, above: 1em, below: 1em, breakable: false,
    fill: rgb("#FFFBEA"), stroke: (paint: rgb("#C9A227"), thickness: 0.6pt, dash: "dashed"),
    text(size: 9pt, fill: rgb("#6B5300"))[*Writing guide* (hidden when `draft: false`). #body],
  )
}

// ---------------------------------------------------------------------
//  Tables, figures & summary elements
// ---------------------------------------------------------------------

// Plain-text status for compliance / checklist tables.
#let status(s) = {
  let labels = (met: "Met", done: "Done", partial: "Partial", bonus: "Bonus", pending: "Pending", no: "Not implemented")
  let label = labels.at(s, default: s)
  if s in ("met", "done") { text(weight: "bold", fill: navy, label) }
  else if s == "partial" { text(weight: "bold", fill: rgb("#B7791F"), label) }
  else if s == "bonus" { text(weight: "bold", fill: rgb("#2F855A"), label) }
  else if s in ("pending", "no") { text(style: "italic", fill: muted, label) }
  else { label }
}

// Row of headline figures: metric-cards((label: "Fmax", value: [120], unit: "MHz"), ...)
#let metric-cards(..items) = {
  let items = items.pos()
  grid(
    columns: (1fr,) * items.len(), column-gutter: 10pt, inset: (x: 6pt, y: 7pt),
    stroke: (top: 1pt + navy, bottom: 0.4pt + row-rule),
    ..items.map(it => {
      set par(justify: false)
      text(size: 9pt, fill: muted, it.label)
      linebreak()
      text(size: 14pt, weight: "bold", fill: navy, it.value)
      if "unit" in it { h(3pt); text(size: 9pt, fill: muted, it.unit) }
    }),
  )
}

// Box standing in for a figure you still have to draw.
#let placeholder(desc, height: 5.5cm) = block(
  width: 100%, height: height, stroke: 0.5pt + hairline,
  align(center + horizon, text(size: 9.5pt, style: "italic", fill: muted)[Figure to be inserted: #desc]),
)

// Figure wrapper for placeholders (keeps kind = image for the List of Figures).
#let placeholder-figure(desc, caption: none, height: 5.5cm) = figure(
  kind: image, caption: caption, placeholder(desc, height: height),
)

// Switch headings to A, B, C… numbering.
#let appendix(body) = {
  set heading(numbering: "A.1", supplement: [Appendix])
  counter(heading).update(0)
  pagebreak(weak: true)
  body
}

// ---------------------------------------------------------------------
//  Cover page
// ---------------------------------------------------------------------
#let _cover(title, subtitle, competition, team-name, members, supervisor, university, date, logos) = page(
  margin: (x: 2.5cm, y: 2.5cm), header: none, footer: none,
  {
    set par(justify: false)

    if logos.len() > 0 {
      grid(
        columns: (1fr,) * logos.len(),
        align: (x, y) => if x == 0 { left + horizon } else if x == logos.len() - 1 { right + horizon } else { center + horizon },
        ..logos,
      )
      v(0.8cm)
    }
    text(size: 11.5pt, fill: navy, smallcaps(competition))
    v(2pt)
    line(length: 100%, stroke: 1.2pt + navy)

    v(4cm)
    text(size: 12.5pt, fill: muted, smallcaps[Design Report])
    v(0.2cm)
    block(text(size: 25pt, weight: "bold", fill: navy, par(leading: 0.45em, title)))
    if subtitle != none {
      v(0.3cm)
      text(size: 14pt, style: "italic", subtitle)
    }
    v(0.7cm)
    line(length: 3.5cm, stroke: 0.8pt + navy)

    v(1fr)

    let field(label, value) = (text(fill: muted, label), value)
    let people = {
      for m in members {
        block(below: 0.55em, {
          m.name
          if m.at("detail", default: none) != none { text(fill: muted)[, #m.detail] }
          if m.at("email", default: none) != none { linebreak(); text(size: 9.5pt, fill: muted, raw(m.email)) }
        })
      }
    }
    grid(
      columns: (3.2cm, 1fr), row-gutter: 0.75em, column-gutter: 0.5cm,
      ..field([Team], text(weight: "bold", team-name)),
      ..field([Members], people),
      ..if university != none { field([University], university) } else { () },
      ..if supervisor != none { field([Supervisor], supervisor) } else { () },
    )

    v(1.2cm)
    line(length: 100%, stroke: 0.5pt + hairline)
    v(2pt)
    set text(size: 9.5pt, fill: muted)
    let d = if type(date) == datetime { date.display("[month repr:long] [day padding:none], [year]") } else { date }
    grid(
      columns: (1fr, auto),
      [Submitted to the IEEE Solid-State Circuits Society, Egypt Chapter],
      if d != none { d },
    )
  },
)

// ---------------------------------------------------------------------
//  Main show rule
// ---------------------------------------------------------------------
#let report(
  title: [Report Title],
  subtitle: none,
  short-title: none,
  competition: [IEEE SSCS Egypt Chapter, 2026 Student Design Competition],
  team-name: [Team Name],
  members: (),              // ((name: "…", detail: "…", email: "…"), …)
  supervisor: none,
  university: none,
  date: datetime.today(),   // datetime or content
  logos: (),                // (image("…", height: 1.3cm), …)
  abstract: none,
  keywords: (),
  highlights: none,         // optional content under the abstract, e.g. metric-cards(...)
  list-of-figures: true,
  list-of-tables: true,
  section-break: false,     // true → each numbered section starts on a new page
  draft: true,              // false → hides writing guides
  body,
) = {
  set document(
    title: title,
    author: members.map(m => m.name).filter(n => type(n) == str),
  )
  draft-state.update(draft)

  // ---- Base typography ----
  set text(font: font-body, size: 11pt, fill: ink, lang: "en")
  set par(justify: true, leading: 0.62em, spacing: 1.05em)
  show raw: set text(font: font-mono, size: 8.8pt)
  show link: set text(fill: navy)
  show ref: set text(fill: navy)
  set list(indent: 0.8em)
  set enum(indent: 0.8em)
  set math.equation(numbering: "(1)")

  // ---- Headings ----
  set heading(supplement: [Section])
  show heading: set text(fill: navy)
  show heading.where(level: 1): it => {
    if section-break and it.numbering != none { pagebreak(weak: true) }
    block(above: 2em, below: 1em, sticky: true, text(size: 15pt, weight: "bold", {
      if it.numbering != none { counter(heading).display(it.numbering); h(0.8em) }
      it.body
    }))
  }
  show heading.where(level: 2): it => block(above: 1.5em, below: 0.75em, sticky: true,
    text(size: 12pt, weight: "bold", {
      if it.numbering != none { counter(heading).display(it.numbering); h(0.7em) }
      it.body
    }))
  show heading.where(level: 3): it => block(above: 1.2em, below: 0.6em, sticky: true,
    text(size: 11pt, weight: "bold", style: "italic", fill: ink, {
      if it.numbering != none { counter(heading).display(it.numbering); h(0.6em) }
      it.body
    }))

  // ---- Figures & captions ("Fig. 1." below figures, "Table 1." above tables) ----
  show figure: set block(above: 1.5em, below: 1.5em)
  set figure(gap: 0.7em)
  set figure.caption(separator: [. ])
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.caption: it => {
    set text(size: 9.5pt)
    let sup = if it.kind == image { [Fig.] } else { it.supplement }
    [#text(weight: "bold", fill: navy)[#sup #it.counter.display(it.numbering)]#it.separator#it.body]
  }

  // ---- Tables: navy header, light blue banding, thin blue rules ----
  set table(
    stroke: (x, y) => if y > 0 { (bottom: 0.4pt + row-rule) },
    fill: (x, y) => if y == 0 { navy } else if calc.even(y) { row-tint },
    inset: (x: 6pt, y: 5pt),
    align: left + horizon,
  )
  show table: it => block(stroke: (bottom: 1pt + navy), it)
  show table: set text(size: 9.5pt)
  show table: set par(justify: false)
  show table.cell.where(y: 0): set text(weight: "bold", fill: white)

  // ---- Code ----
  show raw.where(block: true): it => block(
    width: 100%, inset: 8pt, fill: rgb("#F7F7F5"),
    stroke: (top: 0.5pt + hairline, bottom: 0.5pt + hairline),
    align(left, it),
  )

  // ---- Cover ----
  _cover(title, subtitle, competition, team-name, members, supervisor, university, date, logos)
  counter(page).update(1)

  // ---- Page layout ----
  set page(
    paper: "a4",
    margin: (x: 2.5cm, top: 2.7cm, bottom: 2.5cm),
    header: {
      set text(size: 9pt, fill: muted)
      set block(spacing: 4pt)
      grid(
        columns: (1fr, auto),
        smallcaps(if short-title != none { short-title } else { title }),
        competition,
      )
      line(length: 100%, stroke: 0.4pt + hairline)
    },
    footer: context align(center, text(size: 9.5pt, fill: muted, counter(page).display())),
  )

  // ---- Front matter ----
  if abstract != none {
    heading(level: 1, numbering: none, outlined: false)[Abstract]
    abstract
    if keywords.len() > 0 {
      par[#text(weight: "bold", style: "italic")[Index Terms]—#keywords.join(", ")]
    }
    if highlights != none { v(1em); highlights }
    pagebreak()
  }

  {
    show outline.entry.where(level: 1): set block(above: 0.9em)
    show outline.entry.where(level: 1): set text(weight: "bold")
    outline(title: [Contents], depth: 2, indent: auto)
  }
  if list-of-figures { v(1em); outline(title: [List of Figures], target: figure.where(kind: image)) }
  if list-of-tables { v(1em); outline(title: [List of Tables], target: figure.where(kind: table)) }
  pagebreak()

  // ---- Body ----
  set heading(numbering: "1.1")
  body
}
