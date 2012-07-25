#!/usr/bin/env perl
#!/usr/bin/perl
#
# Routes the request
#
#
#	Ian Steel
#	September 2006
#
use strict;

use POSIX ":sys_wait_h";

use CGI::Fast;
use Config::IniFiles;

use nasCommon;
use nasCore;
use Service::Shares;
#use Permission;

# Load the individual page modules
#
use nas::home;
use nas::driveman;
use nas::fileshare;
use nas::p2pconf;
use nas::gensetup;
use nas::initsetup;
use nas::home_update;
use nas::home_status;
use nas::upgrade_firmware;
use nas::drive_info;
use nas::user_info;
use nas::backup;
use nas::reboot;

=for dynamic loading

use nas::homedriveconf;
use nas::chgdatetime;
use nas::chgdevicename;
use nas::chgftpportnumber;
use nas::chgusername;
use nas::fs_addshare;
use nas::fs_chgaccesstype;
use nas::fs_deluser;
use nas::fs_newuser;
use nas::fs_getSharePerms;
use nas::fs_removeshare;
use nas::fs_renameshare;
use nas::fs_updsecurity;
use nas::fs_userman;
use nas::language;
use nas::network_info;
use nas::updnetwork;

=cut

# Pre run checks.
#
# Write paths to nbin/setupPaths.sh
# ( This means that nasCommon should be the only place that (most) paths 
# need to be changed.)
#
if (! -w nasCommon->nas_paths ) {
	sudo("$nbin/touch.sh ".nasCommon->nas_paths );
	sudo("$nbin/chown.sh www-data:www-data ".nasCommon->nas_paths);
	sudo("$nbin/chmod.sh 0644 ".nasCommon->nas_paths);
}

my $fdPaths = new IO::File( ">".nasCommon->nas_paths );
if ($fdPaths) {
	print( $fdPaths "# Auto generated by nasMaster.pl on ".gmtime(time())."\n" );
	print( $fdPaths "export SMB_PATH=" . nasCommon->smb_lib . "\n");
	print( $fdPaths "export SMB_HOME=" . nasCommon->smb_home . "\n");
	print( $fdPaths "export SMB_CONF=" . nasCommon->smb_conf . "\n");
	print( $fdPaths "export SMB_PASSWD=" . nasCommon->smbpasswd . "\n");
	print( $fdPaths "export SHARES_HOME=" . nasCommon->nas_shares. "\n");
	print( $fdPaths "export PUBLIC_SHARE=" . nasCommon->public_share . "\n");
	print( $fdPaths "export OXSEMI_HOME=" . nasCommon->nas_home. "\n");
	print( $fdPaths	"export PERL5LIB=" . join(':',$ENV{PERL5LIB},nasCommon->nas_lib). "\n");
	print( $fdPaths	"export NETWORK_SETTINGS=" . nasCommon->network_settings. "\n");
	$fdPaths->close();
}

# Remove any locks
#
# This file is typically used to signal that a disk management process is 
# in progress. If it exists at this stage, it's probbly got left behind due to 
# a reboot during the operation. Delete it.
if ( -e nasCommon->nas_lock ) {
	sudo("$nbin/chown.sh www-data:www-data ".nasCommon->nas_lock );
	sudo("$nbin/chmod.sh +w ".nasCommon->nas_lock );
    unlink( nasCommon->nas_lock )
}

=for future

Permission->path( nasCommon->nas_nbin );	# Where to find the scripts
Permission->new( nasCommon->nas_home,	'0775','root','www-data' )->ensure();
Permission->new( nasCommon->shares_inc,	'0644','www-data','www-data' )->ensure();
Permission->new( nasCommon->senvid_inc,	'0644','www-data','www-data' )->ensure();
Permission->new( nasCommon->nas_ini,	'0666','www-data','www-data' )->ensure();
Permission->new( nasCommon->smb_lib,	'0775','www-data','www-data' )->ensure();
Permission->new( nasCommon->smbpasswd,	'0664','www-data','www-data' )->ensure();
Permission->new( nasCommon->smb_conf,	'0664','www-data','www-data' )->ensure();

=cut

#
# TODO: bruce - I am working on Permissions.pm to simplify this bit of code.
# BUG#2889 bruce - Web UI: No initial shares.inc or senvid.inc files
if (! -w nasCommon->TZ ) {
	sudo("$nbin/touch.sh ".nasCommon->TZ );
	sudo("$nbin/chown.sh root:www-data ".nasCommon->TZ );
	sudo("$nbin/chmod.sh g+w ".nasCommon->TZ );
}
if (! -w nasCommon->network_settings ) {
	sudo("$nbin/chown.sh root:www-data ".nasCommon->network_settings );
	sudo("$nbin/chmod.sh g+w ".nasCommon->network_settings );
}
if (! -w nasCommon->nas_home ) {
	sudo("$nbin/mkdir.sh ".nasCommon->nas_home);
	sudo("$nbin/chown.sh root:www-data ".nasCommon->nas_home);
	sudo("$nbin/chmod.sh 775 ".nasCommon->nas_home);
}
if (! -w nasCommon->shares_inc ) {
	sudo("$nbin/touch.sh ".nasCommon->shares_inc );
	sudo("$nbin/chown.sh www-data:www-data ".nasCommon->shares_inc);
	sudo("$nbin/chmod.sh 0644 ".nasCommon->shares_inc);
}
if (! -w nasCommon->senvid_inc ) {
	sudo("$nbin/touch.sh ".nasCommon->senvid_inc );
	sudo("$nbin/chown.sh www-data:www-data ".nasCommon->senvid_inc);
	sudo("$nbin/chmod.sh 0644 ".nasCommon->senvid_inc);
}
if (! -w nasCommon->nfs_exports ) {
	sudo("$nbin/touch.sh ".nasCommon->nfs_exports );
	sudo("$nbin/chown.sh www-data:www-data ".nasCommon->nfs_exports);
	sudo("$nbin/chmod.sh 0644 ".nasCommon->nfs_exports);
}

# BUG#2890 bruce - /var/oxsemi/nas.ini should be owned by www-data
# Also moved the chmod up to befor the Config::IniFiles
sudo("$nbin/chown.sh www-data:www-data ".nasCommon->nas_ini);
sudo("$nbin/chmod.sh 0666 ".nasCommon->nas_ini);

# BUG#2894 bruce - Check that smbpasswd exists and create if not
if (! -w nasCommon->smbpasswd ) {
	sudo("$nbin/touch.sh ".nasCommon->smbpasswd );
	sudo("$nbin/chown.sh www-data:www-data ".nasCommon->smbpasswd);
	sudo("$nbin/chmod.sh 0664 ".nasCommon->smbpasswd);
	sudo("$nbin/fs_addUser.sh 'www-data' 'blank'" );
}

# BUG#2890 bruce - smb.conf and /usr/local/samba/lib/ should be owned by www-data
# Also moved the chmod up to befor the Config::IniFiles
sudo("$nbin/chown.sh root:www-data ".nasCommon->smb_conf);
sudo("$nbin/chmod.sh 0664 ".nasCommon->smb_conf);
sudo("$nbin/chown.sh root:www-data ".nasCommon->smb_lib);
sudo("$nbin/chmod.sh 0775 ".nasCommon->smb_lib);


# Create the default shares for NFS and Samba
#
Service::Shares->createDefault();

# Open nas.ini
my $config = new Config::IniFiles( -file => nasCommon->nas_ini );

# Extract some data from network-settings and put in nas.ini
if (my $dfs=Config::Tiny->read( nasCommon->network_settings )) {
	my $type = $dfs->{_}->{system_type};
	for ($type) {
		# Map the default_system_type names to our internal type name.
		/1nc/i && ($type='1NC',last);
		/2nc/i && ($type='2NC',last);
	}
	# Store the type in config for later use
	$config->newval( 'general','system_type', $type );
}


# If the disks are good, record their serial numbers to enable detecting new
# drives.
if (Service::Storage->driveStatusCode($config) eq Service::RAIDStatus::OK) {
    # run hdparam to get the serial numbers
    system('sudo /sbin/hdparm -I /dev/sda /dev/sdb | grep "Serial Number" >'.nasCommon->serial_numbers);
}

# Main FCGI Loop
while (my $cgi = new CGI::Fast) {
	waitpid(-1,&WNOHANG);	# Wait for any child, but don't block in case we've called ourself

	my $language = $config->val('general', 'language');

	my $func = $ENV{SCRIPT_NAME};
    my $client = $ENV{REMOTE_ADDR};

	
	my $auth = ($func=~/^\/auth\//); # ensure root directory is auth directory.

	$func =~ s/.*?([^\/]+)\.pl$/$1/;

	# Ensure that pages that require authorization do so
	if ( !$auth && ($func !~ /home|MfgTest/)) {
		$func="home";	# Just display the home page
	}

	$func = 'home' if $func =~ /nasMaster/;
	$func = 'home' unless $func;	# bruce - Added default if blank

	# Ensure that the user visits, and completes, the initial setup page(s) - exception is that
	#	they can change language before completing the initial setup.
	#
	if (	($func ne 'initsetup') && 
		($func ne 'language') &&
		($func ne 'home_update') &&
		($func ne 'home_status') &&
		($func ne 'MfgTest') &&
		($func ne 'language')
	) {
		if ($config->val('general', 'initial_config_done') ne 'y') {
			$func = 'initsetup';
		} 
	}
	
    # Can only access these pages if the initial set-up is not complete.
	if ((($func eq 'MfgTest') ||
         ($func eq 'home_update') ||
         ($func eq 'home_status')) &&
        ($config->val('general', 'initial_config_done') eq 'y') )
	{
			$func = "home" ;
	}

	# Use cookies cookies if usecookie is set
	my $usecookie=$config->val( 'general','usecookie');
	if (($func =~/hold/) ||			# and holding pages
		($func =~/networkstatus/) ||		# and network status ajax
		($func =~/ajax/) ||			# and anything ajax
		($func =~/dm_progress/) ||		# and dm_progress ajax
        ($func =~/MfgTest/)
	) {
		# Flag to ignore cookies
		$usecookie=0;
	}

	# Check that the network has finished starting up before we display any page
	#
	if (($func!~/networkstatus/) &&
		(! -r nasCommon->network_lock) 
	) {
		# No lock and not the network status report
		# Go to the hold page and store originalPage if locked
		$func = "hold";
	}

	# check for upgrade lock file and limit acceptible pages
	if (
		!(	# list allowed pages during upgrade here.
			( $func =~ /ajax/) || #anything ajax is allowed
			($func =~ /home$/ ) # home page for nice front panel view.
		) &&
		( -r '/tmp/active_upgrade' )  # present during upgrade so use as lock
	) {
		# Upgrade in progress so only show upgrade progress page.
		$func = "firmware_progress";
	}
	
	# Create a new object based on the $func name being the same name
	# as a class in nas/*.pm
	# bruce - perhaps enclose in eval() to trap potential errors
	
	$func = "home" unless eval( "use nas::$func;1" );
	$func = "nas::$func";
	eval {
		# Try executing the page
		my $ss = new $func($language,$cgi,$config,$usecookie);
		#print "made $ss of $func\n";
		$ss->processRequest();	## ($cgi, $config);
		1; 
	} || do {
		# Display the fatal error page
		my $ss = new nasCore( $language,$cgi,$config );
		$ss->fatalError( $config, 'f00000', $!.$@ );
	};
}
