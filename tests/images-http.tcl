lassign $argv library endpoint directory
set root [file dirname [file dirname [file normalize [info script]]]]
set auto_path [linsert $auto_path 0 $root]
load $library Aws_sdk_tcl_s3
package require web-static-wiki 0.1.5
package require http
proc assert {expression} {if {![uplevel 1 [list expr $expression]]} {error "assertion failed: $expression"}}
proc write {filename bytes} {
    file mkdir [file dirname $filename]
    set channel [open $filename wb]
    try {puts -nonewline $channel $bytes} finally {close $channel}
}
set png [binary decode base64 iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII=]
set svg {<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L1 1"/></svg>}
write [file join $directory pages images.md] {# Images

![Pixel](pixel.png)
![Diagram](diagram.svg)
![Unicode](<caf%C3%A9%20%26%20image.svg#view>)
}
write [file join $directory images pixel.png] $png
write [file join $directory images copy.png] $png
write [file join $directory images diagram.svg] $svg
write [file join $directory images {café & image.svg}] $svg
set client [::aws::s3::create [dict create region us-east-1 endpoint $endpoint \
    aws_access_key_id test aws_secret_access_key test]]
set options [list -directory [file join $directory pages] -images-directory [file join $directory images] \
    -s3 [dict create client $client bucket images-bucket prefix test/images url_expiry_seconds 90 http_endpoint $endpoint]]
try {
    set store [::web::static::wiki::create {*}$options]
    ::web::static::wiki::create {*}$options
    # Runtime mode must make no LIST, GET or PUT calls (the server counts them).
    set runtime [::web::static::wiki::create {*}$options -s3 \
        [dict replace [dict get $options -s3] upload_missing false]]
    assert {[dict get $runtime items] eq [dict get $store items]}
    set store $runtime
    set html [::web::static::wiki::render_markdown $store [::web::static::wiki::load $store /images]]
    set index 0
    foreach {tag escaped} [regexp -all -inline {<img src="([^"]+)"} $html] {
        set url [string map {&amp; &} $escaped]
        set expected "$endpoint/images-bucket/test/images/[lindex {pixel.png diagram.svg caf%C3%A9%20&%20image.svg} $index]?"
        if {[string first $expected $url] != 0} {error "Expected URL starting with $expected; got $url"}
        set token [::http::geturl $url -binary 1]
        try {
            assert {[::http::ncode $token] == 200}
            assert {[::http::data $token] eq [lindex [list $png $svg $svg] $index]}
        } finally {::http::cleanup $token}
        incr index
    }
    assert {$index == 3}
    set router [::tpathexp::router]
    try {
        ::web::static::wiki::mount $router -store $store
        set response [$router dispatch {method GET path /wiki/images}]
        assert {[dict get $response statusCode] == 200}
        assert {[dict get $response headers cache-control] eq "no-store"}
        assert {[string first $endpoint [dict get $response headers content-security-policy]] >= 0}
    } finally {$router destroy}
    write [file join $directory images pixel.png] "${png}changed"
    ::web::static::wiki::create {*}$options
    set token [::http::geturl [::aws::s3::generate_presigned_url -expire 90 $client images-bucket test/images/pixel.png] -binary 1]
    try {assert {[::http::data $token] eq "${png}changed"}} finally {::http::cleanup $token}
    set denied [dict replace [dict get $options -s3] prefix denied]
    assert {[catch {::web::static::wiki::create {*}$options -s3 $denied}]}
    puts "Real SDK image rendering passed (wiki)"
} finally {$client destroy}
