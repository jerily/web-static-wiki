# Explicit maintenance APIs. Creating a database store and serving requests
# never creates schema, reads source files, or uploads images.
namespace eval ::web::static::wiki {namespace import ::tpersist::db_*}

proc ::web::static::wiki::initdb {connection} {
    set fields {
        domain {type varchar length 253 not_null 1}
        path {type varchar length 1024 not_null 1}
    }
    foreach name {parent_path item_type title source_path published_at markdown markdown_html image_references image_bucket image_prefix} {
        dict set fields $name {type text not_null 1}
    }
    db_create_table $connection [db_define_table web_static_wiki_items $fields -primary_key {domain path}] -if_not_exists 1
    db_create_index $connection web_static_wiki_children web_static_wiki_items {domain parent_path} -if_not_exists 1
    db_create_index $connection web_static_wiki_types web_static_wiki_items {domain item_type} -if_not_exists 1
}

proc ::web::static::wiki::database_store {store} {
    if {[dict get $store -directory] ne {}} {error "use -connection or -directory, not both"}
    set domain [dict get $store -domain]
    if {$domain eq {} || [string length $domain] > 253} {error "-domain must contain 1 to 253 characters"}
    # Validate the borrowed connection and signing options, without running SQL.
    db_dialect [dict get $store -connection]
    if {[dict get $store -s3] ne {}} {
        dict set store -s3 [dict replace [image_settings $store] upload_missing false]
    }
    dict set store kind wiki
    return $store
}

proc ::web::static::wiki::database_predicate {store} {
    db_eq [db_col domain] [db_value [dict get $store -domain] -type text]
}

proc ::web::static::wiki::database_load {store path} {
    set query [db_limit [db_where [db_select web_static_wiki_items] [db_and \
        [database_predicate $store] [db_eq [db_col path] [db_value $path -type text]]]] 1]
    set rows [dict get [db_execute [dict get $store -connection] $query] rows]
    if {![llength $rows]} {fail 404 "content not found"}
    set item [lindex $rows 0]
    if {[dict get $item image_references] ne {}} {
        set s3 [image_settings $store]
        foreach field {bucket prefix} {
            if {[dict get $item image_$field] ne [dict get $s3 $field]} {
                error "Stored image $field differs from runtime configuration"
            }
        }
    }
    return [dict remove $item domain image_bucket image_prefix]
}

# Listings read only navigation fields, not every article's body.
proc ::web::static::wiki::database_listing {store field value} {
    set query [db_select web_static_wiki_items -columns {path parent_path item_type title source_path published_at}]
    set query [db_where $query [db_and [database_predicate $store] \
        [db_eq [db_col $field] [db_value $value -type text]]]]
    dict get [db_execute [dict get $store -connection] $query] rows
}

proc ::web::static::wiki::sync {store directory} {
    if {[dict get $store -connection] eq {}} {error "sync requires a database store"}
    set options [dict remove $store kind -connection -domain]
    dict set options -directory $directory
    if {[dict get $options -s3] ne {}} {dict set options -s3 upload_missing false}
    set source [create {*}$options]
    # Publish images before committing references to them. Failed uploads leave
    # the database untouched; immutable uploaded objects can be reused on retry.
    sync_images $source
    set connection [dict get $store -connection]
    db_transaction $connection {
        db_execute $connection [db_where [db_delete web_static_wiki_items] [database_predicate $store]]
        dict for {path item} [dict get $source items] {
            set row [dict merge {published_at {} markdown_html {} image_references {} image_bucket {} image_prefix {}} $item]
            if {[dict get $item item_type] eq "page" && ![dict exists $item markdown_html]} {
                dict set row markdown_html [::cmark_gfm::render_gfm_html [dict get $item markdown]]
            }
            if {[dict get $source -s3] ne {}} {
                foreach field {bucket prefix} {dict set row image_$field [dict get $source -s3 $field]}
            }
            dict set row domain [dict get $store -domain]
            set values {}
            dict for {key value} $row {dict set values $key [db_value $value -type text]}
            db_execute $connection [db_values [db_insert web_static_wiki_items] $values -expressions]
        }
    }
    return [dict size [dict get $source items]]
}
