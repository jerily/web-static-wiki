package require tcltest 2
set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]
::tcltest::configure {*}$argv -singleproc true -testdir [file dirname [file normalize [info script]]]
exit [::tcltest::runAllTests]
