use super::*;

#[test]
fn shorten_path_replaces_home_with_tilde() {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
    if home.as_os_str().is_empty() {
        return;
    }
    let path = home.join("work").join("condukt");
    let shortened = shorten_path(&path);
    assert!(shortened.starts_with('~'), "got {shortened}");
    assert!(shortened.ends_with("work/condukt"), "got {shortened}");
}

#[test]
fn shorten_path_keeps_last_two_components_for_long_paths() {
    let path = PathBuf::from("/a/very/long/path/to/the/worktree");
    let shortened = shorten_path(&path);
    assert!(shortened.starts_with('\u{2026}'), "got {shortened}");
    assert!(shortened.ends_with("the/worktree"), "got {shortened}");
}

#[test]
fn truncate_respects_max_length() {
    assert_eq!(truncate("hello world", 5), "hell\u{2026}");
    assert_eq!(truncate("hi", 5), "hi");
}

#[test]
fn truncate_handles_multibyte_and_wide_characters() {
    assert_eq!(truncate("éclair", 4), "écl\u{2026}");
    assert_eq!(truncate("你好世界", 5), "你好\u{2026}");
}

#[test]
fn format_ci_aggregates_counts() {
    let ci = CiStatus {
        passing: 3,
        failing: 1,
        pending: 2,
    };
    let rendered = format_ci(ci).expect("some checks present");
    assert!(rendered.contains("3 passing"));
    assert!(rendered.contains("1 failing"));
    assert!(rendered.contains("2 pending"));
}

#[test]
fn format_ci_returns_none_when_no_checks() {
    let ci = CiStatus {
        passing: 0,
        failing: 0,
        pending: 0,
    };
    assert!(format_ci(ci).is_none());
}

#[test]
fn footer_is_one_line_and_omits_ci_when_no_checks() {
    let footer = Footer::inert(PathBuf::from("."));
    // No pull request or checks should introduce a second status row.
    let lines = footer.lines(120);
    assert_eq!(lines.len(), 1);
    let footer_line = lines[0].to_string();
    assert!(
        !footer_line.contains("CI"),
        "CI placeholder should be hidden when there are no checks; got {footer_line:?}"
    );
}
