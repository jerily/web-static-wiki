proc ::web::static::wiki::fail {status message} {
    return -code error -errorcode [list WEB STATIC_WIKI $status] $message
}

proc ::web::static::wiki::options {defaults args} {
    if {[llength $args] % 2} {error "options must be name/value pairs"}
    foreach {key value} $args {
        if {![dict exists $defaults $key]} {error "unknown option: $key"}
        dict set defaults $key $value
    }
    return $defaults
}

# Snapshot the trusted directory once per worker. Recreate the store to publish changes.
proc ::web::static::wiki::create {args} {
    set store [options {-directory {} -title Wiki} {*}$args]
    set directory [dict get $store -directory]
    if {$directory eq {} || ![file isdirectory $directory] || [file type $directory] eq "link"} {
        fail 400 "-directory must be an existing content directory"
    }
    dict set store -directory [file normalize $directory]
    dict set store kind wiki
    set items {}
    index_source items / [dict create parent_path / item_type folder title [dict get $store -title] \
        markdown {} source_path {} published_at {}]
    scan $store [dict get $store -directory] {} / items
    dict set store items $items
    return $store
}

proc ::web::static::wiki::canonical_path {path} {
    if {$path eq "/"} {return /}
    if {![regexp {^(/[a-z0-9]+(-[a-z0-9]+)*)+$} $path] || [string length $path] > 1024} {
        fail 400 "invalid content path"
    }
    return $path
}

proc ::web::static::wiki::load {store path} {
    canonical_path $path
    if {![dict exists $store items $path]} {fail 404 "content not found"}
    return [dict get $store items $path]
}

proc ::web::static::wiki::compare_items {left right} {
    foreach field {item_type title path} {
        set order [string compare [dict get $left $field] [dict get $right $field]]
        if {$order != 0} {return $order}
    }
    return 0
}

proc ::web::static::wiki::children {store path} {
    canonical_path $path
    set rows {}
    dict for {key item} [dict get $store items] {
        if {$key ne $path && [dict get $item parent_path] eq $path} {lappend rows $item}
    }
    return [lsort -command ::web::static::wiki::compare_items $rows]
}

proc ::web::static::wiki::slug {text} {
    set text [string tolower [string trim $text]]
    regsub -all {[^a-z0-9[:space:]-]} $text {} text
    regsub -all {[[:space:]-]+} $text - text
    set text [string trim $text -]
    if {$text eq {}} {set text wiki-item}
    return $text
}

proc ::web::static::wiki::title {markdown filename} {
    foreach line [split $markdown \n] {
        if {[regexp {^#{1,6}[ \t]+(.+)$} $line -> title]} {
            set title [string trim [string trimright [string trim $title] #]]
            if {$title ne {}} {return $title}
        }
    }
    return [file rootname [file tail $filename]]
}

proc ::web::static::wiki::read_file {filename {limit 1048576}} {
    if {[file size $filename] > $limit} {fail 413 "source file exceeds size limit: $filename"}
    set channel [open $filename r]
    try {
        fconfigure $channel -encoding utf-8 -translation auto
        set text [read $channel]
    } finally {close $channel}
    if {[string first \x00 $text] >= 0} {fail 400 "NUL in source file: $filename"}
    return $text
}

proc ::web::static::wiki::index_source {itemsVar path item} {
    upvar 1 $itemsVar items
    canonical_path $path
    if {[dict exists $items $path]} {fail 409 "duplicate content URL: $path"}
    dict set item path $path
    dict set items $path $item
}

proc ::web::static::wiki::scan {store directory relative parent itemsVar} {
    upvar 1 $itemsVar items
    foreach filename [lsort [glob -nocomplain -directory $directory *]] {
        set name [file tail $filename]
        set source [expr {$relative eq {} ? $name : "$relative/$name"}]
        set type [file type $filename]
        if {$type eq "link"} {fail 400 "symbolic links are not content sources: $source"}
        set prefix [string trimright $parent /]
        if {$type eq "directory"} {
            set path $prefix/[slug $name]
            index_source items $path [dict create parent_path $parent item_type folder title $name \
                markdown {} source_path $source]
            scan $store $filename $source $path items
        } elseif {$type eq "file" && [string tolower [file extension $filename]] in {.md .markdown}} {
            set markdown [read_file $filename]
            set title [title $markdown $name]
            set pageSlug [slug $title]
            index_source items $prefix/$pageSlug [dict create parent_path $parent item_type page \
                title $title markdown $markdown source_path $source]
        }
    }
}
