# Images are resolved only against this snapshot, never from request-time paths.
proc ::web::static::wiki::image_settings {store} {
    set settings [options {client {} bucket {} prefix content/images url_expiry_seconds 3600 http_endpoint {}} \
        {*}[dict get $store -s3]]
    if {[dict get $settings client] eq {} || [dict get $settings bucket] eq {}} {
        error "-s3 requires client and bucket"
    }
    set endpoint [dict get $settings http_endpoint]
    if {$endpoint ne {} && ![regexp {^http://(127\.0\.0\.1|localhost):[0-9]+$} $endpoint]} {
        error "-s3 http_endpoint must be a loopback HTTP endpoint"
    }
    set expiry [dict get $settings url_expiry_seconds]
    if {![string is integer -strict $expiry] || $expiry < 1 || $expiry > 604800} {
        error "-s3 url_expiry_seconds must be between 1 and 604800"
    }
    set prefix [string trim [dict get $settings prefix] /]
    if {![regexp {^[a-zA-Z0-9_./-]*$} $prefix] || "." in [split $prefix /] || ".." in [split $prefix /]} {
        error "-s3 prefix must be an S3 key prefix without dot segments"
    }
    dict set settings prefix $prefix
    return $settings
}

proc ::web::static::wiki::image_type {filename} {
    set types {.png image/png .jpg image/jpeg .jpeg image/jpeg .gif image/gif \
        .webp image/webp .avif image/avif .svg image/svg+xml .ico image/vnd.microsoft.icon .bmp image/bmp}
    set extension [string tolower [file extension $filename]]
    if {[dict exists $types $extension]} {return [dict get $types $extension]}
    return {}
}

proc ::web::static::wiki::scan_images {directory relative imagesVar} {
    upvar 1 $imagesVar images
    foreach filename [lsort [glob -nocomplain -directory $directory *]] {
        set source [file tail $filename]
        if {$relative ne {}} {set source $relative/$source}
        set type [file type $filename]
        if {$type eq "link"} {fail 400 "symbolic links are not image sources: $source"}
        if {$type eq "directory"} {
            scan_images $filename $source images
        } elseif {$type eq "file" && [image_type $filename] ne {}} {
            if {[file size $filename] > 20971520} {fail 413 "image exceeds 20 MiB: $source"}
            set extension [string tolower [file extension $filename]]
            if {$extension eq ".jpeg"} {set extension .jpg}
            set digest [string tolower [::sha2::sha256 -hex -filename $filename]]
            dict set images $source [dict create filename $filename object $digest$extension \
                content_type [image_type $filename]]
        }
    }
}

# cmark emits escaped HTML attributes. Decode once, then validate the URL path.
# No absolute URLs, queries, empty/dot/hidden segments or encoded separators.
proc ::web::static::wiki::image_source {source} {
    set source [string map {&quot; \" &amp; & &lt; < &gt; >} $source]
    set fragment {}
    set hash [string first # $source]
    if {$hash >= 0} {
        set fragment [string range $source $hash end]
        set source [string range $source 0 [expr {$hash - 1}]]
    }
    if {[regexp -nocase {%2f|%5c} $source]} {fail 400 "encoded image path separators are not accepted"}
    set source [decode $source]
    if {$source eq {} || [regexp {[:\\?\x00-\x1f\x7f]} $source] || [file pathtype $source] ne "relative"} {
        fail 400 "image source must be a relative path within -images-directory"
    }
    foreach segment [split $source /] {
        if {$segment eq {} || [string index $segment 0] eq "."} {
            fail 400 "image source must not contain empty, hidden or dot path segments"
        }
    }
    return [list $source $fragment]
}

proc ::web::static::wiki::prepare_images {store} {
    if {[dict get $store -s3] eq {}} {return $store}
    package require awss3 1.0.17
    package require sha256 1.0
    set settings [image_settings $store]
    dict set store -s3 $settings
    set directory [dict get $store -images-directory]
    if {$directory eq {}} {set directory [dict get $store -directory]}
    if {![file isdirectory $directory] || [file type $directory] eq "link"} {
        fail 400 "-images-directory must be an existing directory without symbolic links"
    }
    # Reject symlinks in ancestors too, before normalization can hide them.
    set current [file join [pwd] $directory]
    while {[file dirname $current] ne $current} {
        if {[file type $current] eq "link"} {fail 400 "symbolic links are not image directories"}
        set current [file dirname $current]
    }
    dict set store -images-directory [file normalize $directory]
    set images {}
    scan_images [dict get $store -images-directory] {} images
    set prefix [dict get $settings prefix]
    dict for {source image} $images {
        set key [dict get $image object]
        if {$prefix ne {}} {set key $prefix/$key}
        dict set images $source key $key
    }
    # Validate every image reference before making any S3 requests. Work on the
    # safe renderer's output so inline/reference images work and code is ignored.
    dict for {path item} [dict get $store items] {
        if {[dict get $item item_type] ne "page"} {continue}
        set html [::cmark_gfm::render_gfm_html [dict get $item markdown]]
        set references {}
        foreach {tag source} [regexp -all -inline {<img src="([^"]*)"} $html] {
            lassign [image_source $source] name fragment
            if {![dict exists $images $name]} {fail 400 "image not found in -images-directory: $name"}
            dict set references $source [list [dict get $images $name key] $fragment]
        }
        dict set store items $path markdown_html $html
        dict set store items $path image_references $references
    }
    set client [dict get $settings client]
    set bucket [dict get $settings bucket]
    set checked {}
    dict for {source image} $images {
        set key [dict get $image key]
        if {[dict exists $checked $key]} {continue}
        # ls propagates permissions/network failures; the SDK's exists command
        # currently returns false for every HEAD error, not just missing objects.
        if {$key ni [$client ls $bucket $key]} {
            $client put $bucket $key [dict get $image filename] [dict get $image content_type]
        }
        dict set checked $key 1
    }
    return $store
}

proc ::web::static::wiki::render_markdown {store item} {
    if {![dict exists $item image_references]} {
        return [::cmark_gfm::render_gfm_html [dict get $item markdown]]
    }
    set settings [dict get $store -s3]
    set urls {}
    set replacements {}
    dict for {source reference} [dict get $item image_references] {
        lassign $reference key fragment
        if {![dict exists $urls $key]} {
            set url [::aws::s3::generate_presigned_url -method GET \
                -expire [dict get $settings url_expiry_seconds] [dict get $settings client] \
                [dict get $settings bucket] $key]
            set validOrigin [string match https://* $url]
            if {[dict get $settings http_endpoint] ne {}} {
                set validOrigin [string match "[dict get $settings http_endpoint]/*" $url]
            }
            if {!$validOrigin || [regexp {[\x00-\x20\x7f]} $url] ||
                ![regexp {[?&]X-Amz-Signature=[0-9a-fA-F]{64}(&|$)} $url]} {
                error "S3 did not return a signed image URL"
            }
            dict set urls $key $url
        }
        set url [string map {& &amp; \" &quot; < &lt; > &gt;} [dict get $urls $key]$fragment]
        lappend replacements "<img src=\"$source\"" "<img src=\"$url\""
    }
    return [string map $replacements [dict get $item markdown_html]]
}
