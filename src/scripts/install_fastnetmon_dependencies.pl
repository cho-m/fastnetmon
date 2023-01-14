#!/usr/bin/perl

###
### This tool builds all binary dependencies required for FastNetMon
###


use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/perllib";

use Fastnetmon;
use Getopt::Long;

#
# CentOS
# sudo yum install perl perl-Archive-Tar
#

my $library_install_folder = '/opt/fastnetmon-community/libraries';

my $os_type = '';  
my $distro_type = '';  
my $distro_version = '';  
my $distro_architecture = '';  
my $appliance_name = ''; 

my $temp_folder_for_building_project = `mktemp -d /tmp/fastnetmon.build.dir.XXXXXXXXXX`;
chomp $temp_folder_for_building_project;

unless ($temp_folder_for_building_project && -e $temp_folder_for_building_project) {
    die "Can't create temp folder in /tmp for building project: $temp_folder_for_building_project\n";
}

# Pass log path to module
$Fastnetmon::install_log_path = '/tmp/fastnetmon_install.log';

# We do not need default very safe permissions
exec_command("chmod 755 $temp_folder_for_building_project");

my $start_time = time();

my $fastnetmon_code_dir = "$temp_folder_for_building_project/fastnetmon/src";

my $cpus_number = 1;

# We could pass options to make with this variable
my $make_options = '';

unless (-e $library_install_folder) {
    exec_command("mkdir -p $library_install_folder");
}

main();

### Functions start here
sub main {
    my $machine_information = Fastnetmon::detect_distribution();

    unless ($machine_information) {
        die "Could not collect machine information\n";
    }

    $distro_version = $machine_information->{distro_version};
    $distro_type = $machine_information->{distro_type};
    $os_type = $machine_information->{os_type};
    $distro_architecture = $machine_information->{distro_architecture};
    $appliance_name = $machine_information->{appliance_name};
	
    $Fastnetmon::library_install_folder = $library_install_folder;
    $Fastnetmon::temp_folder_for_building_project = $temp_folder_for_building_project;

    $cpus_number = Fastnetmon::get_logical_cpus_number();

    print "Your machine has $cpus_number CPUs\n";

    # We could get huge speed benefits with this option
    if ($cpus_number > 1) { 
        print "You have really nice server with $cpus_number CPU's and we will use they all for build process :)\n";
        $make_options = "-j $cpus_number";
    }

    # Install build dependencies
    my $dependencies_install_start_time = time();
    install_build_dependencies();

    print "Installed dependencies in ", time() - $dependencies_install_start_time, " seconds\n";

    # Init environment
    init_compiler();

    # We do not use prefix "lib" in names as all of them are libs and it's meaning less
    # We use target folder names in this list for clarity
    # Versions may be in different formats and we do not use them yet
    my @required_packages = (
        # 'gcc', # we build it separately as it requires excessive amount of time
        'openssl_1_1_1q',
        'cmake_3_23_4',
        'boost_build_4_9_2',
        'icu_65_1',
        'boost_1_80_0',
        'capnproto_0_8_0',
        'hiredis_0_14',
        'mongo_c_driver_1_23_0',
        
        # gRPC dependencies 
        're2_2022_12_01',
        'abseil_2022_06_23',        
        'zlib_1_2_13',,
        'cares_1_18_1',

        'protobuf_21_12',
        'grpc_1_49_2',
        'bpf_1_0_1',
        'elfutils_0_186',
        'gobgp_2_27_0',
        'log4cpp_1_1_3',
    );

    # Accept package name from command line argument
    if (scalar @ARGV > 0) {
        @required_packages = @ARGV;
    }

    # To guarantee that binary dependencies are not altered in storage side we store their hashes in repository
    my $binary_build_hashes = { 
        'gcc_12_1_0' => {
            'debian:9'            => '63995539b8fb75cc89cc7eb3a2b78aaf55a5083fb95bb2b5199b2f4545329789410c54f04f7449a2f96543f21d51977bdd2b9ede10c70f910459dae83b030212',
            'debian:10'           => '2c18964400a6660eae4ee36369c50829fda4ad4ee049c29aa1fd925bf96c3f8eed3ecb619cc02c6f470d0170d56aee1c840a4ca58d8132ca7ae395759aa49fc7',
            'debian:11'           => '3ad28bf950a7be070f1de9b3184f1fe9f42405cdbc0f980ab97e13d571a5be1441963a43304d784c135a43278454149039bd2a6252035c7755d4ba5e0eb41480',
            'debian:bookworm/sid' => '907bf0bb451c5575105695a98c3b9c61ff67ad607bcd6a133342dfddd80d8eac69c7af9f97d215a7d4469d4885e5d6914766c77db8def4efa92637ab2c12a515',
            'ubuntu:16.04'        => '433789f72e40cb8358ea564f322d6e6c117f6728e5e1f16310624ee2606a1d662dad750c90ac60404916aaad1bbf585968099fffca178d716007454e05c49237',
            'ubuntu:18.04'        => '7955ab75d491bd19002e0e6d540d7821f293c2f8acb06fdf2cb5778cdae8967c636a2b253ee01416ea1cb30dc11d363d4a91fb59999bf3fc8f2d0030feaaba4e',
            'centos:7'            => 'f7bb6b23d338fa80e1a72912d001ef926cbeb1df26f53d4c75d5e20ffe107e146637cb583edd08d02d252fc1bb93b2af6b827bd953713a9f55de148fb10b55aa',
        },
        'openssl_1_1_1q'        => {
            'centos:7'            => 'ab9dde43afc7b6bcc4399b6fbd746727e0ce72cf254e9b7f6abcc5c22b319ab82c051546decc6804e508654975089888c544258514e30dc18385ad1dd59d63fb',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'eac2b5a066386f7900b1e364b5347d87ab4a994a058ecfaf5682a9325fc72362b8532ddf974e092c08bebd9f4cc4b433e00c3ab564c532fa6ed1f30a6b354626',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        }, 
        'cmake_3_23_4'          => {
            'centos:7'            => 'f19d35583461af4a8e90a2c6d3751c586eaae3d18dcf849f992af9add78cf190afe2c5e010ddb9f5913634539222ceb218c2c04861b71691c38f231b3f49f6c5',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'cab3412debee6f864551e94f322d453daca292e092eb67a5b7f1cd0025d1997cfa60302dccc52f96be09127aee493ab446004c1e578e1725b4205f8812abd9ea',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'boost_build_4_9_2'     => {
            'centos:7'            => 'd395a8e369d06e8c8ef231d2ffdaa9cacbc0da9dc3520d71cd413c343533af608370c7b9a93843facbd6d179270aabebc9dc4a56f0c1dea3fe4e2ffb503d7efd',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '89c1a916456f85aa76578d5d85b2c0665155e3b7913fd79f2bb6309642dab54335b6febcf6395b2ab4312c8cc5b3480541d1da54137e83619f825a1be3be2e4e',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'icu_65_1'              => {
            'centos:7'            => '4360152b0d4c21e2347d6262610092614b671da94592216bd7d3805ab5dbeae7159a30af5ab3e8a63243ff66d283ad4c7787b29cf5d5a7e00c4bad1a040b19a2',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '1c10db8094967024d5aec07231fb79c8364cff4c850e0f29f511ddaa5cfdf4d18217bda13c41a1194bd2b674003d375d4df3ef76c83f6cbdf3bea74b48bcdcea',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'boost_1_80_0'          => {
            'centos:7'            => '14c81d9937ce763464ccfb04546ed24d04f052c073132cdde20986bd78f3aae2cb386ab8c63f01bcfe43a60d5eceb1deb750ee54fde1a5e8da28b6d2a6f65a4d',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '1787410b79d314576fcf5a0a0e226ed8b74c1e0c7d4629209bb17221a785b40d4daa07f5df04aec24922266947f4a56a3db8664f563bc2f305efc79279aeb918',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'capnproto_0_8_0'       => {
            'centos:7'            => '5c796240cb57179122653b61ee3ef45ca3d209ad83695424952be93bb3aad89e6e660dba034df94d55cc38d3251c438a2eb81b7de2ed9db967154d72441b2e12',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'e9ba7567657d87d908ff0d00a819ad5da86476453dc207cf8882f8d18cbc4353d18f90e7e4bcfbb3392e4bc2007964ea0d9efb529b285e7f008c16063cce4c4e',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'hiredis_0_14'          => {
            'centos:7'            => '03afc34178805b87ef5559ead86c70b5ae315dd407fe7627d6d283f46cf94fd7c41b38c75099703531ae5a08f08ec79a349feef905654de265a7f56b16a129f1',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '76ca19f7cd4ec5e0251bc4804901acbd6b70cf25098831d1e16da85ad18d4bb2a07faa1a8e84e1d58257d5b8b1d521b5e49135ce502bd16929c0015a00f4089d',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'mongo_c_driver_1_23_0' => {
            'centos:7'            => '8ea15364969ad3e31b3a94ac41142bb3054a7be2809134aa4d018ce627adf9d2c2edd05095a8ea8b60026377937d74eea0bfbb5526fccdcc718fc4ed8f18d826',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '3beadd580e8c95463fd8c4be2f4f7105935bd68a2da3fd3ba2413e0182ad8083fd3339aab59f5f20cc0593ffa200415220f7782524721cb197a098c6175452e9',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        're2_2022_12_01'        => {
            'centos:7'            => 'f0df85b26ef86d2e0cd9ce40ee16542efc7436c79d8589c94601fedac0e06bd0f84d264741f39b4d65a41916f6f1313cfe83fde28056f906bbeeccc60a04fff0',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'f2f6dc33364f22cba010f13c43cea00ce1a1f8c1a59c444a39a45029d5154303882cba2176c4ccbf512b7c52c7610db4a8b284e03b33633ff24729ca56b4f078',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'abseil_2022_06_23'     => {
            'centos:7'            => '671a77966a021fe8ca8f25d6510a4ddd7bea78815c9952126fcfabe583315d68ae6c9257bca4c0ad351ff15ae9a7f27c4dab0a4dff6b9f296713b4dfdef4573d',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '5256e2da02b15e8e69aadb0a96bbffd03858f3aa37cb08c029d726627ee26b0428fc086e94d8a0ce2c6a402b8484b96b3ccb5aa3a15af800348b26ce4873068a',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'zlib_1_2_13'           => {
            'centos:7'            => '649e8353e1c7ad7597378b25a81e3bccda28441a80a40d12a3e5e5bee34b88681e90157118736358e858a964b1bdc8cb1c35c6df3bdc2aeafe31664abcabb93f',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '8f7d5ae6b8922b0da22c94ad6dac2bde9c30e4902db93666c8dd1e8985c7c658a581a296bd160c5fff9c52c969b95aa806a8ae7dd4ee94eeb165d62a7fa499f8',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'cares_1_18_1'          => {
            'centos:7'            => '65902575e20b3297a5a45a6bafcc093a744e4774ea47bb1604c828dfa2eb9a8ccd63cfc4a2bffbb970540ca6f5122235c5e19f10690d898dad341c78a3977383',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '433fdaed84962575809969d36a5587becbcf557221b82dfe4c65c4a67e6736de0dfe1408e1fb8859aacf979931a75483bac7679f210c84a5b030ddeba079524d',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'protobuf_21_12'        => {
            'centos:7'            => '82ad83b8532cf234f9bbc6660c77a893279f8ff27c38b14484db3063a65ca15b3dd427573daf915ef2097137640fa9ff859761e6d0696978f9c120cd31099564',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'b0dde2a94dc7e935f906608be5c8204393e87ba5703b78b84ad41ab690107eb306c50c9572669b0d18a55334ba26ed22a2242b54d6e30dffb1c11f8328b23c20',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'grpc_1_49_2'           => {
            'centos:7'            => '4c77cf97c5c42dfddf002b9b453459ed28c8de3715145c8f162fed45f650400bcdf5c7fc714aa50b1fa14f486ae86b47d6d2cb03d00862281dda4482583385db',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '71c6d626aaebcec2f9faa8df215ac988379ef3b7eeb2bdbef4d176d6a3534ec561fa55a4f2b69979c9cd51dcd52aa59b937718066f35cfb1cef5861f2e988bf8',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'bpf_1_0_1'             => {
            'centos:7'            => 'b6c6b072cef81b2462c280935852f085b7e09f9677723caf9bb5df08971886985446ba20a4aa984381c766ed0fc2d2b9cd2afaa7ab3d63becde566738058fd1d',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'e9f131ab11bf1984d19eac280b0f0f5c6161131d2b3ad06deafd3fb3c14e76f2cbfb0c3b01c88a3df05b4f2bca96d7e7934695b099721ed510c21ef9ae43243b',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'elfutils_0_186'        => {
            'centos:7'            => '23acf9d80f72da864310f13b36b941938a841c6418c5378f6c3620a339d0f018376e52509216417ec9c0ce3d65c9a285d2c009ec5245e3ee01e9e54d2f10b2f8',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => '16bdd1aa0feee95d529fa98bf2db5a5b3a834883ba4b890773d32fc3a7c5b04a9a5212d2b6d9d7aa5d9a0176a9e9002743d20515912381dcafbadc766f8d0a9d',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'gobgp_2_27_0'          => {
            'centos:7'            => 'a907b6cc247147fb2c125ee7c8186c4f2b5b57e3a114e45c53b5373324d02318aad6d3d0397aa3d9761c434f022f8a8bbb2e55caa9c5654966ef9ce85c6206b9',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'c5f16ad35f13555514c3a286b32909f51f9eeada3f0fd7ccba519a6faff8e1d710eb16e7d33132ed7ecc9b2477f49279eeb4cc1dd9ae62b249ffe46522c370d2',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
        'log4cpp_1_1_3'         => {
            'centos:7'            => '5f314177ff82f9b822c76a0256a322e1b8c81575d9b3da33f45532f0942f5358c7588cf1b88a88f8ed99c433c97a3f2fbf59a949eb32a7335c5a8d3a59895a65',
            'centos:8'            => '',
            'centos:9'            => '',
            'debian:10'           => 'a966df89fc18ef4b4ea82cc3d2d53d3ecb3623ef5cd197a23ed8135f27ecfab2d35b4a24f594bb16aaa11b618126cba640ef7a61d7d2d22ba9682e5e0e8114ca',
            'ubuntu:16.04'        => '',
            'ubuntu:18.04'        => '',
            'ubuntu:20.04'        => '',
            'ubuntu:22.04'        => '',
        },
    };

    # How many seconds we needed to download all dependencies
    # We need it to investigate impact on whole build process duration
    my $dependencies_download_time = 0;

    for my $package (@required_packages) {
        print "Install package $package\n";
        my $package_install_start_time = time();

        # We need to get package name from our folder name
        # We use regular expression which matches first part of folder name before we observe any numeric digits after _ (XXX_12345)
        # Name may be multi word like: aaa_bbb_123
        my ($function_name) = $package =~ m/^(.*?)_\d/;

        # Check that package is not installed
        my $package_install_path = "$library_install_folder/$package";

        if (-e $package_install_path) {
            warn "$package is installed, skip build\n";
            next;
        }

        # This check just validates that entry for package exists in $binary_build_hashes
        # But it does not validate that anything in that entry is populated
        # When add new package you just need to add it as empty hash first
        # And then populate with hashes
        my $binary_hash = $binary_build_hashes->{$package}; 

        unless ($binary_hash) {
            die "Binary hash does not exist for $package, please do fresh build and add hash for it\n";
        }

        my $cache_download_start_time = time();

        # Try to retrieve it from S3 bucket 
        my $get_from_cache = Fastnetmon::get_library_binary_build_from_google_storage($package, $binary_hash);

        my $cache_download_duration = time() - $cache_download_start_time;
        $dependencies_download_time += $cache_download_duration;

        if ($get_from_cache == 1) {
            print "Got $package from cache\n";
            next;
        }

        # In case of any issues with hashes we must break build procedure to raise attention
        if ($get_from_cache == 2) {
            die "Detected hash issues for package $package, stop build process, it may be sign of data tampering, manual checking is needed\n";
        }

        # We can reach this step only if file did not exist previously
        print "Cannot get package $package from cache, starting build procedure\n";

        # We provide full package name i.e. package_1_2_3 as second argument as we will use it as name for installation folder
        my $install_res = Fastnetmon::install_package_by_name($function_name, $package);
 
        unless ($install_res) {
            die "Cannot install package $package using handler $function_name: $install_res\n";
        }

        # We successfully built it, let's upload it to cache

        my $elapse = time() - $package_install_start_time;

        my $build_time_minutes = sprintf("%.2f", $elapse / 60);

        # Build only long time
        if ($build_time_minutes > 1) {
            print "Package build time: " . int($build_time_minutes) . " Minutes\n";
        }

        # Upload successfully built package to S3
        my $upload_binary_res = Fastnetmon::upload_binary_build_to_google_storage($package);

        # We can ignore upload failures as they're not critical
        if (!$upload_binary_res) {
            warn "Cannot upload dependency to cache\n";
            next;
        }


        print "\n\n";
    }

    my $install_time = time() - $start_time;
    my $pretty_install_time_in_minutes = sprintf("%.2f", $install_time / 60);

    print "We have installed all dependencies in $pretty_install_time_in_minutes minutes\n";
    
    my $cache_download_time_in_minutes = sprintf("%.2f", $dependencies_download_time / 60);
    
    print "We have downloaded all cached dependencies in $cache_download_time_in_minutes minutes\n";
}