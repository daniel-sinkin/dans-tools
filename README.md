# ds-tools

Dev tools and the like.

## Development Marker Tidy Check

```sh
/Users/danielsinkin/GitHub_private/ds-tools/scripts/ds-dev-marker-tidy.sh
```

The script finds the nearest `.ds_dev`, builds the local clang-tidy plugin, and
runs the `ds-dev-marker-tidy` check against the configured translation
units.

Example `.ds_dev`:

```txt
marker_tidy = true
build_dir = build
marker_tidy_translation_units = src/main.cpp
```

## Repo Template CLI

```sh
ds_git_clone
ds_git_clone --clone <repo-url>
ds_git_clone -c <repo-url>
ds_git_clone --list
ds_git_clone -l
```

`ds_git_clone` applies a selected starter template only to a zero-commit git
repo. From inside an already-cloned empty repo, run it directly. From a parent
folder, pass `--clone` or `-c` with the target repo URL and it will clone
that target repo first.
