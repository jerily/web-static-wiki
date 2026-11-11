# web-static-wiki — User & Technical Requirements

## Rules
- Serve a trusted local directory, or query synchronized SQL content on demand.
- Keep content as data; never evaluate it as Tcl or template code.
- Render safe GFM HTML through `cmark_gfm` and escaped metadata through Jinja.

## Commandments
- No request editing API, editing endpoints, browser editor or authentication flags.
- The host owns its router, database connections and explicit content imports.

## Principles
- `::web::static::wiki` owns directory reading, routing, templates and CSS.
- Directory stores refresh when recreated; database stores read synced changes on the next request.

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
package require web-static-wiki 0.1.2
set store [::web::static::wiki::create -directory ./content/wiki -title Wiki]
set router [::tpathexp::router]
::web::static::wiki::mount $router -store $store -prefix /wiki
puts [dict get [$router dispatch {method GET path /wiki}] body]
$router destroy
```

Public commands: `create -directory directory ?-title title? ?-exclude_from_navigation paths? ?-images-directory directory? ?-s3 settings?`, `load store /path`,
`children store /folder`, and `mount router -store store ?options...?`.
A directory store contains validated local content. A database store holds a borrowed
connection and queries requested items without preloading content.
A missing directory is an error; an empty directory serves an empty index.

`.md` and `.markdown` files are read recursively; dotfiles are ignored, and symlinks
are rejected. A file is limited to 1 MiB. The first Markdown heading supplies its
title, falling back to the filename stem. Folder names and titles become lowercase
ASCII URL slugs. Empty slugs become `wiki-item`. Duplicate canonical paths fail.
The index lists immediate children with folders first. Empty folders remain navigable.

To keep asset folders out of directory listings:

```tcl
set store [::web::static::wiki::create -directory ./content/wiki \
    -exclude_from_navigation {images drafts/notes.md}]
```

Available since 0.1.2, `-exclude_from_navigation` is a Tcl list of literal,
case-sensitive source paths relative to `-directory`, using `/` separators.
An entry hides that file or directory and its descendants from all directory
listings. Paths are source filenames, not title-derived URLs; glob characters
are literal. Absolute paths, backslashes, empty segments, `.` and `..` are
rejected. An empty list (the default) leaves navigation unchanged.

This only affects navigation. Excluded content is still validated and available
at its direct URL; the option is not access control. Image discovery, uploads,
and Markdown image rendering are unaffected.

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

## Images in private S3 storage

Image hosting is optional. Pass `-s3` and, optionally, `-images-directory` to
`create`. Without `-s3`, the existing Markdown rendering behavior is unchanged.

```tcl
package require awss3 1.0.17
set s3 [::aws::s3::create {region eu-central-1}]
set store [::web::static::wiki::create -directory ./content/wiki \
    -images-directory ./content/images \
    -s3 [dict create client $s3 bucket my-private-images \
        prefix site/images url_expiry_seconds 3600]]
```

The host owns the client and must keep it alive while the store is mounted.
Use the SDK's credential provider chain (for example an IAM role); the store
contains a client handle, not credentials. Each worker needs its own client.

All image sources are relative to `-images-directory`, which defaults to the
content directory. They are **not relative to the Markdown file**. For example:

```markdown
![Architecture](architecture.svg)
![Installation screen](screens/install.png "Installation")
![Reference image][screen]

[screen]: screens/install.png
```

These refer to `content/images/architecture.svg` and
`content/images/screens/install.png` in the example above. Spaces and Unicode
filenames work with angle-bracket destinations or percent encoding. SVG fragments
such as `architecture.svg#overview` are preserved. Ordinary hyperlinks and image
syntax inside code are unchanged; raw HTML remains disabled by the safe renderer.

When S3 image hosting is enabled, every rendered image must name an indexed image.
External URLs, absolute paths, query strings, backslashes, empty/hidden/dot path
segments (including `..` and percent-encoded traversal), encoded separators, and
symlinks are rejected. A missing image aborts the snapshot before uploads begin.
Keep the trusted content and image directories unchanged while creating a store.

PNG, JPEG, GIF, WebP, AVIF, SVG, ICO and BMP files are indexed recursively (dotfiles
are ignored). The limit is 20 MiB per image. All indexed images, including unused
ones, are uploaded during `create` if absent from S3 and `upload_missing` is true
(the default). Keys contain the SHA-256 of
the bytes and a normalized extension, under the configured prefix. Identical files
share an object; changing bytes creates a new object without breaking old snapshots.
Existing objects are left untouched and old objects are not deleted automatically.
Uploads set the matching image MIME type. Listing/upload errors abort creation.

For production, call `create` with `upload_missing true` during the build, then
use `upload_missing false` in the runtime's `-s3` dictionary. Runtime creation
still validates sources and computes the same keys, but makes no S3 LIST or PUT
calls. Bundle the same image files and use the same bucket/prefix in both stages;
missing S3 objects will not be repaired at runtime. A failed build upload must
prevent deployment. Local development can keep the default automatic uploads.

Each rendered response gets freshly signed GET URLs; no expiring URLs are stored
in Markdown or in the snapshot. HTML attributes escape the signed URL correctly.
`url_expiry_seconds` defaults to 3600 and must be 1–604800. Already-open pages may
need reloading after expiry, and temporary credentials may expire sooner. Page
responses retain `Cache-Control: no-store`.

The S3 settings are `client`, `bucket`, `prefix` (default `content/images`) and
`url_expiry_seconds`, plus the boolean `upload_missing` (default true). Uploads
need `s3:ListBucket` for the object prefix and `s3:PutObject` for missing images.
A runtime using `upload_missing false` only needs `s3:GetObject` for signed downloads. No public
bucket ACL is needed. For local tests only, `http_endpoint` may name a loopback
HTTP origin (e.g. `http://127.0.0.1:9000`); it must match the SDK client endpoint.
The package then allows that origin in its image CSP. Production URLs require HTTPS.

Image support requires `aws-sdk-tcl-s3` 1.0.17+ (`awss3`) and `twebserver`'s native `::twebserver::sha256`.

The unit suite uses a fake S3 client. For real SDK requests against a disposable
loopback HTTP fixture (no AWS credentials or account needed), run:

```sh
python3 tests/images_server.py --tclsh tclsh9.1 \
  --library /path/to/aws-sdk-tcl-s3/libaws-sdk-tcl-s3.so
```

## Explicit database initialization and synchronization

The host owns the `tpersist` connection (SQLite locally or PostgreSQL in production).
Schema and content updates are explicit maintenance operations:

```tcl
::web::static::wiki::initdb $connection
set store [::web::static::wiki::create -connection $connection -domain example.com \
    -images-directory ./images -s3 [dict create client $s3 bucket private-images prefix content/images]]
::web::static::wiki::sync $store ./content
```

`create -connection` performs no queries, schema creation, file reads or hashing.
`load $store /path` queries just that item through `tpersist`; folder/post listings
query metadata without article bodies. Existing readers see synced changes on their
next query. The host closes the connection when its worker stops.

`sync` validates source files, prepares rendered Markdown and image keys, uploads
missing images, and replaces the domain's rows in one transaction. Image-upload
failures leave the previous database content intact. Expiring image URLs are signed
when rendering a requested item. `initdb` is idempotent and never called by `sync`,
store creation, mounting or request handling. Directory stores keep their original
local behavior. There are no snapshot files to build, publish or load.
