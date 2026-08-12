//! Markdown code-fence rendering for terminal output.

use std::sync::OnceLock;

use syntect::{
    easy::HighlightLines,
    highlighting::ThemeSet,
    parsing::SyntaxSet,
    util::{LinesWithEndings, as_24_bit_terminal_escaped},
};

const RESET: &str = "\x1b[0m";
const ADDED: &str = "\x1b[32m";
const REMOVED: &str = "\x1b[31m";
const CONTEXT: &str = "\x1b[2;37m";
const HEADER: &str = "\x1b[36m";

struct HighlightAssets {
    syntaxes: SyntaxSet,
    themes: ThemeSet,
}

fn assets() -> &'static HighlightAssets {
    static ASSETS: OnceLock<HighlightAssets> = OnceLock::new();
    ASSETS.get_or_init(|| HighlightAssets {
        syntaxes: SyntaxSet::load_defaults_newlines(),
        themes: ThemeSet::load_defaults(),
    })
}

/// Highlight fenced code and unified diff blocks, leaving ordinary markdown as-is.
pub fn highlight_markdown(markdown: &str) -> String {
    let mut rendered = String::new();
    let mut fence_language = None;
    let mut code = String::new();
    for line in markdown.split_inclusive('\n') {
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if fence_language.is_none() && trimmed.starts_with("```") {
            fence_language = Some(
                trimmed
                    .trim_start_matches("```")
                    .trim()
                    .to_ascii_lowercase(),
            );
            rendered.push_str(line);
        } else if let Some(language) = fence_language.take_if(|_| trimmed.starts_with("```")) {
            rendered.push_str(&highlight_block(&code, &language));
            rendered.push_str(line);
            code.clear();
        } else if fence_language.is_some() {
            code.push_str(line);
        } else {
            rendered.push_str(line);
        }
    }
    if let Some(language) = fence_language {
        rendered.push_str(&highlight_block(&code, &language));
    }
    rendered
}

fn highlight_block(code: &str, language: &str) -> String {
    if matches!(language, "diff" | "patch" | "udiff") {
        return highlight_diff(code);
    }
    let assets = assets();
    let syntax = assets
        .syntaxes
        .find_syntax_by_token(language)
        .unwrap_or_else(|| assets.syntaxes.find_syntax_plain_text());
    let theme = &assets.themes.themes["base16-ocean.dark"];
    let mut highlighter = HighlightLines::new(syntax, theme);
    let mut rendered = String::new();
    for line in LinesWithEndings::from(code) {
        if let Ok(ranges) = highlighter.highlight_line(line, &assets.syntaxes) {
            rendered.push_str(&as_24_bit_terminal_escaped(&ranges, false));
        } else {
            rendered.push_str(line);
        }
    }
    rendered
}

fn highlight_diff(diff: &str) -> String {
    diff.lines()
        .map(|line| {
            let colour =
                if line.starts_with("+++") || line.starts_with("---") || line.starts_with("@@") {
                    HEADER
                } else if line.starts_with('+') {
                    ADDED
                } else if line.starts_with('-') {
                    REMOVED
                } else {
                    CONTEXT
                };
            format!("{colour}{line}{RESET}\n")
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn highlights_rust_fences() {
        let rendered = highlight_markdown("```rust\nfn main() {}\n```\n");
        assert!(rendered.contains("\x1b["));
        assert!(rendered.contains("main"));
    }

    #[test]
    fn colors_diff_additions_and_removals() {
        let rendered = highlight_markdown("```diff\n-old\n+new\n```\n");
        assert!(rendered.contains("\x1b[31m-old"));
        assert!(rendered.contains("\x1b[32m+new"));
    }
}
