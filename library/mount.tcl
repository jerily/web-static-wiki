proc ::web::static::wiki::prepare_mount {args} {
    set config [options [dict create -store {} -prefix /wiki -navigation {} -config {} -secret_config {}] {*}$args]
    # Reserved for a consistent host mount contract; never capture unused secrets.
    dict size [dict get $config -secret_config]
    dict unset config -secret_config
    set settings [options {master_template {} templates {} template_renderer {} validate_templates true} {*}[dict get $config -config]]
    dict set config -config $settings
    if {[dict get $settings template_renderer] eq {}} {prepare_templates $settings}
    set store [dict get $config -store]
    if {$store eq {} || [dict get $store kind] ne "wiki"} {error "-store must be a wiki store"}
    set prefix [string trimright [dict get $config -prefix] /]
    if {$prefix ne {}} {canonical_path $prefix}
    dict set config -prefix $prefix
    foreach link [dict get $config -navigation] {
        if {[llength $link] != 2 || ![regexp {^/[^\r\n]*$} [lindex $link 1]] ||
            [string match {//*} [lindex $link 1]]} {error "navigation entries must be {label /local-path}"}
    }
    return $config
}

proc ::web::static::wiki::mount {router args} {
    set config [prepare_mount {*}$args]
    set prefix [dict get $config -prefix]
    set settings [dict get $config -config]
    set index [expr {$prefix eq {} ? "/" : $prefix}]
    if {[dict get [$router match GET $index] statusCode] != 404} {
        error "mount prefix is already handled; mount content before catch-all routes"
    }
    foreach route [::web::static::wiki::route_specs $prefix $config $settings] {
        lassign $route method path handler
        $router add $method $path $handler -strict true
    }
    return $config
}
