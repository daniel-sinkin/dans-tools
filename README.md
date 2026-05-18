# dans-tools

Personal development tools.

## Development Marker Tidy Check

```sh
/Users/danielsinkin/GitHub_private/dans-tools/scripts/dans-dev-marker-tidy.sh
```

The script finds the nearest `.dans_dev`, builds the local clang-tidy plugin, and
runs the `dans-dev-marker-tidy` check against the configured translation units.

Example `.dans_dev`:

```txt
marker_tidy = true
build_dir = build
marker_tidy_translation_units = app/main.cpp
```

## Repo Template CLI

```sh
dans_git_clone
dans_git_clone --clone <repo-url>
dans_git_clone -c <repo-url>
dans_git_clone --list
dans_git_clone -l
```

`dans_git_clone` applies a selected starter template only to a zero-commit git
repo. It configures and builds the copied template before creating the initial
commit. From inside an already-cloned empty repo, run it directly. From a parent
folder, pass `--clone` or `-c` with the target repo URL and it will clone that
target repo first.
