if {![package vsatisfies [package provide Tcl] 8.6-10]} {return}
package ifneeded web-static-wiki 0.1.3 [list source [file join $dir library web-static-wiki.tcl]]
