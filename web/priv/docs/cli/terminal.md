# Terminal coding agent

The Condukt CLI combines the portable agent loop with local workspace tools and an interactive conversation in the terminal.

## Interactive mode

Run `condukt` without a subcommand from the project you want to work on:

```sh
condukt
```

The slash menu exposes the same primary workflows as the command line:

| Command | Purpose |
| --- | --- |
| `/connect` | Connect an OpenRouter account or key |
| `/files` | List files at the workspace root |
| `/read <path>` | Read a workspace file |
| `/help` | Show available commands |
| `/quit` | Exit Condukt |

## Include an image

Copy an image, then press **Ctrl+V** in the prompt. Condukt reads it from the system clipboard, attaches it to the turn, and leaves a marker such as `[image #1]` in the text so you can refer to it:

```text
Why does the footer look wrong here? [image #1]
```

A terminal never hands an application image bytes, so this is a deliberate key rather than your terminal's own paste. Ctrl+V also pastes text when the clipboard holds no image, and your terminal's usual paste keeps working for text.

You can also type `/image <path>`, or **drag an image file onto the terminal**. Dragging makes the terminal type the file's path, and Condukt attaches the file instead of typing it. This needs nothing installed, and it is the way to include an image over a remote connection, where there is no clipboard to read.

PNG, JPEG, WebP, and GIF are supported, up to 8 MB. The format is taken from the file's contents rather than its name, so a mislabelled screenshot still works.

Reading the clipboard needs no setup on macOS. On Linux it uses `wl-paste` on Wayland or `xclip` on X11; if neither is installed, Condukt says so and dragging the file works instead.

The coding agent can ask for two model tools:

- `read` reads text from a path and truncates very large results.
- `bash` runs a shell command in the workspace with a bounded timeout.

Tool activity appears in the transcript so the user can see how an answer was produced.

## Give Condukt useful context

Start Condukt at the project root so file and command tools use the expected workspace. Describe the desired outcome, relevant constraints, and how the result should be validated.

For example:

```text
Find the failing test, explain the root cause, and propose the smallest safe fix.
```

## Continue elsewhere

Use [editor integration](/cli/editor) when another application should present the conversation. Use [automation](/cli/automation) when you need one non-interactive task.

See the [command-line reference](/cli/command-line) for every terminal option.
