use std::collections::HashMap;
use std::str::FromStr;

use pubgrub::{
    DefaultStringReporter, OfflineDependencyProvider, PubGrubError, Ranges, Reporter as _,
    SemanticVersion, resolve as pubgrub_resolve,
};
use rustler::Term;

use crate::errors::{WorkflowsError, WorkflowsResult};

type SemverRange = Ranges<SemanticVersion>;

#[derive(Clone, Debug, rustler::NifMap)]
pub(crate) struct Requirement {
    pub url: String,
    pub version_spec: String,
}

#[derive(Clone, Debug, rustler::NifMap)]
pub(crate) struct PackageVersion {
    pub dependencies: Vec<Requirement>,
}

pub(crate) fn resolve(
    root: String,
    requirements: Term<'_>,
    index: Term<'_>,
) -> WorkflowsResult<Vec<(String, String)>> {
    let requirements: Vec<Requirement> = requirements
        .decode()
        .map_err(|error| WorkflowsError::Eval(format!("invalid requirements: {error:?}")))?;
    let index: HashMap<String, HashMap<String, PackageVersion>> = index
        .decode()
        .map_err(|error| WorkflowsError::Eval(format!("invalid index: {error:?}")))?;

    resolve_index(root, requirements, index)
}

pub(crate) fn resolve_index(
    root: String,
    requirements: Vec<Requirement>,
    index: HashMap<String, HashMap<String, PackageVersion>>,
) -> WorkflowsResult<Vec<(String, String)>> {
    let root_version = SemanticVersion::new(0, 0, 0);
    let mut provider = OfflineDependencyProvider::<String, SemverRange>::new();

    provider.add_dependencies(
        root.clone(),
        root_version.clone(),
        requirements
            .into_iter()
            .map(|requirement| Ok((requirement.url, parse_range(&requirement.version_spec)?)))
            .collect::<WorkflowsResult<Vec<_>>>()?,
    );

    for (package, versions) in index {
        for (version, package_version) in versions {
            let version = parse_version(&version)?;
            let dependencies = package_version
                .dependencies
                .into_iter()
                .map(|requirement| Ok((requirement.url, parse_range(&requirement.version_spec)?)))
                .collect::<WorkflowsResult<Vec<_>>>()?;

            provider.add_dependencies(package.clone(), version, dependencies);
        }
    }

    match pubgrub_resolve(&provider, root.clone(), root_version) {
        Ok(solution) => {
            let mut selected = solution
                .into_iter()
                .filter_map(|(package, version)| {
                    if package == root {
                        None
                    } else {
                        Some((package, version.to_string()))
                    }
                })
                .collect::<Vec<_>>();
            selected.sort_by(|left, right| left.0.cmp(&right.0));
            Ok(selected)
        }
        Err(PubGrubError::NoSolution(tree)) => Err(WorkflowsError::NoSolution(
            DefaultStringReporter::report(&tree),
        )),
        Err(error) => Err(WorkflowsError::NoSolution(format!("{error:?}"))),
    }
}

fn parse_range(spec: &str) -> WorkflowsResult<SemverRange> {
    let spec = spec.trim();

    if spec == "*" {
        return Ok(SemverRange::full());
    }

    if spec.contains(',') {
        return spec
            .split(',')
            .map(parse_range)
            .try_fold(SemverRange::full(), |acc, range| {
                Ok(acc.intersection(&range?))
            });
    }

    let tokens = spec.split_whitespace().collect::<Vec<_>>();
    if tokens.len() > 2 && tokens.len() % 2 == 0 && is_operator(tokens[0]) {
        return tokens
            .chunks(2)
            .map(|chunk| parse_comparator(chunk[0], chunk[1]))
            .try_fold(SemverRange::full(), |acc, range| {
                Ok(acc.intersection(&range?))
            });
    }

    if let Some(version) = spec.strip_prefix('^') {
        let lower = parse_version(version.trim())?;
        return Ok(SemverRange::between(lower.clone(), caret_upper(&lower)));
    }

    if let Some(version) = spec.strip_prefix("~>") {
        let lower = parse_version(version.trim())?;
        return Ok(SemverRange::between(lower.clone(), tilde_upper(&lower)));
    }

    if let Some(version) = spec.strip_prefix('~') {
        let lower = parse_version(version.trim())?;
        return Ok(SemverRange::between(lower.clone(), tilde_upper(&lower)));
    }

    for operator in [">=", "<=", ">", "<"] {
        if let Some(version) = spec.strip_prefix(operator) {
            return parse_comparator(operator, version.trim());
        }
    }

    Ok(SemverRange::singleton(parse_version(spec)?))
}

fn parse_comparator(operator: &str, version: &str) -> WorkflowsResult<SemverRange> {
    let version = parse_version(version)?;

    match operator {
        ">=" => Ok(SemverRange::higher_than(version)),
        ">" => Ok(SemverRange::strictly_higher_than(version)),
        "<=" => Ok(SemverRange::lower_than(version)),
        "<" => Ok(SemverRange::strictly_lower_than(version)),
        _ => Err(WorkflowsError::InvalidVersion(format!(
            "unsupported comparator {operator}"
        ))),
    }
}

fn is_operator(token: &str) -> bool {
    matches!(token, ">=" | "<=" | ">" | "<")
}

fn parse_version(version: &str) -> WorkflowsResult<SemanticVersion> {
    SemanticVersion::from_str(version.trim().trim_start_matches('v'))
        .map_err(|_| WorkflowsError::InvalidVersion(version.to_owned()))
}

fn caret_upper(version: &SemanticVersion) -> SemanticVersion {
    let (major, minor, patch): (u32, u32, u32) = (*version).into();

    if major == 0 && minor == 0 {
        SemanticVersion::new(0, 0, patch + 1)
    } else if major == 0 {
        SemanticVersion::new(0, minor + 1, 0)
    } else {
        SemanticVersion::new(major + 1, 0, 0)
    }
}

fn tilde_upper(version: &SemanticVersion) -> SemanticVersion {
    let (major, minor, _patch): (u32, u32, u32) = (*version).into();
    SemanticVersion::new(major, minor + 1, 0)
}

#[cfg(test)]
mod tests {
    use super::{PackageVersion, Requirement, resolve_index};
    use std::collections::HashMap;

    #[test]
    fn resolves_satisfiable_graph() {
        let solution = resolve_index(
            "__root__".to_owned(),
            vec![Requirement {
                url: "github.com/acme/a".to_owned(),
                version_spec: "^1.0.0".to_owned(),
            }],
            HashMap::from([
                (
                    "github.com/acme/a".to_owned(),
                    HashMap::from([
                        (
                            "1.0.0".to_owned(),
                            PackageVersion {
                                dependencies: vec![Requirement {
                                    url: "github.com/acme/b".to_owned(),
                                    version_spec: "^1.0.0".to_owned(),
                                }],
                            },
                        ),
                        (
                            "1.1.0".to_owned(),
                            PackageVersion {
                                dependencies: vec![Requirement {
                                    url: "github.com/acme/b".to_owned(),
                                    version_spec: "^2.0.0".to_owned(),
                                }],
                            },
                        ),
                    ]),
                ),
                (
                    "github.com/acme/b".to_owned(),
                    HashMap::from([(
                        "2.0.0".to_owned(),
                        PackageVersion {
                            dependencies: vec![],
                        },
                    )]),
                ),
            ]),
        )
        .unwrap();

        assert_eq!(
            solution,
            vec![
                ("github.com/acme/a".to_owned(), "1.1.0".to_owned()),
                ("github.com/acme/b".to_owned(), "2.0.0".to_owned())
            ]
        );
    }

    #[test]
    fn reports_unsatisfiable_graph() {
        let error = resolve_index(
            "__root__".to_owned(),
            vec![
                Requirement {
                    url: "github.com/acme/a".to_owned(),
                    version_spec: "^1.0.0".to_owned(),
                },
                Requirement {
                    url: "github.com/acme/b".to_owned(),
                    version_spec: "^2.0.0".to_owned(),
                },
            ],
            HashMap::from([
                (
                    "github.com/acme/a".to_owned(),
                    HashMap::from([(
                        "1.0.0".to_owned(),
                        PackageVersion {
                            dependencies: vec![Requirement {
                                url: "github.com/acme/b".to_owned(),
                                version_spec: "^1.0.0".to_owned(),
                            }],
                        },
                    )]),
                ),
                (
                    "github.com/acme/b".to_owned(),
                    HashMap::from([
                        (
                            "1.0.0".to_owned(),
                            PackageVersion {
                                dependencies: vec![],
                            },
                        ),
                        (
                            "2.0.0".to_owned(),
                            PackageVersion {
                                dependencies: vec![],
                            },
                        ),
                    ]),
                ),
            ]),
        )
        .unwrap_err();

        assert!(format!("{error}").contains("no solution"));
    }
}
