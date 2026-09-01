use strict;
use warnings;
use Test::More;
use FindBin;
my $script="$FindBin::Bin/../bin/asgs-lint";
my $ok=do $script;
ok($ok,'single script loads as modulino without running CLI') or diag($@||$!);
ok(bin::asgslint->can('run'),'run() is available');
done_testing;
