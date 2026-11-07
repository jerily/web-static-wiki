# Mount contract

`::web::static::wiki::mount router -store store ?-prefix /wiki? ?-navigation links? ?-config settings?`

The host supplies a `tpathexp` router and a store from `create -directory`.
Mount before catch-all routes. A prefix must be an absolute canonical content path;
`/` mounts at the root. Navigation entries are `{label /local-path}` pairs.

Routes are GET/HEAD for the root, content paths and `/_assets/style.css`.
There are no write routes. Unknown content and reserved endpoint names return 404;
unsupported methods return 405. Responses are dictionaries with `statusCode`,
`headers` and `body`, suitable for direct HTTP and Lambda adapters.

`-config` accepts `master_template` (trusted source replacing `page.html.jinja`)
and `templates` (additional trusted named templates). The layout exposes `body`.
Context includes `title`, `brand`, `home`, `assets`, and `navigation` (label/href).
Item templates also receive `parent`, `date`, and safe-rendered `markdown_html`;
index templates receive `entries` (url/title/kind/date). Only `markdown_html` is
marked safe. Content cannot provide template source.
