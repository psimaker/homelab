# Grimmory (book library)

Two-container books-library: Grimmory web app + MariaDB 11.4 backing store.
Mounts a `bookdrop/` watch folder for new uploads and a `books/` permanent
library. The MariaDB network is `internal: true` — only the grimmory
container talks to it.

- Public domain: **library.psimaker.org**
- Upstream: <https://github.com/grimmory/grimmory>
- Source path on airbase is `/data/library/`; the directory here is named
  `grimmory/` to disambiguate "library" from generic system libraries.
