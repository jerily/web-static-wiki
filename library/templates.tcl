namespace eval ::web::static::wiki {
    variable templates {}
}

proc ::web::static::wiki::init_templates {} {
    variable root
    variable templates
    if {[dict size $templates]} {return}
    set loaded {}
    foreach filename [glob -directory [file join $root assets] *.html.jinja] {
        dict set loaded [file tail $filename] [read_file $filename]
    }
    dict for {name text} $loaded {
        ::jinja2::validate $text -templates $loaded -path $name
    }
    set templates $loaded
}

# All text is explicitly typed; arrays and booleans are never inferred from strings.
proc ::web::static::wiki::text_fields {dictionary} {
    set fields {}
    dict for {key value} $dictionary {dict set fields $key [list S $value]}
    return $fields
}

proc ::web::static::wiki::rows_field {rows} {
    set values {}
    foreach row $rows {lappend values [list M [text_fields $row]]}
    return [list L $values]
}

# Host configuration is local to a mount; package defaults remain unchanged.
proc ::web::static::wiki::page_templates {config {extraTemplates {}}} {
    variable templates
    init_templates
    set settings [dict get $config -config]
    set available [dict merge $templates [dict get $settings templates] $extraTemplates]
    if {[dict get $settings master_template] ne {}} {
        dict set available page.html.jinja [dict get $settings master_template]
    }
    return $available
}

proc ::web::static::wiki::render_page {config name fields {extraTemplates {}}} {
    variable templates
    init_templates
    set navigation {}
    foreach link [dict get $config -navigation] {
        lassign $link label href
        lappend navigation [dict create label $label href $href]
    }
    set context [text_fields [dict create brand [dict get $config -store -title] \
        home [url $config /] assets [dict get $config -prefix]/_assets]]
    dict set context navigation [rows_field $navigation]
    set context [dict merge $context $fields]
    # Extra templates come from the trusted host, never a request or content row.
    set available [page_templates $config $extraTemplates]
    ::jinja2::render [dict get $available $name] \
        [::tjson::typed_to_json [list M $context]] -templates $available -path $name
}
