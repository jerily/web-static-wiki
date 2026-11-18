# Mount contract

`::web::static::wiki::mount router -store store ?-prefix /wiki? ?-navigation links? ?-config settings?`

The host supplies a `tpathexp` router and a store from `create -directory`.
Pass `-exclude_from_navigation {images}` to `create` to hide source paths from
directory listings. Direct content URLs and image rendering remain available.
Mount before catch-all routes. A prefix must be an absolute canonical content path;
`/` mounts at the root. Navigation entries are `{label /local-path}` pairs.

Routes are GET/HEAD for the root, content paths and `/_assets/style.css`.
Content paths use folder names and filename stems, with `.md` or `.markdown`
removed and the usual lowercase slug normalization. Headings supply display
titles only; changing a heading does not change the URL.
There are no write routes. Unknown content and reserved endpoint names return 404;
unsupported methods return 405. Responses are dictionaries with `statusCode`,
`headers` and `body`, suitable for direct HTTP and Lambda adapters.

`-config` accepts `master_template` (trusted source replacing `page.html.jinja`)
and `templates` (additional trusted named templates). The layout exposes `body`.
Context includes `title`, `brand`, `home`, `assets`, and `navigation` (label/href).
Item templates also receive `parent`, `date`, and safe-rendered `markdown_html`;
index templates receive `entries` (url/title/kind/date). Only `markdown_html` is
marked safe. Content cannot provide template source.

Image storage is configured on `create` with `-images-directory` and `-s3`.
Image sources are relative to that directory, with no `..`, absolute/external URLs
or symlinks. `markdown_html` contains freshly signed image URLs per request; host
layouts must retain its safe rendering. See [readme.md](readme.md#images-in-private-s3-storage).

For build-time uploads, use `upload_missing true` in `-s3` during the build and
`upload_missing false` at runtime. Both stages must use the same image files,
bucket and prefix. Runtime mode validates references and signs fresh URLs without
listing or uploading S3 objects; its role only needs image `s3:GetObject` access.

## Local images

Use the same Markdown image references with a local URL prefix:

```tcl
set store [::web::static::wiki::create -directory content/wiki \
    -images-directory content/images -images-url-prefix /images]
$router add GET /images/:path(.*) [list ::web::static::wiki::serve_image $store] -strict true
```

`![Photo](photo.jpg)` reads `content/images/photo.jpg` and renders
`<img src="/images/photo.jpg" ...>`, including on nested pages. The host mounts
one image handler; wiki and blog can share the same directory and prefix.
The handler returns binary-safe responses for twebserver or Lambda, with image
MIME types and automatic HEAD support through tpathexp. It serves only indexed
images, rejects traversal and symbolic links, and limits images to 20 MiB.
Restart the directory store after adding images. No AWS client is needed.

Choose either `-images-url-prefix` or `-s3`. Both use the same validated image
inventory and URL encoding. Database stores can sync local image references;
the host serves their files separately from a directory store's inventory.

To share the renderer with an editable wiki, blog or forum, create an inventory
without loading Markdown pages:

```tcl
set images [::web::static::wiki::image_store \
    -images-directory content/images -images-url-prefix /images]
set renderer [list ::web::static::wiki::render_content $images]
```

`render_content $images $markdown` uses the same safe Markdown parsing, reference
validation and URL rewriting as static pages. It reports expected image errors
with `{WEB CONTENT status}` so a host can reject invalid submissions before
saving. `serve_image` accepts the same inventory. Host callbacks are trusted;
never substitute an unsafe renderer for user-submitted Markdown.

## Build-time template validation

`::web::static::wiki::prepare_templates settings` returns the same template dictionary used
by the mount, without opening a database, creating keys, connecting middleware,
or registering routes. Supply the mount's `master_template` and `templates`
settings to validate both the package defaults and their composition with the
host layout during packaging/CI.

Validation defaults to `true`. After validating the exact deployed templates,
pass `validate_templates false` in the mount's `-config` to skip repeated
validation in production workers. The template strings are still loaded and
composed normally; rendering and escaping are unchanged. Development hosts can
keep the default validation behavior. This option does not cache compiled templates.

The mount also accepts `-secret_config dictionary`, consistent with `web-user`.
It is reserved and currently unused here. Its dictionary shape is checked, then
its contents are discarded rather than captured in routes or returned settings.
Existing account-store or middleware credential handling is unchanged.
