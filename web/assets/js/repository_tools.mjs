const REPOSITORY = "tuist/condukt"
const REVISION = "main"
const MAX_DIRECTORY_ENTRIES = 200
const MAX_DIRECTORY_BYTES = 512 * 1024
const MAX_FILE_BYTES = 128 * 1024
const FETCH_OPTIONS = {cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer"}

export function createRepositoryTools({fetch: fetchImplementation = globalThis.fetch} = {}) {
  if (typeof fetchImplementation !== "function") {
    throw new TypeError("A fetch implementation is required for repository tools")
  }

  return [
    {
      name: "list_repository_directory",
      description:
        "List files and directories at one path in the public tuist/condukt GitHub repository. Use an empty path for the repository root.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Directory path relative to the repository root, or an empty string for root.",
          },
        },
        required: ["path"],
        additionalProperties: false,
      },
      execute: async ({path}) => {
        const safePath = repositoryPath(path, {allowEmpty: true})
        const suffix = safePath ? `/${encodePath(safePath)}` : ""
        const url = `https://api.github.com/repos/${REPOSITORY}/contents${suffix}?ref=${REVISION}`
        const response = await fetchImplementation(url, {
          ...FETCH_OPTIONS,
          headers: {accept: "application/vnd.github+json"},
        })
        await ensureSuccess(response)

        const entries = JSON.parse(
          await boundedText(response, {
            maxBytes: MAX_DIRECTORY_BYTES,
            label: "Repository directory response",
          }),
        )
        if (!Array.isArray(entries)) {
          throw new Error(`${safePath || "The repository root"} is not a directory`)
        }

        return {
          repository: REPOSITORY,
          revision: REVISION,
          path: safePath,
          truncated: entries.length > MAX_DIRECTORY_ENTRIES,
          entries: entries.slice(0, MAX_DIRECTORY_ENTRIES).map((entry) => ({
            name: entry.name,
            path: entry.path,
            type: entry.type,
            size: entry.size,
          })),
        }
      },
    },
    {
      name: "read_repository_file",
      description:
        "Read one Unicode text file from the public tuist/condukt GitHub repository at the main revision.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Text file path relative to the repository root.",
          },
        },
        required: ["path"],
        additionalProperties: false,
      },
      execute: async ({path}) => {
        const safePath = repositoryPath(path)
        const url = `https://raw.githubusercontent.com/${REPOSITORY}/${REVISION}/${encodePath(safePath)}`
        const response = await fetchImplementation(url, FETCH_OPTIONS)
        await ensureSuccess(response)

        return {
          repository: REPOSITORY,
          revision: REVISION,
          path: safePath,
          content: await boundedText(response, {
            maxBytes: MAX_FILE_BYTES,
            label: "Repository file",
          }),
        }
      },
    },
  ]
}

function repositoryPath(value, {allowEmpty = false} = {}) {
  if (typeof value !== "string") throw new TypeError("Repository path must be a string")

  const path = value.trim()
  if (allowEmpty && path === "") return ""
  if (!path || path.length > 300) throw new Error("Repository path is empty or too long")
  if (path.startsWith("/") || path.includes("\\") || /[\u0000-\u001f\u007f]/.test(path)) {
    throw new Error("Repository path must be relative")
  }

  const segments = path.split("/")
  if (segments.some((segment) => !segment || segment === "." || segment === "..")) {
    throw new Error("Repository path contains an invalid segment")
  }
  return segments.join("/")
}

function encodePath(path) {
  return path.split("/").map(encodeURIComponent).join("/")
}

async function ensureSuccess(response) {
  if (response.ok) return
  throw new Error(`GitHub returned status ${response.status}`)
}

async function boundedText(response, {maxBytes, label}) {
  const declaredLength = Number(response.headers.get("content-length"))
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new Error(`${label} is too large`)
  }

  const reader = response.body?.getReader()
  if (!reader) {
    const content = await response.text()
    if (new TextEncoder().encode(content).byteLength > maxBytes) {
      throw new Error(`${label} is too large`)
    }
    return content
  }

  const chunks = []
  let byteLength = 0
  while (true) {
    const {done, value} = await reader.read()
    if (done) break
    byteLength += value.byteLength
    if (byteLength > maxBytes) {
      await reader.cancel()
      throw new Error(`${label} is too large`)
    }
    chunks.push(value)
  }

  const bytes = new Uint8Array(byteLength)
  let offset = 0
  for (const chunk of chunks) {
    bytes.set(chunk, offset)
    offset += chunk.byteLength
  }

  try {
    return new TextDecoder("utf-8", {fatal: true}).decode(bytes)
  } catch (_error) {
    throw new Error(`${label} is not valid Unicode text`)
  }
}
