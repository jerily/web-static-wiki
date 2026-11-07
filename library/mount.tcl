proc ::web::static::wiki::mount {router args} {
    init_templates
    set config [options [dict create -store {} -prefix /wiki -navigation {} -config {}] {*}$args]
    set settings [options {master_template {} templates {}} {*}[dict get $config -config]]
    dict set config -config $settings
    set available [page_templates $config]
    dict for {name text} $available {
        ::jinja2::validate $text -templates $available -path $name
    }
    set store [dict get $config -store]
    if {$store eq {} || [dict get $store kind] ne "wiki"} {error "-store must be a wiki store"}
    set prefix [string trimright [dict get $config -prefix] /]
    if {$prefix ne {}} {canonical_path $prefix}
    dict set config -prefix $prefix
    foreach link [dict get $config -navigation] {
        if {[llength $link] != 2 || ![regexp {^/[^\r\n]*$} [lindex $link 1]] ||
            [string match {//*} [lindex $link 1]]} {error "navigation entries must be {label /local-path}"}
    }
    set index [expr {$prefix eq {} ? "/" : $prefix}]
    if {[dict get [$router match GET $index] statusCode] != 404} {
        error "mount prefix is already handled; mount content before catch-all routes"
    }
    $router add GET $prefix/_assets/:asset [list ::web::static::wiki::dispatch $config asset] -strict true
    $router add GET $index [list ::web::static::wiki::dispatch $config view] -strict true
    if {$prefix ne {}} {
        $router add GET $prefix/ [list ::web::static::wiki::dispatch $config view] -strict true
    }
    $router add GET $prefix/:path(.*) [list ::web::static::wiki::dispatch $config view] -strict true
    return $config
}
