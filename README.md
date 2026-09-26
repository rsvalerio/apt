# rsvalerio APT Repository

Personal Debian/Ubuntu package repository, signed and served from GitHub Pages.

## Installation

```bash
# Add the GPG key
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://rsvalerio.github.io/apt/public.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/rsvalerio.gpg

# Add the repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/rsvalerio.gpg] https://rsvalerio.github.io/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/rsvalerio.list

# Refresh package lists
sudo apt update
```

Indexes are published for `amd64` and `arm64`. `Architecture: all` packages
(scripts-only, e.g. `my-gha-runner`, `my-gha-runner-host`) are listed for both,
so they install on the Raspberry Pis too; `amd64` packages only on amd64 hosts.

## How it works

- `pool/` holds the raw `.deb` files, committed here by each project's release
  workflow:
  - `rsvalerio/my-cloud`: the `my-*` packages (`build-deb.yaml`)
  - `rsvalerio/oxydraw`: `oxydraw` (`publish-deb.yml`)
  - `rsvalerio/ops`: `ops`, once it adopts forge's `publish-deb-dist`
- `.github/workflows/publish.yml` indexes the pool with `aptly`, signs the
  `Release` file with GPG, and deploys the resulting `public/` tree to
  GitHub Pages.
- CI uses a **passphrase-less** signing key: `APT_GPG_PRIVATE_KEY` (secret,
  base64 armored private key) and `APT_GPG_KEY_ID` (variable, full fingerprint).

## Retention: old versions leave the pool

Publishers that use forge's `apt-pool-push` (directly or through
`publish-deb-dist`) prune the pool as they publish. They keep the newest N
versions of each **package and architecture** (`keep-versions`, compared with
`dpkg --compare-versions`) and remove the rest in the same commit.
`publish-deb-dist` defaults to N = 3. Other packages, and other architectures of
the same package, are not touched.

| Publisher | Retention |
|-----------|-----------|
| `ops` (via `publish-deb-dist`, once adopted) | newest 3 per arch |
| `my-cloud`, `oxydraw` (plain `git push`) | none; every version stays until pruned by hand |

What this means if you install from this repo:

- When a version leaves `pool/`, the next index publish drops it, and
  `apt install <pkg>=<old-version>` stops working (`E: Version ... was not found`).
- If you pin an exact version (apt preferences, Ansible, a Dockerfile), keep the
  pin within the newest N releases or it breaks on the next publish without
  warning.
- Hosts that already have the old version installed keep it. They just can't
  reinstall or downgrade to it from here.

Pruning bounds the pool, not the git history: a removed `.deb` stays in `.git`
until the history is rewritten. Run `scripts/squash-history.sh` when a clone of
this repo is much larger than `pool/` (compare `du -sh .git` with
`du -sh pool`), for example after a run of large `ops` releases:

```bash
./scripts/squash-history.sh squash --dry-run   # history only; pool stays as is
./scripts/squash-history.sh squash --yes
./scripts/squash-history.sh push --yes         # force-push; re-clone elsewhere
```

`squash-history.sh run` also prunes `pool/` down to the **single newest** version
per package+arch before squashing. That is stricter than the `keep-versions`
window above and removes pinned versions users may still depend on, so use
`squash` alone unless you mean to do that.

## Rotating the signing key

Use this when creating a new key or replacing a broken passphrase setup.

### Script (recommended)

```bash
./scripts/rotate-signing-key.sh help
./scripts/rotate-signing-key.sh rotate   # keygen + export + test sign
./scripts/rotate-signing-key.sh clean    # after secrets are in 1Password
```

| Command | What it does |
|---------|----------------|
| `keygen` | Create passphrase-less key in `.gpg-workdir/` |
| `show-keys` | Print key ID and fingerprint |
| `export-public` | Write `public.key` (commit to git) |
| `export-secret` | Write `build/apt-secret.b64` for 1Password |
| `test-sign` | Confirm signing works without a passphrase |
| `rotate` | Run all of the above |
| `clean` | Delete local key material |

`%no-protection` in `scripts/apt-signing.batch` creates a key with **no passphrase**, which is what CI needs.

After `rotate`, the script writes `build/apt-secret.b64` and `build/apt-gpg-fingerprint.txt`
and prints `path|clip` commands to copy each into 1Password / Terraform.

### 4. Update 1Password

In your **APT / GitHub** vault item (names may differ in your setup):

| Field | Value |
|-------|--------|
| `APT_GPG_PRIVATE_KEY` | Contents of `build/apt-secret.b64` (single line, no newlines) |
| `APT_GPG_KEY_ID` | Full fingerprint (40 hex chars) |
| `APT_GPG_PASSPHRASE` | **Delete** — no longer used |

Then wipe local copies:

```bash
./scripts/rotate-signing-key.sh clean
```

### 5. Update Terraform

In the module that syncs secrets to GitHub (`rsvalerio/apt`, environment `github-pages`):

1. Update `APT_GPG_PRIVATE_KEY` (secret) and `APT_GPG_KEY_ID` (variable, full fingerprint).
2. **Remove** `APT_GPG_PASSPHRASE` from Terraform and 1Password.
3. Apply:

```bash
terraform plan   # confirm only apt gpg secrets change
terraform apply
```

If you set secrets manually instead of Terraform:

**GitHub → rsvalerio/apt → Settings → Environments → github-pages → Environment secrets**

- Secret: `APT_GPG_PRIVATE_KEY`
- Variable: `APT_GPG_KEY_ID` (full fingerprint)
- Delete `APT_GPG_PASSPHRASE`

### 6. Commit and publish

In this repo:

```bash
git add public.key
git commit -m "chore(apt): rotate APT repository signing key"
git push origin main
```

Trigger a publish (any of these):

- Push the commit above (touches `public.key`), or
- **Actions → Publish APT Repository → Run workflow**

### 7. Verify

After the workflow succeeds:

```bash
curl -fsSL https://rsvalerio.github.io/apt/public.key | gpg --show-keys
```

On a machine that had the old key configured, users must refresh the keyring
before `apt update` will trust the new signatures.

## Security note

A passphrase-less signing key in CI is standard for automated APT repos, but
anyone with `APT_GPG_PRIVATE_KEY` can sign packages as you. Restrict GitHub
environment access, rotate if leaked, and keep the private key only in 1Password
and GitHub secrets — never in git.

## Backlog

Work items live in `.backlog/tasks/` and are managed with `ops backlog`
(`ops backlog task list/view/create/edit`, `ops backlog search`), configured by
the `[backlog]` section in `.ops.toml`. The external Backlog.md `backlog` CLI
does not read that config. See [AGENTS.md](AGENTS.md) for the commands.
