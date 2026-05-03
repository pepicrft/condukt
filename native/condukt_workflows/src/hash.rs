use std::fs;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::errors::{WorkflowsError, WorkflowsResult};

pub(crate) fn sha256_tree(root_dir: String) -> WorkflowsResult<String> {
    let root = PathBuf::from(root_dir);
    hash_tree(&root)
}

fn hash_tree(root: &Path) -> WorkflowsResult<String> {
    if !root.is_dir() {
        return Err(WorkflowsError::NotFound(root.display().to_string()));
    }

    let mut files = Vec::new();

    for entry in WalkDir::new(root).sort_by_file_name() {
        let entry = entry?;
        if entry.file_type().is_file() {
            files.push(entry.into_path());
        }
    }

    files.sort_by(|left, right| relative_key(root, left).cmp(&relative_key(root, right)));

    let mut hasher = Sha256::new();

    for path in files {
        let relative = relative_key(root, &path);
        let bytes = fs::read(&path)?;

        hasher.update(relative.as_bytes());
        hasher.update([0]);
        hasher.update(bytes);
        hasher.update([0]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

fn relative_key(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::hash_tree;
    use std::fs;
    use std::path::PathBuf;

    #[test]
    fn tree_hash_is_stable_across_file_creation_order() {
        let left = temp_dir("left");
        let right = temp_dir("right");

        fs::create_dir_all(left.join("a")).unwrap();
        fs::create_dir_all(right.join("a")).unwrap();

        fs::write(left.join("z.txt"), "last").unwrap();
        fs::write(left.join("a").join("first.txt"), "first").unwrap();

        fs::write(right.join("a").join("first.txt"), "first").unwrap();
        fs::write(right.join("z.txt"), "last").unwrap();

        assert_eq!(hash_tree(&left).unwrap(), hash_tree(&right).unwrap());

        fs::remove_dir_all(left).unwrap();
        fs::remove_dir_all(right).unwrap();
    }

    #[test]
    fn tree_hash_changes_when_content_changes() {
        let root = temp_dir("content");
        fs::create_dir_all(&root).unwrap();

        fs::write(root.join("file.txt"), "one").unwrap();
        let before = hash_tree(&root).unwrap();

        fs::write(root.join("file.txt"), "two").unwrap();
        let after = hash_tree(&root).unwrap();

        assert_ne!(before, after);

        fs::remove_dir_all(root).unwrap();
    }

    fn temp_dir(label: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "condukt-workflows-{label}-{}-{:?}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        path
    }
}
