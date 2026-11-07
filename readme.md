# web-static-wiki — User & Technical Requirements

## Rules
- Serve Markdown from a trusted directory using a read-only snapshot per worker.
- Keep content as data; never evaluate it as Tcl or template code.
- Render safe GFM HTML through `cmark_gfm` and escaped metadata through Jinja.

## Commandments
- No database, write API, editing endpoints, browser editor or authentication flags.
- The host owns its router and chooses when to recreate the content snapshot.

## Principles
- `::web::static::wiki` owns directory reading, routing, templates and CSS.
- Content changes become visible when the host recreates and remounts its store, usually on restart.

## Best Practices
- Mount before host catch-all routes and use a separate router per worker.
- Validate content before deployment; duplicate URLs fail the complete snapshot.

## Generic Guidelines
- Tcl 8.6 and 9.x are supported with ABI-matching native dependencies.
- Installation uses CMake with `LANGUAGES NONE`; this package needs no compiler or Node.

## Install and use

```sh
ttrek install web-static-wiki
```

```tcl
package require web-static-wiki 0.1.0
set store [::web::static::wiki::create -directory ./content/wiki -title Wiki]
set router [::tpathexp::router]
::web::static::wiki::mount $router -store $store -prefix /wiki
puts [dict get [$router dispatch {method GET path /wiki}] body]
$router destroy
```

Public commands: `create -directory directory ?-title title?`, `load store /path`,
`children store /folder`, and `mount router -store store ?options...?`.
The store is an immutable Tcl dictionary containing the validated directory snapshot.
A missing directory is an error; an empty directory serves an empty index.

`.md` and `.markdown` files are read recursively; dotfiles are ignored, and symlinks
are rejected. A file is limited to 1 MiB. The first Markdown heading supplies its
title, falling back to the filename stem. Folder names and titles become lowercase
ASCII URL slugs. Empty slugs become `wiki-item`. Duplicate canonical paths fail.
The index lists immediate children with folders first. Empty folders remain navigable.

For source installation and tests:

```sh
cmake -S . -B build -DTCLSH=tclsh9.1
cmake --install build --prefix "$PWD/stage"
ctest --test-dir build --output-on-failure
```

Dependencies: Tcl, tpathexp 1.1.0+, cmark-gfm-tcl 0.1.0+, jinja2-tcl 0.1.0+,
and tjson 1.0.26+. Put their installation libraries on `TCLLIBPATH` for tests.
See [MOUNTING.md](MOUNTING.md) for the HTTP and template contract.

## Security
### Surface
Public content and a single CSS asset; directory paths and template overrides are trusted host configuration.
### Protections
Only GET/HEAD routes are exposed. Paths reject traversal, encoded separators,
malformed UTF-8 and NUL. Source symlinks and duplicate URLs fail validation.
Metadata is escaped, Markdown uses safe HTML mode, and responses include CSP and nosniff.
### Pending
The host owns TLS, request limits and deployment permissions. Source directories
must not be modified by untrusted users while snapshots are being read.
