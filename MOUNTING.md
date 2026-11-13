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
