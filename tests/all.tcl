package require tcltest 2
set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]
# Fixtures must never share a caller's source/content directory.
set channel [file tempfile temporary]
close $channel
file delete $temporary
file mkdir $temporary
try {
    ::tcltest::configure {*}$argv -singleproc true -testdir [file dirname [file normalize [info script]]] -tmpdir $temporary
    set failed [::tcltest::runAllTests]
} finally {file delete -force $temporary}
exit $failed
