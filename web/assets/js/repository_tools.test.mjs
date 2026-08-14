import assert from "node:assert/strict"
import test from "node:test"

import {createRepositoryTools} from "./repository_tools.mjs"

test("lists a bounded repository directory through the GitHub contents endpoint", async () => {
  let requested
  let requestOptions
  const fetch = async (url, options) => {
    requested = url
    requestOptions = options
    return Response.json([
      {name: "lib.rs", path: "crates/core/lib.rs", type: "file", size: 42},
      {name: "tests", path: "crates/core/tests", type: "dir", size: 0},
    ])
  }
  const tool = createRepositoryTools({fetch})[0]

  const result = await tool.execute({path: "crates/core"})

  assert.equal(
    requested,
    "https://api.github.com/repos/tuist/condukt/contents/crates/core?ref=main",
  )
  assert.equal(requestOptions.credentials, "omit")
  assert.equal(requestOptions.cache, "no-store")
  assert.equal(requestOptions.referrerPolicy, "no-referrer")
  assert.deepEqual(result.entries.map(({path}) => path), ["crates/core/lib.rs", "crates/core/tests"])
})

test("reads a repository text file through the fixed raw-content origin", async () => {
  let requested
  const fetch = async (url) => {
    requested = url
    return new Response("# Condukt\n")
  }
  const tool = createRepositoryTools({fetch})[1]

  const result = await tool.execute({path: "docs/hello world.md"})

  assert.equal(
    requested,
    "https://raw.githubusercontent.com/tuist/condukt/main/docs/hello%20world.md",
  )
  assert.equal(result.content, "# Condukt\n")
})

test("rejects traversal before making a request", async () => {
  let requests = 0
  const fetch = async () => {
    requests += 1
    return new Response("unexpected")
  }
  const tool = createRepositoryTools({fetch})[1]

  await assert.rejects(() => tool.execute({path: "../private"}), /invalid segment/)
  assert.equal(requests, 0)
})

test("stops reading repository files above the response limit", async () => {
  const oversized = new Uint8Array(128 * 1024 + 1)
  const tool = createRepositoryTools({fetch: async () => new Response(oversized)})[1]

  await assert.rejects(() => tool.execute({path: "large.txt"}), /Repository file is too large/)
})
