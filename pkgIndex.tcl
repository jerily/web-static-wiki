# 
# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.
# 

# Register the package and load its dependencies.
if {![package vsatisfies [package provide Tcl] 9.1-10]} {return}
package ifneeded web-static-wiki 1.0.0 [list source [file join $dir library web-static-wiki.tcl]]

# Locate the manifest without loading application services.
package ifneeded web-static-wiki::manifest 1.0.0 [list apply {{dir} {
    package require web-core
    ::web::core::register web-static-wiki $dir
    package provide web-static-wiki::manifest 1.0.0
}} $dir]
