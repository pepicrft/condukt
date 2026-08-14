const BLOCK_MARKERS = /^(#{1,4})\s+|^```|^>\s?|^\s*[-+*]\s+|^\s*\d+\.\s+/

export function renderMarkdown(source) {
  const root = document.createElement("div")
  root.dataset.part = "markdown"

  const lines = String(source ?? "").replace(/\r\n?/g, "\n").split("\n")
  let index = 0

  while (index < lines.length) {
    const line = lines[index]

    if (!line.trim()) {
      index += 1
      continue
    }

    const fence = line.match(/^```([\w+-]*)\s*$/)
    if (fence) {
      const codeLines = []
      index += 1
      while (index < lines.length && !/^```\s*$/.test(lines[index])) {
        codeLines.push(lines[index])
        index += 1
      }
      if (index < lines.length) index += 1

      const pre = document.createElement("pre")
      const code = document.createElement("code")
      if (fence[1]) code.dataset.language = fence[1]
      code.textContent = codeLines.join("\n")
      pre.append(code)
      root.append(pre)
      continue
    }

    const heading = line.match(/^(#{1,4})\s+(.+)$/)
    if (heading) {
      const element = document.createElement(`h${Math.min(heading[1].length + 2, 6)}`)
      appendInline(element, heading[2])
      root.append(element)
      index += 1
      continue
    }

    if (/^>\s?/.test(line)) {
      const quoteLines = []
      while (index < lines.length && /^>\s?/.test(lines[index])) {
        quoteLines.push(lines[index].replace(/^>\s?/, ""))
        index += 1
      }
      const quote = document.createElement("blockquote")
      appendInline(quote, quoteLines.join(" "))
      root.append(quote)
      continue
    }

    const unordered = line.match(/^\s*[-+*]\s+(.+)$/)
    const ordered = line.match(/^\s*\d+\.\s+(.+)$/)
    if (unordered || ordered) {
      const list = document.createElement(unordered ? "ul" : "ol")
      const itemPattern = unordered ? /^\s*[-+*]\s+(.+)$/ : /^\s*\d+\.\s+(.+)$/

      while (index < lines.length) {
        const item = lines[index].match(itemPattern)
        if (!item) break
        const listItem = document.createElement("li")
        appendInline(listItem, item[1])
        list.append(listItem)
        index += 1
      }
      root.append(list)
      continue
    }

    const paragraphLines = [line.trim()]
    index += 1
    while (index < lines.length && lines[index].trim() && !BLOCK_MARKERS.test(lines[index])) {
      paragraphLines.push(lines[index].trim())
      index += 1
    }

    const paragraph = document.createElement("p")
    appendInline(paragraph, paragraphLines.join(" "))
    root.append(paragraph)
  }

  return root
}

function appendInline(parent, source, depth = 0) {
  if (!source || depth > 8) {
    parent.append(document.createTextNode(source ?? ""))
    return
  }

  const tokens = [
    {kind: "code", pattern: /`([^`\n]+)`/},
    {kind: "link", pattern: /\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/},
    {kind: "strong", pattern: /\*\*([^*\n]+)\*\*|__([^_\n]+)__/},
    {kind: "strike", pattern: /~~([^~\n]+)~~/},
    {kind: "emphasis", pattern: /(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)/},
  ]

  let remaining = source
  while (remaining) {
    const match = tokens
      .map((token) => ({...token, match: token.pattern.exec(remaining)}))
      .filter((token) => token.match)
      .sort((left, right) => left.match.index - right.match.index)[0]

    if (!match) {
      parent.append(document.createTextNode(unescapeMarkdown(remaining)))
      return
    }

    if (match.match.index > 0) {
      parent.append(document.createTextNode(unescapeMarkdown(remaining.slice(0, match.match.index))))
    }

    const whole = match.match[0]
    const value = match.match[1] || match.match[2] || ""

    if (match.kind === "code") {
      const code = document.createElement("code")
      code.textContent = value
      parent.append(code)
    } else if (match.kind === "link") {
      const href = safeHref(match.match[2])
      if (href) {
        const link = document.createElement("a")
        link.href = href
        link.target = "_blank"
        link.rel = "noreferrer noopener"
        appendInline(link, match.match[1], depth + 1)
        parent.append(link)
      } else {
        appendInline(parent, match.match[1], depth + 1)
      }
    } else {
      const element = document.createElement(
        match.kind === "strong" ? "strong" : match.kind === "strike" ? "s" : "em",
      )
      appendInline(element, value, depth + 1)
      parent.append(element)
    }

    remaining = remaining.slice(match.match.index + whole.length)
  }
}

function safeHref(value) {
  try {
    const url = new URL(value, document.baseURI)
    return ["http:", "https:", "mailto:"].includes(url.protocol) ? url.href : undefined
  } catch (_error) {
    return undefined
  }
}

function unescapeMarkdown(value) {
  return value.replace(/\\([\\`*{}\[\]()#+\-.!_>~])/g, "$1")
}
