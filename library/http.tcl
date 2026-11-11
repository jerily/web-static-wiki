proc ::web::static::wiki::response {status body {type {text/html; charset=utf-8}}} {
    dict create statusCode $status body $body headers [dict create \
        content-type $type x-content-type-options nosniff cache-control no-store \
        content-security-policy {default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https: data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'}]
}

proc ::web::static::wiki::url {config path} {
    set prefix [dict get $config -prefix]
    if {$path eq "/"} {return [expr {$prefix eq {} ? "/" : $prefix}]}
    return $prefix$path
}

proc ::web::static::wiki::decode {value} {
    set bytes {}
    for {set i 0} {$i < [string length $value]} {incr i} {
        set character [string index $value $i]
        if {$character eq "%"} {
            set hex [string range $value [expr {$i + 1}] [expr {$i + 2}]]
            if {![regexp {^[0-9a-fA-F]{2}$} $hex]} {fail 400 "invalid percent encoding"}
            append bytes [binary format H2 $hex]
            incr i 2
        } else {append bytes [encoding convertto utf-8 $character]}
    }
    if {[catch {encoding convertfrom utf-8 $bytes} result]} {fail 400 "invalid UTF-8 in request"}
    if {[encoding convertto utf-8 $result] ne $bytes || [string first \x00 $result] >= 0} {
        fail 400 "invalid UTF-8 or NUL in request"
    }
    return $result
}

proc ::web::static::wiki::request_path {params} {
    if {![dict exists $params path]} {return /}
    set path [string trimright /[decode [dict get $params path]] /]
    if {$path eq {}} {return /}
    # Do not turn traversal, encoded slashes or punctuation into valid identifiers.
    if {[regexp -nocase {%2f|%5c} [dict get $params path]]} {fail 400 "encoded path separators are not accepted"}
    if {[regexp {(^|/)_} $path]} {fail 404 "content not found"}
    set path [string tolower $path]
    regsub -all { +} $path - path
    return [canonical_path $path]
}

proc ::web::static::wiki::asset {params} {
    variable root
    set name [dict get $params asset]
    set types {style.css text/css}
    if {![dict exists $types $name]} {fail 404 "asset not found"}
    set result [response 200 [read_file [file join $root assets $name] 2097152] \
        "[dict get $types $name]; charset=utf-8"]
    dict set result headers cache-control {public, max-age=3600}
    return $result
}

proc ::web::static::wiki::view {config path} {
    set store [dict get $config -store]
    set item [load $store $path]
    set title [dict get $item title]
    if {[dict get $item item_type] eq "folder"} {
        set entries [children $store $path]
        set rows {}
        foreach entry $entries {
            lappend rows [dict create url [url $config [dict get $entry path]] \
                title [dict get $entry title] kind [dict get $entry item_type] \
                date {}]
        }
        set fields [text_fields [dict create title $title]]
        dict set fields entries [rows_field $rows]
        set html [render_page $config index.html.jinja $fields]
    } else {
        set markdownHtml [render_markdown $store $item]
        # The template renders the saved title; omit the Markdown's leading title.
        regsub {^<h1>.*?</h1>\n} $markdownHtml {} markdownHtml
        set fields [text_fields [dict create title $title \
            parent [url $config [dict get $item parent_path]] \
            markdown_html $markdownHtml \
            date {}]]
        set html [render_page $config item.html.jinja $fields]
    }
    set result [response 200 $html]
    if {[dict exists $store -s3 http_endpoint] && [dict get $store -s3 http_endpoint] ne {}} {
        set policy [dict get $result headers content-security-policy]
        dict set result headers content-security-policy [string map \
            [list "img-src 'self'" "img-src 'self' [dict get $store -s3 http_endpoint]"] $policy]
    }
    return $result
}

proc ::web::static::wiki::dispatch {config action request context params} {
    try {
        switch -- $action {
            asset {return [asset $params]}
            view {return [view $config [request_path $params]]}
        }
    } trap {WEB STATIC_WIKI} {message options} {
        return [response [lindex [dict get $options -errorcode] 2] "$message\n" {text/plain; charset=utf-8}]
    }
}
