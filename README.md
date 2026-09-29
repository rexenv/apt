# rexenv — apt repository

The Debian/Ubuntu package repository for [rexenv](https://rexenv.rex.bd/), a native, no-Docker
local development environment. Ubuntu 22.04 or newer, x86_64 (`amd64`) and arm64.

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://rexenv.github.io/apt/rexenv.gpg | sudo tee /etc/apt/keyrings/rexenv.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/rexenv.gpg] https://rexenv.github.io/apt stable main" | sudo tee /etc/apt/sources.list.d/rexenv.list
sudo apt-get update && sudo apt-get install rexenv
```

Or the one command, which does the same: `curl -fsSL https://rexenv.rex.bd/install.sh | bash`.

Updates arrive with `sudo apt upgrade`; rexenv's own in-app update installs the same package.

## The key

Fingerprint (also in [`KEY_FINGERPRINT`](KEY_FINGERPRINT)):

```
139C C1A4 A197 1376 FC6B 586B D2F2 070D 6DFA 60C9
```

## How the repository is built

Nothing binary lives in this git repository. [`publish.yml`](.github/workflows/publish.yml) — run
after each release is published on [rexenv/homebrew-tap](https://github.com/rexenv/homebrew-tap/releases)
— downloads the debs of the newest three published releases, checks each against its `.sha256` and
its own control fields, builds the indexes with `apt-ftparchive`, signs `Release`, has the runner's
own apt verify the result, and deploys it to GitHub Pages. The signing key is a secret of the
`apt-signing` environment, which needs a maintainer's approval for every run.
