package require Tcl 8.6 9
package require cmark_gfm 0.1.0
package require tpathexp 1.1.0
package require jinja2 0.1.0
package require tjson 1.0.26

namespace eval ::web::static::wiki {
    variable root [file dirname [file dirname [info script]]]
}
source [file join $::web::static::wiki::root library content.tcl]
source [file join $::web::static::wiki::root library images.tcl]
source [file join $::web::static::wiki::root library templates.tcl]
source [file join $::web::static::wiki::root library http.tcl]
source [file join $::web::static::wiki::root library mount.tcl]
package provide web-static-wiki 0.1.2
