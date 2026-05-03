use rustler::{Atom, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        parse_error,
        eval_error,
        no_solution,
        missing_load,
        invalid_url,
        invalid_version,
        io_error,
        not_found,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn eval(_source: String, _filename: String, _globals: Term) -> (Atom, Atom) {
    (atoms::error(), atoms::eval_error())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_only(_source: String, _filename: String) -> (Atom, Atom) {
    (atoms::error(), atoms::parse_error())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn resolve(_root: String, _requirements: Term, _index: Term) -> (Atom, Atom) {
    (atoms::error(), atoms::no_solution())
}

#[rustler::nif(schedule = "DirtyIo")]
fn sha256_tree(_root_dir: String) -> (Atom, Atom) {
    (atoms::error(), atoms::io_error())
}

rustler::init!("Elixir.Condukt.Workflows.NIF");
