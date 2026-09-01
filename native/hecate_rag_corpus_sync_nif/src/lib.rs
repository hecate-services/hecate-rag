//! hecate_rag_corpus_sync_nif
//!
//! Rustler NIF backing the corpus git-sync gen_server. Replaces the
//! bash-script-on-a-systemd-timer design: fetch `origin` for the
//! checkout's current branch and fast-forward it, entirely via
//! vendored libgit2 (statically linked at build time) -- no `git`
//! binary needed on the host or in the container at runtime.
//!
//! Deliberately `--ff-only` in spirit: a real merge is never
//! attempted. A diverged history is reported as `not_fast_forward`
//! and left untouched, the same safety property the bash script's
//! own `git pull --ff-only` had.
//!
//! HTTPS only (mirrors this fleet's actual clone convention -- see
//! `macula-demo/infrastructure/gitops/README.md`'s enrollment step).
//! No SSH transport, no credentials callback: a private repo needing
//! auth is out of scope until something here actually needs one.

use git2::{AnnotatedCommit, FetchOptions, Reference, Repository};

pub enum Status {
    UpToDate,
    FastForwarded { from: String, to: String },
}

pub enum SyncError {
    NotFastForward,
    Git(String),
}

impl From<git2::Error> for SyncError {
    fn from(e: git2::Error) -> Self {
        SyncError::Git(e.message().to_string())
    }
}

pub fn sync_inner(path: &str) -> Result<Status, SyncError> {
    let repo = Repository::open(path)?;
    let branch_name = current_branch_name(&repo)?;

    fetch_origin(&repo, &branch_name)?;

    let fetch_commit = fetch_head_commit(&repo)?;
    let before = repo.head()?.peel_to_commit()?.id().to_string();

    let analysis = repo.merge_analysis(&[&fetch_commit])?;
    if analysis.0.is_up_to_date() {
        return Ok(Status::UpToDate);
    }
    if !analysis.0.is_fast_forward() {
        return Err(SyncError::NotFastForward);
    }

    fast_forward(&repo, &branch_name, &fetch_commit)?;
    let after = fetch_commit.id().to_string();
    Ok(Status::FastForwarded { from: before, to: after })
}

fn current_branch_name(repo: &Repository) -> Result<String, SyncError> {
    let head = repo.head()?;
    head.shorthand()
        .map(|s| s.to_string())
        .ok_or_else(|| SyncError::Git("HEAD is not a valid UTF-8 branch name".to_string()))
}

fn fetch_origin(repo: &Repository, branch_name: &str) -> Result<(), SyncError> {
    let mut remote = repo.find_remote("origin")?;
    let mut opts = FetchOptions::new();
    remote.fetch(&[branch_name], Some(&mut opts), None)?;
    Ok(())
}

fn fetch_head_commit(repo: &Repository) -> Result<AnnotatedCommit<'_>, SyncError> {
    let fetch_head = repo.find_reference("FETCH_HEAD")?;
    Ok(repo.reference_to_annotated_commit(&fetch_head)?)
}

fn fast_forward(
    repo: &Repository,
    branch_name: &str,
    fetch_commit: &AnnotatedCommit,
) -> Result<(), SyncError> {
    let refname = format!("refs/heads/{branch_name}");
    let mut reference: Reference = repo.find_reference(&refname)?;
    reference.set_target(
        fetch_commit.id(),
        &format!("fast-forward: {refname} -> {}", fetch_commit.id()),
    )?;
    repo.set_head(&refname)?;
    repo.checkout_head(Some(git2::build::CheckoutBuilder::default().force()))?;
    Ok(())
}

// The wrapper below pulls in `enif_*` symbols that only exist once this is
// `dlopen`'d into a running BEAM (via `erlang:load_nif/2`) -- `cargo test`
// builds a standalone executable with no BEAM to provide them, so linking
// a test binary that includes it fails outright. Gated out of `cfg(test)`
// entirely: the pure git2 logic above is what the tests below exercise;
// real coverage of the wrapper itself happens on the Erlang side once
// loaded for real.
#[cfg(not(test))]
mod nif {
    use super::{sync_inner, Status, SyncError};
    use rustler::{Encoder, Env, NifResult, Term};

    mod atoms {
        rustler::atoms! {
            ok,
            error,
            up_to_date,
            fast_forwarded,
            not_fast_forward,
            git_error,
        }
    }

    #[rustler::nif(schedule = "DirtyIo")]
    fn sync<'a>(env: Env<'a>, path: String) -> NifResult<Term<'a>> {
        Ok(match sync_inner(&path) {
            Ok(Status::UpToDate) => (atoms::ok(), atoms::up_to_date()).encode(env),
            Ok(Status::FastForwarded { from, to }) => {
                (atoms::ok(), (atoms::fast_forwarded(), from, to)).encode(env)
            }
            Err(SyncError::NotFastForward) => {
                (atoms::error(), atoms::not_fast_forward()).encode(env)
            }
            Err(SyncError::Git(msg)) => (atoms::error(), (atoms::git_error(), msg)).encode(env),
        })
    }

    rustler::init!("hecate_rag_corpus_sync_nif");
}

#[cfg(test)]
mod tests {
    use super::*;
    use git2::{Repository, Signature};
    use std::fs;
    use std::path::{Path, PathBuf};

    struct TempDir(PathBuf);

    // cargo test runs test functions concurrently by default -- a
    // check-then-create loop keyed only on pid can hand two threads the
    // same "unique" path in the gap between the check and the create.
    // A single process-wide atomic counter has no such gap.
    static NEXT_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

    impl TempDir {
        fn new(label: &str) -> Self {
            let n = NEXT_ID.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "hecate_rag_corpus_sync_nif-{label}-{}-{n}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            TempDir(path)
        }
        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn commit_file(repo: &Repository, name: &str, contents: &str, message: &str) -> git2::Oid {
        let workdir = repo.workdir().unwrap().to_path_buf();
        fs::write(workdir.join(name), contents).unwrap();
        let mut index = repo.index().unwrap();
        index.add_path(Path::new(name)).unwrap();
        index.write().unwrap();
        let tree_id = index.write_tree().unwrap();
        let tree = repo.find_tree(tree_id).unwrap();
        let sig = Signature::now("Test", "test@example.com").unwrap();
        let parents: Vec<git2::Commit> = match repo.head() {
            Ok(head) => vec![head.peel_to_commit().unwrap()],
            Err(_) => vec![],
        };
        let parent_refs: Vec<&git2::Commit> = parents.iter().collect();
        repo.commit(Some("HEAD"), &sig, &sig, message, &tree, &parent_refs)
            .unwrap()
    }

    /// Sets up a bare "remote" repo plus a working "origin-side" checkout
    /// that pushes into it (bare repos have no working tree of their own,
    /// so commits have to be made in a separate clone and pushed). Returns
    /// (remote_bare_dir, origin_workdir, local_clone_dir) -- the NIF under
    /// test operates on local_clone_dir, matching what a real corpus
    /// checkout on a beam host is.
    fn setup() -> (TempDir, TempDir, TempDir) {
        let remote_dir = TempDir::new("remote-bare");
        Repository::init_bare(remote_dir.path()).unwrap();

        let origin_dir = TempDir::new("origin-workdir");
        let origin_repo = Repository::init(origin_dir.path()).unwrap();
        commit_file(&origin_repo, "corpus.md", "# v1\n", "initial commit");
        {
            let mut remote = origin_repo
                .remote("origin", remote_dir.path().to_str().unwrap())
                .unwrap();
            remote.push(&["refs/heads/master:refs/heads/master"], None).unwrap();
        }

        let local_dir = TempDir::new("local-clone");
        fs::remove_dir(local_dir.path()).unwrap(); // clone_into needs to create it itself
        Repository::clone(remote_dir.path().to_str().unwrap(), local_dir.path()).unwrap();

        (remote_dir, origin_dir, local_dir)
    }

    fn push_new_commit(origin_dir: &TempDir, contents: &str) {
        let origin_repo = Repository::open(origin_dir.path()).unwrap();
        commit_file(&origin_repo, "corpus.md", contents, "update");
        let mut remote = origin_repo.find_remote("origin").unwrap();
        remote.push(&["refs/heads/master:refs/heads/master"], None).unwrap();
    }

    #[test]
    fn up_to_date_when_nothing_changed() {
        let (_remote, _origin, local) = setup();
        let path = local.path().to_str().unwrap().to_string();
        match sync_inner(&path) {
            Ok(Status::UpToDate) => {}
            Ok(Status::FastForwarded { .. }) => panic!("expected UpToDate, got FastForwarded"),
            Err(_) => panic!("expected UpToDate, got an error"),
        }
    }

    #[test]
    fn fast_forwards_and_updates_the_working_tree() {
        let (_remote, origin, local) = setup();
        push_new_commit(&origin, "# v2\n");

        let path = local.path().to_str().unwrap().to_string();
        match sync_inner(&path) {
            Ok(Status::FastForwarded { from, to }) => assert_ne!(from, to),
            _ => panic!("expected a fast-forward"),
        }

        let content = fs::read_to_string(local.path().join("corpus.md")).unwrap();
        assert_eq!(content, "# v2\n");

        // Idempotent: a second sync with nothing new is up-to-date, not an error.
        match sync_inner(&path) {
            Ok(Status::UpToDate) => {}
            _ => panic!("expected UpToDate on the second sync"),
        }
    }

    #[test]
    fn diverged_history_is_left_untouched() {
        let (_remote, origin, local) = setup();

        // Diverge: a local commit never pushed anywhere...
        let local_repo = Repository::open(local.path()).unwrap();
        commit_file(&local_repo, "corpus.md", "# local-only change\n", "local edit");

        // ...while origin moves forward independently.
        push_new_commit(&origin, "# v2-from-origin\n");

        let path = local.path().to_str().unwrap().to_string();
        match sync_inner(&path) {
            Err(SyncError::NotFastForward) => {}
            _ => panic!("expected NotFastForward on diverged history"),
        }

        // Untouched: the local-only content is still there, not overwritten.
        let content = fs::read_to_string(local.path().join("corpus.md")).unwrap();
        assert_eq!(content, "# local-only change\n");
    }
}
