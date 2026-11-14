# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

# Register the package and load its dependencies.
if {![package vsatisfies [package provide Tcl] 8.6-10]} {return}
package ifneeded web-static-wiki 0.1.7 [list source [file join $dir library web-static-wiki.tcl]]
