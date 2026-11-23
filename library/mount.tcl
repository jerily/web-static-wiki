# Validate options and prepare the content store and templates.
proc ::web::static::wiki::prepare_mount {args} {
    set config [::web::core::options [dict create -store {} -prefix /wiki -navigation {} -config {} -secret_config {}] {*}$args]
    # Reserved for a consistent host mount contract; never capture unused secrets.
    dict size [dict get $config -secret_config]
    dict unset config -secret_config
    set settings [::web::core::options {master_template {} templates {} template_renderer {} validate_templates true} {*}[dict get $config -config]]
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

# Register this mount's manifest routes on the supplied router.
proc ::web::static::wiki::mount {router args} {
    set config [prepare_mount {*}$args]
    set prefix [dict get $config -prefix]
    set settings [dict get $config -config]
    set manifest [::web::core::manifest web-static-wiki]
    set plan [::web::core::route_plan $manifest $prefix $config $settings]
    ::web::core::install $router $plan
    return $config
}
