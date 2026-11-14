# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

# Load the static wiki package and its storage dependencies.
package require Tcl 8.6 9
package require cmark_gfm 0.1.0
package require tpathexp 1.1.0
package require jinja2 0.1.0
package require tjson 1.0.26
package require tpersist 0.1.4

namespace eval ::web::static::wiki {
    variable root [file dirname [file dirname [info script]]]
}
source [file join $::web::static::wiki::root library content.tcl]
source [file join $::web::static::wiki::root library images.tcl]
source [file join $::web::static::wiki::root library templates.tcl]
source [file join $::web::static::wiki::root library http.tcl]
source [file join $::web::static::wiki::root library mount.tcl]
source [file join $::web::static::wiki::root library sync.tcl]
package provide web-static-wiki 0.1.7
