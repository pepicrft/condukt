use super::*;

#[test]
fn pkce_pair_has_correct_shape() {
    let pair = generate_pkce().expect("secure randomness is available");
    assert_eq!(pair.verifier.len(), 64);
    assert!(pair.challenge.len() >= 43);
    assert!(
        pair.verifier
            .chars()
            .all(|c| UNRESERVED.contains(&(c as u8)))
    );
}

#[test]
fn pkce_pair_changes_between_calls() {
    // Two consecutive pairs should not collide even on a fast machine.
    let first = generate_pkce().expect("secure randomness is available");
    let second = generate_pkce().expect("secure randomness is available");
    assert_ne!(first.verifier, second.verifier);
    assert_ne!(first.challenge, second.challenge);
}

#[test]
fn query_param_extracts_value() {
    assert_eq!(
        query_param("code=abc&state=xyz", "code").as_deref(),
        Some("abc")
    );
    assert_eq!(
        query_param("code=abc&state=xyz", "state").as_deref(),
        Some("xyz")
    );
    assert_eq!(query_param("code=abc&state=xyz", "missing"), None);
}

#[test]
fn query_param_url_decodes_value() {
    assert_eq!(
        query_param("code=hello%20world", "code").as_deref(),
        Some("hello world")
    );
    assert_eq!(
        query_param("code=foo+bar", "code").as_deref(),
        Some("foo bar")
    );
}

#[test]
fn loopback_server_serves_the_captured_code() {
    // Bind a server, then "call back" with a raw HTTP request that
    // simulates the browser redirect. The receiver should yield the
    // authorization code.
    let server = bind_loopback("/oauth/callback", Duration::from_secs(2)).expect("bind loopback");
    let port = server.port();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(50));
        let mut stream = std::net::TcpStream::connect(("127.0.0.1", port)).expect("connect");
        stream
                .write_all(
                    b"GET /oauth/callback?code=the-code&state=ignored HTTP/1.1\r\nHost: localhost\r\n\r\n",
                )
                .expect("write");
    });
    let result = server
        .wait(&AtomicBool::new(false))
        .expect("code arrives in time");
    match result {
        CallbackResult::Code(code) => assert_eq!(code, "the-code"),
    }
}

#[test]
fn loopback_server_can_be_cancelled_without_waiting_for_timeout() {
    let server = bind_loopback("/oauth/callback", Duration::from_secs(5)).expect("bind loopback");
    let cancelled = AtomicBool::new(true);
    let started_at = Instant::now();
    let error = server
        .wait(&cancelled)
        .expect_err("wait should be cancelled");
    assert!(error.to_string().contains("cancelled"));
    assert!(started_at.elapsed() < Duration::from_secs(1));
}

#[test]
fn loopback_server_forwards_provider_errors_immediately() {
    let server = bind_loopback("/oauth/callback", Duration::from_secs(2)).expect("bind loopback");
    let port = server.port();
    std::thread::spawn(move || {
        let mut stream = std::net::TcpStream::connect(("127.0.0.1", port)).expect("connect");
        stream
            .write_all(
                b"GET /oauth/callback?error=access_denied&error_description=Nope HTTP/1.1\r\nHost: localhost\r\n\r\n",
            )
            .expect("write");
    });
    let started_at = Instant::now();
    let error = server
        .wait(&AtomicBool::new(false))
        .expect_err("provider error should be forwarded");
    assert!(error.to_string().contains("access_denied"));
    assert!(started_at.elapsed() < Duration::from_secs(1));
}

#[test]
fn callback_page_success_loads_noora_and_inter() {
    let html = callback_page(CallbackPage::Success);
    assert!(html.contains("Signed in"));
    assert!(
        html.contains("noora.css"),
        "success page should link Noora's CSS"
    );
    assert!(
        html.contains("rsms.me/inter"),
        "success page should load Inter font"
    );
    assert!(html.contains("data-badge=\"success\""));
    // The success page should auto-close the tab; the error page should not.
    assert!(html.contains("window.close()"));
}

#[test]
fn callback_page_error_omits_auto_close() {
    let html = callback_page(CallbackPage::Error);
    assert!(html.contains("Sign-in failed"));
    assert!(html.contains("data-badge=\"error\""));
    assert!(
        !html.contains("window.close()"),
        "error page should not auto-close"
    );
}

#[test]
fn callback_page_uses_noora_design_tokens() {
    // The page should style itself with Noora's design tokens so it
    // matches the rest of the Tuist product surface.
    let html = callback_page(CallbackPage::Success);
    for token in [
        "--noora-surface-background-primary",
        "--noora-surface-background-secondary",
        "--noora-surface-label-primary",
        "--noora-surface-label-secondary",
        "--noora-font-body",
        "--noora-radius-8",
        "--noora-spacing-9",
    ] {
        assert!(
            html.contains(token),
            "callback page should reference {token}"
        );
    }
}

#[test]
fn send_response_uses_byte_length_not_char_length() {
    // Regression: the body now contains multi-byte UTF-8 (em dash,
    // quotes, box-drawing characters). The Content-Length header
    // must report the byte count or the browser will truncate the
    // page mid-tag.
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = listener.local_addr().unwrap().port();
    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        send_response(&mut stream, 200, "hello \u{2014} world").expect("send");
    });
    let mut stream = std::net::TcpStream::connect(("127.0.0.1", port)).expect("connect");
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).expect("read");
    handle.join().expect("join");
    let header = String::from_utf8_lossy(&buf);
    // "hello \u{2014} world" is 13 chars but 15 bytes (em dash is
    // 3 bytes in UTF-8). The header must report 15, not 13.
    assert!(
        header.contains("Content-Length: 15"),
        "Content-Length should be byte count, got: {header}"
    );
}
