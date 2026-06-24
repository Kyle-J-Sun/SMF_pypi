# SuperModelingFactory · Private PyPI Index

PEP 503 simple repository index for [`supermodelingfactory`](https://github.com/Kyle-J-Sun/SuperModelingFactory_protected).

The index itself is public, but the wheels it points to live in **private GitHub Releases** — downloading them requires a GitHub token with read access to `Kyle-J-Sun/SuperModelingFactory_protected`.

## Install

```bash
# Generate a Fine-grained PAT with read access to SuperModelingFactory_protected
export GH_TOKEN=github_pat_xxxxxxxx

pip install supermodelingfactory \
  --extra-index-url "https://${GH_TOKEN}@kyle-j-sun.github.io/SMF_pypi/simple/"

# With ODPSRunner support
pip install "supermodelingfactory[odps]" \
  --extra-index-url "https://${GH_TOKEN}@kyle-j-sun.github.io/SMF_pypi/simple/"
```

Or set it once in `~/.pip/pip.conf`:

```ini
[global]
extra-index-url = https://${GH_TOKEN}@kyle-j-sun.github.io/SMF_pypi/simple/
```

> Note: `pip` doesn't expand `${GH_TOKEN}` in `pip.conf` directly. Use one of:
>
> - Hardcode the token (not recommended)
> - Use `--index-url` on the CLI with env var substitution
> - Use `~/.netrc` (recommended, see below)

### Recommended: `.netrc` auth

```bash
# ~/.netrc (chmod 600)
machine kyle-j-sun.github.io
  login Kyle-J-Sun
  password github_pat_xxxxxxxx

machine github.com
  login Kyle-J-Sun
  password github_pat_xxxxxxxx
```

Then your `pip.conf` stays clean:

```ini
[global]
extra-index-url = https://kyle-j-sun.github.io/SMF_pypi/simple/
```

## How it works

This repo is rebuilt by `SuperModelingFactory_protected` after every release. The generator script reads all releases via the GitHub API and emits a PEP 503 compliant `simple/<package>/index.html` listing every wheel and sdist.

The `<a>` hrefs point to GitHub Release asset URLs, which 302-redirect to S3 with a short-lived signature. `pip` follows the redirect and downloads the wheel — but only if your token has `Contents: read` on the private repo.
