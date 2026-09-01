use strict;
use warnings;
use Test::More;
use File::Temp qw/tempdir tempfile/;
use File::Spec;
use FindBin;

my $script=File::Spec->catfile($FindBin::Bin,q{..},q{bin},q{asgs-lint});
require $script;

sub write_file {
    my ($path,$text)=@_;
    open my $fh,'>',$path or die $!;
    print {$fh} $text;
    close $fh;
}
sub base_config {
    my (%x)=@_;
    my $extra=$x{extra}//q{};
    my $scenario=$x{scenario}//q{gfsforecast};
    my $bg=$x{bg}//q{GFS};
    my $tc=$x{tc}//q{off};
    return qq{INSTANCENAME=test\nASGSADMIN=test\@example.com\nPPN=40\nNCPU=16\nNUMWRITERS=1\nNCPUCAPACITY=40\nQUEUENAME=general\nSERQUEUE=general\nGRIDNAME=mesh\nBACKGROUNDMET=$bg\nTROPICALCYCLONE=$tc\nWAVES=off\nINTENDEDAUDIENCE=general\nPOSTPROCESS=\(\)\nCOLDSTARTDATE=2026010100\nHINDCASTLENGTH=30\nHOTORCOLD=coldstart\nLASTSUBDIR=null\nPREPPEDARCHIVE=prepped.tgz\nHINDCASTARCHIVE=hindcast.tgz\ncreateWind10mLayer=yes\n$extra\ncase \$si in\n-2)\n ENSTORM=hindcast\n ;;\n-1)\n ENSTORM=nowcast\n ;;\n0)\n ENSTORM=$scenario\n ;;\n*)\n echo error\n ;;\nesac\n};
}

sub run_lint {
    my ($config,%env)=@_;
    local %ENV=(%ENV,%env,ASGS_CONFIG=>$config);
    my $out=q{};
    my $rc;
    { local *STDOUT; open STDOUT,'>',\$out or die $!; $rc=bin::asgslint::run([]); }
    return ($rc,$out);
}

my $dir=tempdir(CLEANUP=>1);
my $bindir="$dir/adcirc-bin"; mkdir $bindir or die $!; write_file("$bindir/adcirc",q{#!/bin/sh\n}); chmod 0755,"$bindir/adcirc";
my $cfg="$dir/config.sh";
write_file($cfg,base_config());
my ($rc,$out)=run_lint($cfg, ASGS_PLATFORMS=>q{}, PLATFORM_INIT=>q{}, ACCOUNT=>'null', ADCIRCDIR=>$bindir, ADCIRC_BINS=>'adcirc');
is($rc,0,'valid baseline passes');
like($out,qr/Summary: 0 error\(s\)/,'baseline reports no errors');

write_file($cfg,base_config(extra=>"SERQUEUE_NTASKS=40\n"));
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'SERQUEUE_NTASKS equal to PPN passes');

write_file($cfg,base_config(extra=>"SERQUEUE_NTASKS=41\n"));
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'SERQUEUE_NTASKS above PPN fails');
like($out,qr/exceeds effective PPN=40/,'range error explained');

write_file($cfg,base_config(extra=>"SCENARIOPACKAGESIZE=auto\n"));
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'SCENARIOPACKAGESIZE rejected with Wind10m automatic layer');
like($out,qr/SCENARIOPACKAGESIZE must not be actively set/,'Wind10m package size message');

write_file($cfg,base_config(scenario=>'gfsforecastWind10m'));
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'explicit Wind10m scenario rejected in automatic mode');
like($out,qr/obsolete explicit Wind10m/,'Wind10m scenario message');

write_file($cfg,base_config(bg=>'NAM',scenario=>'gfsforecast'));
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'forcing/scenario mismatch fails');
like($out,qr/inconsistent with BACKGROUNDMET=NAM/,'forcing mismatch identified');

# h2o objects are restricted hashes: duplicate_lines must be declared when a case is created.
my $dup=base_config();
$dup =~ s/0\)\n ENSTORM=gfsforecast\n ;;/0)\n ENSTORM=gfsforecast\n ;;\n0)\n ENSTORM=gfsforecast\n ;;/;
write_file($cfg,$dup);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'duplicate scenario case fails without restricted-hash exception');
like($out,qr/Scenario case '0' is defined more than once/,'duplicate scenario case is reported');

write_file($cfg,base_config(extra=>"SERQUEUE_NTASKS=99\n",bg=>'NAM',scenario=>'gfsforecast'));
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
my @errors=$out=~/^\[ERROR\]/mg;
cmp_ok(scalar @errors,'>=',2,'multiple errors accumulate');

my $marker="$dir/SHOULD_NOT_EXIST";
my $plat="$dir/init.sh";
write_file($plat,qq{export HPCENV=cephas\nexport HPCENVSHORT=cephas\nexport QUEUESYS=SLURM\nexport QUEUENAME=general\nexport SERQUEUE=general\nexport SERQUEUE_NTASKS=1\nexport PPN=40\nexport JOBLAUNCHER='srun --mpi=pmi2 -n %totalcpu%'\nexport EVIL=\$(touch $marker)\n});
write_file($cfg,base_config());
($rc,$out)=run_lint($cfg,PLATFORM_INIT=>$plat,ASGS_MACHINE_NAME=>'cephas',PPN=>40,QUEUESYS=>'SLURM',QUEUENAME=>'general',SERQUEUE=>'general',SERQUEUE_NTASKS=>1,ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
ok(!-e $marker,'PLATFORM_INIT command substitution is never executed');

write_file($cfg,base_config(extra=>"PPN=32\nSERQUEUE_NTASKS=33\n"));
($rc,$out)=run_lint($cfg,PLATFORM_INIT=>$plat,ASGS_MACHINE_NAME=>'cephas',PPN=>40,QUEUESYS=>'SLURM',QUEUENAME=>'general',SERQUEUE=>'general',SERQUEUE_NTASKS=>1,ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
like($out,qr/ASGS_CONFIG overrides PPN='40' with '32'/,'platform/config override reported');
like($out,qr/SERQUEUE_NTASKS=33 exceeds effective PPN=32/,'effective config values drive validation');


# COLDSTARTDATE may use the documented ASGS helper without executing it.
my $helper=base_config();
$helper =~ s/COLDSTARTDATE=2026010100/COLDSTARTDATE=\$(get-coldstart-date)/;
write_file($cfg,$helper);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'COLDSTARTDATE=$(get-coldstart-date) is accepted statically');
unlike($out,qr/COLDSTARTDATE.*not defined/,'recognized helper is not treated as unresolved command substitution');

my $auto_cold=base_config();
$auto_cold =~ s/COLDSTARTDATE=2026010100/COLDSTARTDATE=auto/;
write_file($cfg,$auto_cold);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'COLDSTARTDATE=auto is rejected for a true coldstart');
like($out,qr/COLDSTARTDATE=auto is not valid for HOTORCOLD=coldstart/,'coldstart auto rule explained');

# A non-null LASTSUBDIR with coldstart is contradictory and catches the operational mistake in #1570.
my $cold_with_last=base_config();
$cold_with_last =~ s{LASTSUBDIR=null}{LASTSUBDIR=https://example.invalid/hotstart};
write_file($cfg,$cold_with_last);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'coldstart with active LASTSUBDIR is rejected');
like($out,qr/LASTSUBDIR=.*is set while HOTORCOLD=coldstart/,'coldstart/LASTSUBDIR inconsistency explained');

# Current ASGS accepts remote hotstarts over http, https, scp, and ssh. The linter never contacts them.
my $remote_hot=base_config();
$remote_hot =~ s/HOTORCOLD=coldstart/HOTORCOLD=hotstart/;
$remote_hot =~ s/COLDSTARTDATE=2026010100/COLDSTARTDATE=auto/;
$remote_hot =~ s{LASTSUBDIR=null}{LASTSUBDIR=https://example.invalid/path/to/gfsforecast};
write_file($cfg,$remote_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'https LASTSUBDIR with hotstart and COLDSTARTDATE=auto passes static checks');

my $scp_hot=$remote_hot;
$scp_hot =~ s{https://example\.invalid/path/to/gfsforecast}{scp://tacc_tds3//full/path/to/gfsforecast};
write_file($cfg,$scp_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'scp LASTSUBDIR syntax used by ASGS passes static checks');

my $bad_scheme=$remote_hot;
$bad_scheme =~ s{https://example\.invalid/path/to/gfsforecast}{ftp://example.invalid/path/to/gfsforecast};
write_file($cfg,$bad_scheme);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'unsupported LASTSUBDIR URL scheme fails');
like($out,qr/unsupported URL scheme/,'unsupported hotstart scheme identified');

# Local LASTSUBDIR follows current asgs_main.sh: hindcast, nowcast, then remote; run.properties + fort.67.
my $lsroot="$dir/previous-cycle";
mkdir $lsroot or die $!;
mkdir "$lsroot/nowcast" or die $!;
write_file("$lsroot/nowcast/run.properties","ColdStartTime : 2026010100\n");
open my $ncfh,'>:raw',"$lsroot/nowcast/fort.67.nc" or die $!;
print {$ncfh} "\x89HDF\x0d\x0a\x1a\x0a", "STATIC-TEST";
close $ncfh;
my $local_hot=base_config();
$local_hot =~ s/HOTORCOLD=coldstart/HOTORCOLD=hotstart/;
$local_hot =~ s/COLDSTARTDATE=2026010100/COLDSTARTDATE=auto/;
$local_hot =~ s{LASTSUBDIR=null}{LASTSUBDIR=$lsroot};
write_file($cfg,$local_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'local netCDF4 hotstart layout matching ASGS passes');

# The first existing ASGS source directory wins; do not silently skip a broken hindcast for a valid nowcast.
mkdir "$lsroot/hindcast" or die $!;
write_file("$lsroot/hindcast/run.properties","ColdStartTime : 2026010100\n");
write_file($cfg,$local_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'local LASTSUBDIR follows ASGS hindcast-before-nowcast search order');
like($out,qr{hindcast/fort\.67\.nc.*was not found},'broken earlier source is reported rather than skipped');
unlink "$lsroot/hindcast/run.properties" or die $!;
rmdir "$lsroot/hindcast" or die $!;

# run.properties is part of the actual ASGS hotstart contract.
write_file("$lsroot/nowcast/run.properties","Model : PADCIRC\n");
write_file($cfg,$local_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'local run.properties without ColdStartTime fails');
like($out,qr/does not contain a valid ten-digit ColdStartTime/,'missing ColdStartTime identified');
write_file("$lsroot/nowcast/run.properties","ColdStartTime : 2026010100\n");

my $mismatch_hot=$local_hot;
$mismatch_hot =~ s/COLDSTARTDATE=auto/COLDSTARTDATE=2026020200/;
write_file($cfg,$mismatch_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'explicit COLDSTARTDATE differing from local run.properties is a warning, matching ASGS override behavior');
like($out,qr/current ASGS uses the run\.properties value/,'hotstart cold-start date override is explained');

unlink "$lsroot/nowcast/fort.67.nc" or die $!;
write_file($cfg,$local_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'local hotstart missing fort.67.nc fails');
like($out,qr/fort\.67\.nc.*was not found/,'missing local hotstart file identified');

# Binary local hotstarts are under PE0000/fort.67.
mkdir "$lsroot/nowcast/PE0000" or die $!;
write_file("$lsroot/nowcast/PE0000/fort.67","binary-hotstart\n");
my $binary_hot=$local_hot;
$binary_hot =~ s/createWind10mLayer=yes/createWind10mLayer=yes\nHOTSTARTFORMAT=binary/;
write_file($cfg,$binary_hot);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'local binary hotstart PE0000/fort.67 layout passes');

# INSTANCENAME may be custom. Explicit values are authoritative and are not replaced
# by the current-ASGS derived naming convention.
my $custom_instance=base_config();
$custom_instance =~ s/^INSTANCENAME=test$/INSTANCENAME=my_custom_instance/m;
write_file($cfg,$custom_instance);
{
    local %ENV=(%ENV,ASGS_CONFIG=>$cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},HPCENVSHORT=>'cephas',ASGSADMIN_ID=>'be',ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
    my $lint=bless {config=>$cfg}, 'bin::asgslint';
    $lint->check_config_file;
    my ($name,$source,$missing)=$lint->_derive_instancename;
    is($name,'my_custom_instance','explicit custom INSTANCENAME is preserved verbatim');
    is($source,'config','custom INSTANCENAME provenance is config');
}

# INSTANCENAME is optional in current ASGS and can be reproduced statically when inputs are available.
my $auto_instance=base_config();
$auto_instance =~ s/^INSTANCENAME=test\n//;
write_file($cfg,$auto_instance);
{
    # A real asgsh session commonly exports INSTANCENAME for the currently
    # loaded profile.  This test is specifically for the case where neither
    # ASGS_CONFIG nor the inherited environment supplies INSTANCENAME, so
    # isolate it from the Operator's live shell environment.
    local $ENV{INSTANCENAME};
    delete $ENV{INSTANCENAME};

    ($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},HPCENVSHORT=>'cephas',ASGSADMIN_ID=>'be',ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
    is($rc,0,'config without INSTANCENAME passes because ASGS derives it');
}
{
    local %ENV=(%ENV,ASGS_CONFIG=>$cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},HPCENVSHORT=>'cephas',ASGSADMIN_ID=>'be',ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
    delete $ENV{INSTANCENAME};

    my $lint=bless {config=>$cfg}, 'bin::asgslint';
    $lint->check_config_file;
    my ($name,$source,$missing)=$lint->_derive_instancename;
    is($name,'mesh_gfs_cephas_be','omitted INSTANCENAME is statically derived using current ASGS convention');
    is($source,'derived','derived INSTANCENAME is marked as derived');
    is_deeply($missing,[],'all inputs required for INSTANCENAME derivation were resolved');
}

# mesh_defaults.sh consumes GRIDNAME and explicit parameterPackage at source time.
my $ordered=base_config();
$ordered =~ s/GRIDNAME=mesh/GRIDNAME=mesh\nparameterPackage=default\nsource \$SCRIPTDIR\/config\/mesh_defaults.sh/;
write_file($cfg,$ordered);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,0,'GRIDNAME and parameterPackage before mesh_defaults source pass');

my $late_grid=base_config();
$late_grid =~ s/GRIDNAME=mesh/source \$SCRIPTDIR\/config\/mesh_defaults.sh\nGRIDNAME=mesh/;
write_file($cfg,$late_grid);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'GRIDNAME after mesh_defaults source fails');
like($out,qr/GRIDNAME must be assigned before mesh_defaults\.sh/,'mesh initialization ordering error identified');

my $late_package=base_config();
$late_package =~ s/GRIDNAME=mesh/GRIDNAME=mesh\nsource \$SCRIPTDIR\/config\/mesh_defaults.sh\nparameterPackage=default/;
write_file($cfg,$late_package);
($rc,$out)=run_lint($cfg,ASGS_PLATFORMS=>q{},PLATFORM_INIT=>q{},ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
is($rc,255,'parameterPackage after mesh_defaults source fails');
like($out,qr/parameterPackage is assigned after mesh_defaults\.sh/,'parameter package ordering error identified');

# --explain smoke test
write_file($cfg,base_config());
{
    local %ENV=(%ENV,ASGS_CONFIG=>$cfg,PLATFORM_INIT=>$plat,ASGS_MACHINE_NAME=>'cephas',PPN=>40,QUEUESYS=>'SLURM',QUEUENAME=>'general',SERQUEUE=>'general',SERQUEUE_NTASKS=>1,ACCOUNT=>'null',ADCIRCDIR=>$bindir,ADCIRC_BINS=>'adcirc');
    my $text=q{}; my $x; { local *STDOUT; open STDOUT,'>',\$text or die $!; $x=bin::asgslint::run(['--explain']); }
    like($text,qr/ASGS configuration summary/,'--explain prints interpreted summary');
    like($text,qr/GFS background-meteorology configuration/,'--explain interprets forcing');
}

done_testing;

