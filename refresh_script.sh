#!/bin/bash
## ---------------------------------------------------------------------------
## This software is the confidential and proprietary information
## ("Confidential Information") of Oracle and/or its affiliates
## ("The Company").
## You shall not disclose such Confidential Information and shall use
## and alter it only in accordance with the terms of the agreement(s)
## you entered into with Oracle and/or its affiliates.
## ---------------------------------------------------------------------------
##
## Team: Oracle CPQ OPS
##
## Created by Slobodan Radovic, Michael Weinberg 
##
## Last update: March 4th, 2021
##
## Copyright (c) 2020, Oracle and/or its affiliates. All rights reserved.
##
## ---------------------------------------------------------------------------
#CH3 / DC3 Only
#default location:/Repo_Ops/Scripts/refresh
#set variables

#CONSTANTS
SUDO="sudo -i";
SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
DATE=`date '+%m%d%y.%H'`;

#the following are set by default and interchangeable 
destination_backup="yes";
source_backup="yes";
big_db_user="";
backup_paraller_number="8";
using_param_file="no";
using_image='no'
batch='no';
DEF_TEMPLATE="propman_default"
PPARTIAL="";
DPARTIAL="";
Xms="9g";
XX="3g";
destination_script_start="";
destination_script_stop="";
remove_destination_frontend="yes";
remove_destination_schema="yes";
skip_prompt='no'


##assert running in screen
[ -z "$STY" ] && echo "ERROR: Must run using screen" && exit 1

#the following are set by default and not interchangeable 
username="$(whoami)";
backup_location="/fsnhome/${username}/refresh_backup";
if [[ -d "/fsnhome/${username}/refresh_backup" ]]; then printf "\nVerified /fsnhome/${username}/refresh_backup\n"; else mkdir -p "/fsnhome/${username}/refresh_backup" && printf "Created /fsnhome/${username}/refresh_backup"; fi;

#db variables 
g_target_user_oracle='oracle';
oracle_scripts="/home/oracle/oracle_scripts"
g_db_orabin="/usr/local/orabin"
upgrade_maps="/Repo_Ops/components/maps"

#check for encrypt.jar
[[ ! -f './encrypt.jar' ]] && printf "Missing encrypt.jar, please verify it's location\n" && exit 1;

#check for cleansite_new
[[ ! -f './cleansite' ]] && printf "Missing cleansite, please verify it's location\n" && exit 1;

#verify if directory exists /Repo_Ops/cpqtools/cpq-tools-latest
while [ ! -d "/Repo_Ops/cpqtools/cpq-tools-latest" ]
do
   printf "/Repo_Ops/cpqtools/cpq-tools-latest is missing, please verify the location....\n" ;
   sleep 1
   printf "Is /Repo_Ops/cpqtools/cpq-tools-latest available?\n";
   printf "Please answer (y / n)\n";
   read yn
    case $yn in
        [Yy]* ) break
		;;
        [Nn]* ) echo "aborting..." && exit 1
		;;
        * ) echo "Please answer y (yes) or n (no)"
		;;
    esac
done

#check for propman directory
while [ ! -d "./propman_templates" ]
do
   printf "./propman_templates is missing, please verify the location....\n" ;
   sleep 1
   printf "Is ./propman_templates available?\n";
   printf "Please answer (y / n)\n";
   read yn
    case $yn in
        [Yy]* ) break
		;;
        [Nn]* ) echo "aborting..." && exit 1
		;;
        * ) echo "Please answer y (yes) or n (no)"
		;;
    esac
done

#clean exit
trap cleanexit SIGHUP SIGINT SIGQUIT

cleanexit()
{
  echo "exiting..."
  exit 0
}

#command syntax
function usage() #add newer options
{
  echo "Command Syntax: "
  echo
  echo " 	  -S <source fqdn> -D <destination fqdn> -I <path_to_image-skip source backup> -B <path_to_bck_location> -N <skip destination backup> -P <location of PARAM. FILE>"
  echo ""
  echo "      where: "
  echo "             -S               <source fqdn> "
  echo "             -D               <dest fqdn> "
  echo "             -I               path to existing source's image, skip back up of a source site"
  echo "             -B		      backup path location | by default set to /fsnhome/whoami/refresh_backup/"
  echo "             -N               skip backup of a destination site"
  echo "             -P 	      path of destination's PARAM. FILE"
  echo "             -b               for importing a schema over 150GB (big user flag)"
  echo "             -l <no.>         number of parallel for pullsite"
  echo "             -x 	      step to start deployimage"
  echo "             -y               step to stop deployimage"
  echo "             -o        	      pull front-end and deploy front-end (-o fs ) / schema must be already present" 
  echo "             -T 	      propman template name | path: propman_templates/template_folder"
  echo "	     -F		      skip destination's front end removal"
  echo "	     -R               skip destination's schema removal"
  echo "             -Q       	  skip prompts"
  echo
  echo "      example: "
  echo "             refresh_script.sh -S cpq-s41-001.web.dem.ch3.bmi -D cpq-m12-002.web.dem.ch3.bmi"
  echo ""
  exit 0;
}

set_arguments() {
	local OPTARG;
	while getopts ":S:D:I:B:P:l:x:y:T:F:R:NboQ" OPTION ; do
	  case "${OPTION}" in
		S)
		  source_site=${OPTARG};
		  ;;
		D)
		  destination_site=${OPTARG};
		  ;;
		I)
		  source_site_image=${OPTARG};
		  source_backup="no";
		  using_image='yes'
		  ;;
		l)
		  backup_paraller_number=${OPTARG};
		  ;;
		x)
          destination_script_start=" -s ${OPTARG}";
		  ;;
		y)
		  destination_script_stop=" --stopbefore ${OPTARG}";
		  ;;
		B)
		  backup_location=${OPTARG};
		  ;;
		T)
		  DEF_TEMPLATE=${OPTARG};
		  ;;
		o)
		  PPARTIAL="-o fs";
		  DPARTIAL="--deploytype fs -s 5";
		  remove_destination_schema="no"
		  ;;
		b)
		  big_db_user="-b";
		  ;;
		N)
		  destination_backup="no"
		  ;;
		P)
		  destination_deployimage_param=${OPTARG};
		  using_param_file="yes"
		  destination_backup="no";
		  source_backup="no"; 
		  ;;
		F)
		  remove_destination_frontend="no"
		  ;;
		R)
		  remove_destination_schema="no"
		  ;;
		Q)
		  skip_prompt='yes'
		  ;;
		*)
		  usage;
		  ;;
		?)
		  usage;
		 ;;
	  esac;
	done;
	
[[ -z ${source_site} || -z ${destination_site} ]] && printf "\nOne of the default values is missing, please check command syntax below\n" && usage && exit 1;
#if [[ ${source_backup} == "no" ]] && [[ ${using_image} == "no" ]] ; then printf "Can not skip source's backup with out source's image (option -I)\n" && exit 1; fi
}

logging (){
mkdir -m 777 logs 2>/dev/null
exec 2>logs/refresh/refresh_site-${destination_site}-`date +'%Y%m%d-%H%M%S'`.log
set -x
}

#get variables from source and destination sites

#source variables
get_source_variables() {
#check connection
source_site_version="`ssh ${SSHOPTS} ${source_site} 'grep ^bigmac.version /bigmac/conf/build.properties | cut -f2 -d=' | tr -d '\r'`";
if [[ -z ${source_site_version} ]]
	then 
		printf "please verify if ${source_site} reachable...\n"
		exit 1;
fi
source_site_eth1=$(ssh ${SSHOPTS} ${source_site} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
source_site_eth0=$(ssh ${SSHOPTS} ${source_site} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth0 | cut -f2 -d=");
#clear keys
echo "";
printf "Resetting known_hosts keys for source site.....\n"
ssh-keygen -R ${source_site};
ssh-keygen -R ${source_site_eth0};
ssh-keygen -R ${source_site_eth1};
ssh ${SSHOPTS} ${source_site} "exit";
ssh ${SSHOPTS} ${source_site_eth1} "exit" ;
source_short_name=$(ssh ${source_site} "hostname -s" | tr -d '\r');
source_full_name=$(ssh ${source_site} "hostname" | tr -d '\r');
source_datacenter=`echo ${source_full_name} | cut -d. -f4`;
source_site_type=`echo ${source_full_name} | cut -d. -f3`;
source_schema_name=$(ssh ${source_site} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d=");
#verify provided site name and full hostname
if [ "${source_site}" != "${source_full_name}" ]; then
      printf "Something is wrong!!! Provided site name does not match full hostname\n";
	  printf "${source_site}" != "${source_full_name}";
      exit 1;
fi
#verify variables for source
[[ -z ${source_short_name}  ]] && printf "source_short_name is missing, please check the site\n"  && exit 1;
[[ -z ${source_full_name}  ]] && printf "source_full_name is missing, please check the site\n"  && exit 1;
[[ -z ${source_datacenter}  ]] && printf "source_datacenter is missing, please check the site\n"  && exit 1;
[[ -z ${source_site_type}  ]] && printf "source_site_type is missing, please check the site\n"  && exit 1;
[[ -z ${source_schema_name}  ]] && printf "source_schema_name is missing, please check the site\n"  && exit 1;
}

set_source_variables() {
#set registry name and datapump dir
if [[ ${source_datacenter} == 'dc3' ]]; then
                source_registry_name='provadmin-dc3.app.mgt.dc3.bmi';
                source_dc_datadump="7"
elif [[ ${source_datacenter} == 'ch3' ]]; then
                source_registry_name='provadmin.app.mgt.ch3.bmi';
                source_dc_datadump="8"
elif  [[ ${source_datacenter} == 'com' ]]; then
                source_registry_name='provadmin-am3.nldc1.oraclecloud.com:5043';
                source_dc_datadump="9"
else
     printf "No data center found (source)!!!!\n"
     exit 1;
fi
#set datapump type dir for CH3 / DC3
if [[ ${source_datacenter} == 'dc3' || ${source_datacenter} == 'ch3' ]]; then
	if [[ ${source_site_type} == 'prd' ]]; then
		source_dc_type='6';
	elif [[ ${source_site_type} == 'tst' ]]; then
		source_dc_type='7';
	elif [[ ${source_site_type} == 'dem' ]]; then
		source_dc_type='8';
	else
		printf "No data type found!!!!\n"
		exit 1;
	fi
fi
#set datapump type dir for AM3
if [[ ${source_datacenter} == 'com' ]]; then
	source_dbsid_mapped=$(grep -v ^# ${upgrade_maps}/site.map | grep -i "^\<${source_schema_name}\>" | head -1 | awk '{print $5}') || printf "schema name is not found in site.map\n";
	source_site_type=$(echo ${source_dbsid_mapped:2:3})
	if [[ ${source_site_type} == 'PRD' ]]; then
			source_dc_type='6';
	elif [[ ${source_site_type} == 'TST' ]]; then
			source_dc_type='7';
	elif [[ ${source_site_type} == 'DEM' ]]; then
			source_dc_type='8';
	else
		 printf "No data type found!!!!\n"
		 exit 1;
	fi
fi
}

#destination variables
get_destination_variables() {
#check connection
destination_site_version="`ssh ${SSHOPTS} ${destination_site} 'grep ^bigmac.version /bigmac/conf/build.properties | cut -f2 -d=' | tr -d '\r'`";
if [[ -z ${destination_site_version} ]]
	then 
		printf "please verify if ${destination_site} reachable...\n"
		exit 1;
fi
destination_site_eth1=$(ssh ${SSHOPTS} ${destination_site} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
destination_site_eth0=$(ssh ${SSHOPTS} ${destination_site} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth0 | cut -f2 -d=");
#clear keys
echo "";
printf "Resetting known_hosts keys for destination site.....\n"
ssh-keygen -R ${destination_site};
ssh-keygen -R ${destination_site_eth0};
ssh-keygen -R ${destination_site_eth1};
ssh ${SSHOPTS} ${destination_site} "exit";
ssh ${SSHOPTS} ${destination_site_eth1} "exit" ;
destination_short_name=$(ssh ${destination_site} "hostname -s" | tr -d '\r');
destination_full_name=$(ssh ${destination_site} "hostname" | tr -d '\r');
destination_datacenter=`echo ${destination_full_name} | cut -d. -f4`;
destination_site_type=`echo ${destination_full_name} | cut -d. -f3`;
destination_schema_name=$(ssh ${destination_site} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d=");
destination_schema_password=`ssh ${destination_site} "grep ^db_pass /bmfs/cpqShared/conf/database.properties | cut -b13- " | tr -d '\r'`;
destination_schema_decrypted_password=`java -jar encrypt.jar AES decrypt ${destination_schema_password}`;
destination_tas_id=$(ssh ${destination_site} "grep ^tas_subscription_id /bmfs/cpqShared/conf/tas.properties | cut -f2 -d=");
destination_dbhost_mapped=$(grep -v ^# ${upgrade_maps}/site.map | grep -i "^\<${destination_schema_name}\>" | head -1 | awk '{print $2}');
destination_dbsid_mapped=$(grep -v ^# ${upgrade_maps}/site.map | grep -i "^\<${destination_schema_name}\>" | head -1 | awk '{print $5}');
destination_deployimage_param="./logs/deploy_param_file/${destination_site}_deployimage_${destination_site_version}_param.txt";
#verify provided site name and full hostname
if [ "${destination_site}" != "${destination_full_name}" ]; then
      printf "Something is wrong!!! Provided site name does not match full hostname\n";
	  printf "${destination_site}" != "${destination_full_name}\n";
      exit 1;
fi
#verify variables for destination
[[ -z ${destination_short_name}  ]] && printf "destination_short_name is missing, please check the site\n"  && exit 1;
[[ -z ${destination_full_name}  ]] && printf "destination_full_name is missing, please check the site\n"  && exit 1;
[[ -z ${destination_datacenter}  ]] && printf "destination_datacenter is missing, please check the site\n"  && exit 1;
[[ -z ${destination_site_type}  ]] && printf "destination_site_type is missing, please check the site\n"  && exit 1;
[[ -z ${destination_schema_name}  ]] && printf "destination_schema_name is missing, please check the site\n"  && exit 1;
[[ -z ${destination_schema_password}  ]] && printf "destination_schema_password is missing, please check the site\n"  && exit 1;
[[ -z ${destination_schema_decrypted_password}  ]] && printf "destination_schema_decrypted_password is missing, please check the site\n"  && exit 1;
[[ -z ${destination_tas_id}  ]] && printf "destination_tas_id is missing, please check the site\n"  && exit 1;
[[ -z ${destination_dbhost_mapped}  ]] && printf "destination_dbhost_mapped is missing, please check the site\n"  && exit 1;
[[ -z ${destination_dbsid_mapped}  ]] && printf "destination_dbsid_mapped is missing, please check the site\n"  && exit 1;
[[ -z ${destination_deployimage_param}  ]] && printf "destination_deployimage_param is missing, please check the site\n"  && exit 1;
}

get_destination_java_security () {
destination_keyStorePassword=$( ssh ${destination_site} 'grep ^java_args= /bigmac/conf/node1.properties | tr " " "\n" | grep "Djavax.net.ssl.keyStorePassword=" | cut -d= -f2' );
destination_keyStore=$( ssh ${destination_site} 'grep ^java_args= /bigmac/conf/node1.properties | tr " " "\n" | grep "Djavax.net.ssl.keyStore=" | cut -d= -f2' );
destination_keyStoreType=$( ssh ${destination_site} 'grep ^java_args= /bigmac/conf/node1.properties | tr " " "\n" | grep "Djavax.net.ssl.keyStoreType=" | cut -d= -f2' );
}

get_sflCertificate () {
verify_sflCertificate=$( ssh ${destination_site} "if [[ -f /bmfsweb/${destination_short_name}/sflCertificate.crt || -f /bmfsweb/${destination_short_name}/sflCertificate.cer ]]; then printf 'found sflCertificate.crt file';fi" );
if [[ -z ${verify_sflCertificate} ]]; then
		restore_sflCertificate="no";
	else
		restore_sflCertificate="yes";
		destination_sflCertificate_location="/var/tmp/${destination_short_name}-sflCertificate-${DATE}"
		ssh -t -t ${destination_site} "
		mkdir ${destination_sflCertificate_location}
		sudo cp -rf /bmfsweb/${destination_short_name}/sflCertificate.* ${destination_sflCertificate_location}
		"
fi
}

clean_backup_destination_site () {
echo ""
printf "current files under /backup folder on ${destination_site}\n";
ssh -t -t ${destination_site} 'ls -lhrt /backup';
echo ""
printf "Clean backup folder on ${destination_site}\n";
ssh -t -t ${destination_site} 'sudo bash -c "find /backup/* -mtime +7 -type d -exec rm -vrf {} \\;"'
printf "Clean up completed\n";
echo ""
}

destination_parameter_file() {
#create a back up parameter file
cat <<-_destination_image_parameters > "${destination_deployimage_param}"
				destination_site_version=${destination_site_version}
				destination_tas_id=${destination_tas_id}
				destination_schema_decrypted_password=${destination_schema_decrypted_password}
				destination_schema_password=${destination_schema_password}
				source_image_location=${source_image_location}
				destination_dbhost_mapped=${destination_dbhost_mapped}
				destination_schema_name=${destination_schema_name}
				destination_site_eth1=${destination_site_eth1}
				destination_short_name=${destination_short_name}
				destination_dbsid_mapped=${destination_dbsid_mapped}
				destination_site_type=${destination_site_type}
				destination_datacenter=${destination_datacenter}
                destination_full_name=${destination_full_name}
				destination_keyStorePassword=${destination_keyStorePassword}
				destination_keyStore=${destination_keyStore}
				destination_keyStoreType=${destination_keyStoreType}
_destination_image_parameters
#check parameter file creation status
local parameter_creation_status=$?
if [ $parameter_creation_status -ne 0 ]; then
	echo ""
	printf "\nPlease verify if ${destination_deployimage_param} was created..\n";
	echo ""
else
	echo ""
	printf "\n${destination_deployimage_param} was created..\n";
	echo ""
fi;
}

destination_deploy_parameters() {
	destination_tas_id=$(grep ^destination_tas_id ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_schema_password=$(grep ^destination_schema_password ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_schema_decrypted_password=$(grep ^destination_schema_decrypted_password ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_schema_name=$(grep ^destination_schema_name ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_site_eth1=$(grep ^destination_site_eth1 ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_short_name=$(grep ^destination_short_name ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	source_image_location=$(grep ^source_image_location ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_dbsid_mapped=$(grep ^destination_dbsid_mapped ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_dbhost_mapped=$(grep ^destination_dbhost_mapped ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_datacenter=$(grep ^destination_datacenter ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_site_type=$(grep ^destination_site_type ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_site_version=$(grep ^destination_site_version ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
    destination_full_name=$(grep ^destination_full_name ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_keyStorePassword=$(grep ^destination_keyStorePassword ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_keyStore=$(grep ^destination_keyStore ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
	destination_keyStoreType=$(grep ^destination_keyStoreType ./logs/deploy_param_file/${destination_deployimage_param} | cut -f2 -d=);
}

set_destination_variables() {
if [[ ${using_param_file} == "yes" ]]; then destination_deploy_parameters; fi
#set registry name and datapump dc dir 
if [[ ${destination_datacenter} == 'dc3' ]]; then
                destination_registry_name='provadmin-dc3.app.mgt.dc3.bmi';
                destination_dc_datadump="7"
elif [[ ${destination_datacenter} == 'ch3' ]]; then
                destination_registry_name='provadmin.app.mgt.ch3.bmi';
                destination_dc_datadump="8"
elif  [[ ${destination_datacenter} == 'com' ]]; then
                destination_registry_name='provadmin-am3.nldc1.oraclecloud.com:5043';
                destination_dc_datadump="9"
else
     printf "No data center found (destination)!!!!\n"
     exit 1;
fi
#set datapump type dir for CH3 / DC3
if [[ ${destination_datacenter} == 'dc3' || ${destination_datacenter} == 'ch3' ]]; then
	if [[ ${destination_site_type} == 'prd' ]]; then
			destination_dc_type='6';
	elif [[ ${destination_site_type} == 'tst' ]]; then
			destination_dc_type='7';
	elif [[ ${destination_site_type} == 'dem' ]]; then
			destination_dc_type='8';
	else
		 printf "No data type found!!!!\n"
		 exit 1;
	fi
fi
#set datapump type dir for AM3
if [[ ${destination_datacenter} == 'com' ]]; then
	destination_dbsid_mapped=$(grep -v ^# ${upgrade_maps}/site.map | grep -i "^\<${destination_schema_name}\>" | head -1 | awk '{print $5}') || printf "schema name is not found in site.map\n" && exit 1;
	destination_site_type=$(echo ${destination_dbsid_mapped:2:3})
	if [[ ${destination_site_type} == 'PRD' ]]; then
			destination_dc_type='6';
	elif [[ ${destination_site_type} == 'TST' ]]; then
			destination_dc_type='7';
	elif [[ ${destination_site_type} == 'DEM' ]]; then
			destination_dc_type='8';
	else
		 printf "No data type found!!!!\n"
		 exit 1;
	fi
fi

destination_verify_cpqctl=`ssh -t -t ${destination_site} 'sudo bash -c "if [[ -f /bigmac/bin/cpqctl ]]; then echo 'yes'; fi" ' | tr -d '\r'`;
}

check_diskspace_on_source_and_destination() {
#get size of folders for source check /bigmac /bmfs /bmfsweb
source_folders_size=$(ssh $SSHOPTS -t -t ${source_site} "${SUDO} du -s /bmfsweb /bmfs /bigmac | awk {'print \$1}' | awk '{n += \$1}; END{print n}'") #divide by 1048576 to get Gb
#approximate container size 3G = 3145728
source_folders_size_total=$(awk "BEGIN {print 3145728+$source_folders_size; exit}")
destination_free_size="`ssh $SSHOPTS -t -t ${destination_site} \"df -P | grep \/dev\/mapper\/VolGroupRoot-LogVolRoot | awk '{ print \\$4 }'\"`";#divide by 1048576 to get Gb
}

destination_schema_check() {
#verify db schema user 
echo "";
printf "Checking ${destination_schema_name}\n";
verify_destination_schema_name=$(ssh -q -t -t $destination_dbhost_mapped "sudo su - oracle -c \"ORACLE_SID=${destination_dbsid_mapped} ; sqlplus / as sysdba <<-EOF
set echo off
set head off
select 'tablez='||lower(tablespace_name)
from user_tablespaces
where lower(tablespace_name)=('${destination_schema_name}');
exit
EOF
\" 2>&1 | grep ^tablez= | cut -d= -f2" | tr -d '\r' )
if [[ -z ${verify_destination_schema_name} ]]
then
     echo "";
	 printf "please verify if ${destination_schema_name} exists on ${destination_dbsid_mapped} at ${destination_dbhost_mapped}...\n";
	 echo "";
	 return 1;
else
     echo "";
	 printf "${destination_schema_name} exists on ${destination_dbsid_mapped} at ${destination_dbhost_mapped}...\n";
	 echo "";
fi
}

destination_propman_setup() { #skip_prompt_update 
#verify if propman files exist on destination site
printf "starting propman configuration on ${destination_site}\n"
ssh -t -t ${destination_site} "
	if [[ ! -d "/var/tmp/propman" ]]; then
	printf "Directory /var/tmp/propman does not exist on target ${destination_site}\n";
	exit 255;
	fi"
#configure propman
if [[ "$?" -eq "255" ]]; then
	printf "Creating directory /var/tmp/propman on ${destination_site}\n";
    rsync -avzh ./propman_templates/${DEF_TEMPLATE}/ ${destination_site}:/var/tmp/propman/ 
    bash propman replace ${destination_site}
else
	if [[ ${skip_prompt} == 'yes' ]]; then
			printf "Removing existing /var/tmp/propman on target ${destination_site}\n";
			ssh -t -t ${destination_site} "sudo chown -R ${username}:ops /var/tmp/propman";
			bash ${SUDO} propman delete ${destination_site};
			sleep 2
			rsync -avzh ./propman_templates/${DEF_TEMPLATE}/ ${destination_site}:/var/tmp/propman/;
			bash propman replace ${destination_site};
			printf "Completed propman for ${destination_short_name}\n"
	else 
		while true; do
			echo "";
			printf "Do you want to remove existing /var/tmp/propman and create new? : (y/n) \n";
			read yn
			case $yn in
				[Yy]* ) 
				printf "Removing existing /var/tmp/propman on target ${destination_site}\n";
				ssh -t -t ${destination_site} "sudo chown -R ${username}:ops /var/tmp/propman";
				bash ${SUDO} propman delete ${destination_site};
				sleep 2
				rsync -avzh ./propman_templates/${DEF_TEMPLATE}/ ${destination_site}:/var/tmp/propman/;
				bash propman replace ${destination_site};
				printf "Completed propman for ${destination_short_name}\n"
				return 0
				;;
				[Nn]* ) echo "aborting to create propman..." && return 1
				;;
				* ) echo "Please answer y (yes) or n (no)"
				;;
			esac
		done
	fi
fi;
}

show_destination_variables() {
echo "";
printf "Verify the information below:\n"
echo "";
if [[ ${destination_backup} == "no" ]]; then printf "Skipping destination (${destination_short_name}) backup\n"; fi
if [[ ${source_backup} == "no" ]]; then printf "Skipping source (${source_short_name}) backup\n"; fi
if [[ ${remove_destination_frontend} == "no" ]]; then printf "Skipping removal of (${destination_short_name})'s front end\n"; fi
if [[ ${remove_destination_schema} == "no" ]]; then printf "Skipping removal of (${destination_short_name})'s schema\n"; fi
echo "";
printf "Source site:\n";
echo -e "site name: \e[44m${source_short_name}\e[m";
printf "site version: ${source_site_version}\n";
printf "data transfer size (front end only): `awk "BEGIN {print ${source_folders_size_total} / 1048576; exit}"` GB\n";
printf "site type: ${source_site_type}\n";
printf "location: ${source_datacenter}\n";
if [[ ${using_image} == 'yes' ]]; then printf "source image: ${source_site_image}\n"; fi;
echo "";
printf "********************************************\n"
echo "";
if [[ ${destination_site_type} =~ prd|PRD ]]; then printf "Destination is a PRODUCTION environment, please verify, that it is the intended destination\n"; fi;
printf "Destination site:\n"
echo -e "site name: \e[42m${destination_short_name}\e[m";
printf "site version: ${destination_site_version}\n";
printf "site type: ${destination_site_type}\n";
printf "location: ${destination_datacenter}\n";
printf "site TAS_ID: ${destination_tas_id}\n";
printf "site DB: ${destination_dbsid_mapped}\n";
printf "site DB ip: ${destination_dbhost_mapped}\n";
printf "site schema name: ${destination_schema_name}\n";
printf "encrypted db password: ${destination_schema_password}\n";
printf "decrypted db password: ${destination_schema_decrypted_password}\n";
echo "";
destination_free_size_gb=`awk "BEGIN {print ${destination_free_size} / 1048576; exit}"`
printf "available space on destination site (front end only): ${destination_free_size_gb}GB\n";
distination_available_space=`awk "BEGIN {print ${destination_free_size} - ${source_folders_size_total}; exit}"`
distination_available_space_gb=`awk "BEGIN {print ${distination_available_space} / 1048576; exit}"`
distination_required_space=`echo ${distination_available_space_gb} | awk '{print int($1 + 1)}'`
printf "********************************************\n"
if [[ ${distination_required_space} -lt 5 ]]; then 
		printf "less than 5GB (${distination_required_space}GB) will be available after this deployment, please remove unnecessary data from destination site and try again\n"; 
	else 
		printf "More than 5GB will be available (${distination_required_space}GB) on destination site after this deployment\n"; 
fi;
printf "********************************************\n"
echo "";
printf "****************Certificates****************\n"
if [[ -z ${destination_keyStore} ]]; then
		echo ""
		printf "Destination site does not have custom certificates\n"
		restore_source_java_properties="no";
	else
		echo ""
		printf "Destination site has custom certificates, which will be restored after refresh\n"
		echo ""
		restore_source_java_properties="yes";
		printf "Set Djavax.net.ssl.keyStorePassword=${destination_keyStorePassword}\n"
		printf "Set Djavax.net.ssl.keyStore=${destination_keyStore}\n"
		printf "Set Djavax.net.ssl.keyStoreType=${destination_keyStoreType}\n"
fi
if [[ -z ${verify_sflCertificate} ]]; then
		echo ""
		printf "Destination site does not have sflCertificate\n"
		echo ""
	else
		echo ""
		printf "Destination site has sflCertificate, which will be restored after refresh\n"
		echo ""
fi
printf "********************************************\n"
echo "";
}

destination_start_rngd() {
printf "starting rngd on ${destination_short_name}...\n"
echo "";
ssh -t -t  $destination_site "${SUDO} systemctl start rngd";
}

timeout_skip_prompt() {
echo ""
printf "Please review information above...\n"
printf "Refresh of ${destination_short_name} with the image of ${source_short_name} is starting in 15 seconds:"
echo ""
for i in {15..01}
do
	echo -ne "$i\033[0K\r"
	sleep 1
done
echo
echo ""
printf "Starting refresh...\n"
echo ""
}

#skip oemblackout if skip_prompt
upgrade_prompt() {
echo "";
while true; do
    printf "If information above is correct, proceed with oem blackout and stopping ${destination_short_name}? (y / n)";
    read yn
    case $yn in
        [Yy]* ) break
		;;
        [Nn]* ) echo "aborting..." && exit 1
		;;
        * ) echo "Please answer y (yes) or n (no)"
		;;
    esac
done
destination_start_rngd 
}

oem_blackout() {
#oemblackout 
echo "";
printf "starting oemblackout for ${destination_short_name}\n";
echo "";
if [[ ${destination_datacenter} == 'dc3' ]]
	then 
		#ssh -t -t 172.30.254.80 "bash /scripts/oemblackout start -h ${destination_site} -n \"refresh-${destination_site}\" -d \"12:00\" "
		bash /scripts/oemblackout start -h ${destination_site} -n \"refresh-${destination_site}\" -d \"12:00\"
elif [[ ${destination_datacenter} == 'ch3' ]]
	then 
		#ssh -t -t 172.27.254.80 "bash /scripts/oemblackout start -h ${destination_site} -n \"refresh-${destination_site}\" -d \"12:00\" "
		bash /scripts/oemblackout start -h ${destination_site} -n \"refresh-${destination_site}\" -d \"12:00\"
else 
	printf "Skipping blackout for ${destination_short_name}\n";
fi
echo "";
if [[ ! -z ${destination_verify_cpqctl} ]]
	then 
		printf "destination_script_stopping ${destination_short_name}...\n"
		echo "";
		ssh -t -t  $destination_site "${SUDO} bash -c 'source /home/bm/.bash_profile; bash /bigmac/bin/cpqctl stop'";
		echo "";
	else 
		echo "";
		printf "${destination_short_name} is already down\n";
		echo "";
fi
}

#backup source and destination
complete_backups() {
if [[ ${using_param_file} == "no" ]]; then destination_parameter_file; fi;
#backup for destination
if [[ ${destination_backup} == yes ]]
	then
		destination_image_location="${backup_location}/${destination_short_name}-${DATE}"
        if [ -d "${destination_image_location}" ]
			then
                printf "Warning: Directory ${destination_image_location} exists! Please remove or rename directory.\n";
                exit 1;
        fi;
        mkdir -p ${destination_image_location}
        chmod 777 ${destination_image_location}
        printf "Started pulling destination (${destination_short_name}) with the following command:\n" 
		printf "bash pullsite -i ${destination_image_location} -k  ${destination_schema_name}  -t ${destination_site} -D /bmsrv99${destination_dc_datadump}${destination_dc_type}/oracle/backup/datapump_ondemand -l ${NO_PARALL} -v -M prod ${PPARTIAL} --oci legacy\n"
        bash pullsite -i ${destination_image_location} -k  ${destination_schema_name}  -t ${destination_site} -D /bmsrv99${destination_dc_datadump}${destination_dc_type}/oracle/backup/datapump_ondemand -l ${backup_paraller_number} -v -M prod ${PPARTIAL} --oci legacy 2>&1 &
		EXPPID=$!
		#export $EXPPID #error - export: `23953': not a valid identifier / not needed as everything is ran under the same session
		echo "";
		printf "destination's back up PID: $EXPPID\n"
		echo "";
	else
        printf "skipping backup of a destination site(${destination_short_name})\n";
		echo ""
fi;
#backup for source
if [[ ${using_image} == 'no' ]]
	then
		if [[ ${source_backup} == yes ]]
			then
				source_image_location="${backup_location}/${source_short_name}-${DATE}"
                if [ -d "${source_image_location}" ]
					then
                    printf "Warning: Directory ${source_image_location} exists! Please remove or rename directory.\n";
					exit 1;
                fi;
        mkdir -p ${source_image_location}
        chmod 777 ${source_image_location}
        printf "Started pulling source (${source_short_name}) with the following command:\n" 
		printf "bash pullsite -i ${source_image_location} -k  ${source_schema_name}  -t ${source_site} -D /bmsrv99${source_dc_datadump}${source_dc_type}/oracle/backup/datapump_ondemand -l ${backup_paraller_number} -v -M prod ${PPARTIAL} --oci legacy\n"
        echo "";
        bash pullsite -i ${source_image_location} -k  ${source_schema_name}  -t ${source_site} -D /bmsrv99${source_dc_datadump}${source_dc_type}/oracle/backup/datapump_ondemand -l ${backup_paraller_number} -v -M prod ${PPARTIAL} --oci legacy;
        if [[ -f "${source_image_location}/cpq-image.info" ]]; then 
			printf "\nback up ${source_image_location} has been created successfully\n"
		else
			printf "\nplease verify ${source_image_location}, cpq-image.info is missing\n"
			if [[ ${skip_prompt} == 'yes' ]]; then exit 1; fi
		fi
	else
			printf "skipping backup of a source site(${source_short_name})\n";
        fi;
else
        printf "Using an existing pullsite image, source's backup is not necessary\n"
		source_image_location=${source_site_image}
        printf "Using source image:${source_image_location}\n"
fi
echo ""
wait ${EXPPID}
if [[ ${destination_backup} == yes ]]; then 
	if [[ -f "${destination_image_location}/cpq-image.info" ]]; then 
		printf "\nback up ${destination_image_location} has been created successfully\n"
		ssh -t -t ${destination_site} "sudo mkdir /backup; sudo touch /backup/backup_created_on_${DATE}; sudo chmod 777 /backup/backup_created_on_${DATE}; echo ${destination_image_location} > /backup/backup_created_on_${DATE}"
	else
		printf "\nplease verify ${destination_image_location}, cpq-image.info is missing\n"
		if [[ ${skip_prompt} == 'yes' ]]; then exit 1; fi
	fi
fi
}

#skip_prompt_update
destination_remove_schema() {
if [[ ${skip_prompt} == 'yes' ]]; then
	yes | while true; do
		echo ""
		printf "Continue to delete ${destination_short_name}'s schema ${destination_schema_name}? (y / n)";
		read yn
		case $yn in
			[Yy]* ) printf "Selected Yes\n"
			break
			;;
			[Nn]* ) echo "aborting schema drop..." && return 1
			;;
			* ) echo "Please answer y (yes) or n (no)"
			;;
		esac
	done
else 
	while true; do
		echo ""
		printf "Continue to delete ${destination_short_name}'s schema ${destination_schema_name}? (y / n)";
		read yn
		case $yn in
			[Yy]* ) break
			;;
			[Nn]* ) echo "aborting schema drop..." && return 1
			;;
			* ) echo "Please answer y (yes) or n (no)"
			;;
		esac
	done
fi
# drop schema
echo "";
DROPRESULT='1'	# Non-zero means (re)try drop
while [ "$DROPRESULT" != '0' ]
	do
		printf "Dropping user ${destination_schema_name}...\n"
		#ssh -t -t $destination_dbhost_mapped "sudo su - oracle -c \"ORACLE_SID=${destination_dbsid_mapped} ; ~/oracle_scripts/dropuser.sh ${destination_schema_name}\""
		ssh -t -t $SSHOPTS $destination_dbhost_mapped "[[ -f /usr/local/bin/oraenv ]] && source /usr/local/bin/oraenv -s <<<\"${destination_dbsid_mapped}\"; sudo -u oracle /usr/local/orabin/dropUserSchema.sh ${destination_schema_name};"
		DROPRESULT="$?"
		if [ "$DROPRESULT" != '0' ]
		then
		echo -en "\nWARNING: Database could not be dropped.  This may be caused by stale connections.\n  Press any key to retry or Ctrl+C to abort."
	    read x
	  echo
	fi
done
db_drop_status=$?
if [ $db_drop_status -ne 0 ]; then
		printf "Please verify successful deletion of ${destination_schema_name}...\n";
		if [[ ${skip_prompt} == 'yes' ]]; then exit 1; fi
		echo "";
	else 
		printf "user ${destination_schema_name} dropped...\n";
		echo "";
fi
printf "Removed ${destination_short_name}'s schema ${destination_schema_name}";
echo "";
#finish
}

#skip_prompt_update
destination_remove_frontend() {
if [[ ${skip_prompt} == 'yes' ]]; then
	yes | while true; do
		echo ""
		printf "Continue to remove ${destination_short_name}'s front end? (y / n)";
		read yn
		case $yn in
			[Yy]* ) printf "Selected Yes\n" 
			break
			;;
			[Nn]* ) echo "aborting..." && return 1
			;;
			* ) echo "Please answer y (yes) or n (no)"
			;;
		esac
	done
else 
	while true; do
		printf "Continue to remove ${destination_short_name}'s front end? (y / n)";
		read yn
		case $yn in
			[Yy]* ) break
			;;
			[Nn]* ) echo "aborting..." && return 1
			;;
			* ) echo "Please answer y (yes) or n (no)"
			;;
		esac
	done
fi
echo ""
printf "starting general clean up for ${destination_short_name}\n"
#run clean up script "cleansite_new"
./cleansite -t ${destination_site};
frontend_clean_status=$?
if [ $frontend_clean_status -ne 0 ]; then
		printf "Please verify successful front end clean up for ${destination_schema_name}...\n";
		if [[ ${skip_prompt} == 'yes' ]]; then exit 1; fi
		echo "";
	else 
		printf "general clean up for ${destination_schema_name} is completed...\n";
		echo "";
fi
}

#skip_prompt_update
destination_deploy_message() {
echo "";
printf "Please verify the following details prior to deployment:\n";
echo "";
printf "source image:${source_image_location} \n";
printf "destination site name: ${destination_short_name}\n";
printf "TAS_ID: ${destination_tas_id}\n";
printf "Schema name: ${destination_schema_name}\n";
printf "encrypted db password: ${destination_schema_password}\n";
printf "decrypted db password: ${destination_schema_decrypted_password}\n";
printf "DB ip: ${destination_dbhost_mapped}\n";
printf "DB sid: ${destination_dbsid_mapped}\n";
echo "";
printf "Deploying with the following command:\n"
printf "bash deployimage --tassubid ${destination_tas_id} --companyname ${destination_short_name}  --cpqdbnode ${destination_dbhost_mapped} --passwordenc \'${destination_schema_password}\' --image ${source_image_location} --mapkey ${destination_schema_name} --target ${destination_site_eth1} --cpqdbuser ${destination_schema_name} --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname ${destination_registry_name} --oci legacy ${big_db_user} ${DPARTIAL} ${destination_script_start} ${destination_script_stop}\n"
if [[ ${skip_prompt} == 'yes' ]]; then
	yes | while true; do
		echo ""
		printf "Please confirm if you would like to proceed with deployment? (y / n)";
		read yn
		case $yn in
			[Yy]* ) printf "Selected Yes\n"
			break
			;;
			[Nn]* ) echo "aborting..." && exit 1
			;;
			* ) echo "Please answer y (yes) or n (no)"
			;;
		esac
	done
else
	while true; do
		echo ""
		printf "Please confirm if you would like to proceed with deployment? (y / n)";
		read yn
		case $yn in
			[Yy]* ) break
			;;
			[Nn]* ) echo "aborting..." && exit 1
			;;
			* ) echo "Please answer y (yes) or n (no)"
			;;
		esac
	done
fi
echo "";
}

destination_deploy() {
if [[ ${using_param_file} == yes ]]
	then
		echo ""
		printf "starting deployment for ${destination_short_name} with parameter file...\n";
        echo ""
        bash deployimage --tassubid ${destination_tas_id} --companyname ${destination_short_name}  --cpqdbnode ${destination_dbhost_mapped} --passwordenc \'${destination_schema_password}\' --image ${source_image_location} --mapkey ${destination_schema_name} --target ${destination_site_eth1} --cpqdbuser ${destination_schema_name} --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname ${destination_registry_name} --oci legacy ${big_db_user} ${DPARTIAL} ${destination_script_start} ${destination_script_stop}
		refresh_status_param=$?
		if [ $refresh_status_param -ne 0 ]; then
			printf "Please verify successful completion deployment...\n";
			printf "Re-run the following command if necessary:\n";
			printf "bash deployimage --tassubid ${destination_tas_id} --companyname ${destination_short_name}  --cpqdbnode ${destination_dbhost_mapped} --passwordenc \'${destination_schema_password}\' --image ${source_image_location} --mapkey ${destination_schema_name} --target ${destination_site_eth1} --cpqdbuser ${destination_schema_name} --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname ${destination_registry_name} --oci legacy ${big_db_user} ${DPARTIAL} ${destination_script_start} ${destination_script_stop}\n";
			exit 1;
		fi
else
	    echo ""
        printf "starting deployment for ${destination_short_name}...\n";
        echo ""
		bash deployimage --tassubid ${destination_tas_id} --companyname ${destination_short_name}  --cpqdbnode ${destination_dbhost_mapped} --passwordenc ${destination_schema_password} --image ${source_image_location} --mapkey ${destination_schema_name} --target ${destination_site_eth1} --cpqdbuser ${destination_schema_name}  --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname	${destination_registry_name} --oci legacy ${big_db_user} ${DPARTIAL} ${destination_script_start} ${destination_script_stop}
		refresh_status_param=$?
		if [ $refresh_status_param -ne 0 ]; then
			printf "Please verify successful completion deployment...\n";
			printf "Re-run the following command if necessary:\n";
			printf "bash deployimage --tassubid ${destination_tas_id} --companyname ${destination_short_name}  --cpqdbnode ${destination_dbhost_mapped} --passwordenc ${destination_schema_password} --image ${source_image_location} --mapkey ${destination_schema_name} --target ${destination_site_eth1} --cpqdbuser ${destination_schema_name}  --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname	${destination_registry_name} --oci legacy ${big_db_user} ${DPARTIAL} ${destination_script_start} ${destination_script_stop}\n";
			exit 1;
		fi;
fi
}

restore_sflCertificate_cert () {
ssh -t -t ${destination_site} "
sudo cp -rf $destination_sflCertificate_location/* /bmfsweb/${destination_short_name}/;
sudo chown bm:ecom /bmfsweb/${destination_short_name}/sflCertificate.*;
sudo chmod 444 /bmfsweb/${destination_short_name}/sflCertificate.*;
"
echo ""
printf "Restored sflCertificates\n"
echo ""
}

restore_java_properties_folder () {
echo "":
printf "restoring original java_properties folder...\n"
ssh -t -t ${destination_site} "
	if [[ ! -d "/var/tmp/propman/bigmac/conf/java_security/" ]]; then
	printf "Directory /var/tmp/propman/bigmac/conf/java_security/ does not exist on target ${destination_site}\n";
	return 1;
	fi"
ssh -t -t ${destination_site} "
	sudo rm -rf /bigmac/conf/java_security; 
	sudo cp -rf /var/tmp/propman/bigmac/conf/java_security /bigmac/conf/;
	sudo chown -R bm:ecom /bigmac/conf/java_security/;
	"
echo ""
printf "restored original java_properties folder...\n"
echo ""
printf "restoring java security node1.properties' values...\n"
echo ""
ssh -t -t ${destination_site} "
sudo sed -i \"s?-Djavax.net.ssl.keyStorePassword=[^ ]*\s?-Djavax.net.ssl.keyStorePassword=${destination_keyStorePassword} ?g\" /bigmac/conf/node1.properties;
sudo sed -i \"s?-Djavax.net.ssl.keyStore=\/bigmac\/conf\/java_security\/[^ ]*\s?-Djavax.net.ssl.keyStore=${destination_keyStore} ?g\" /bigmac/conf/node1.properties;
sudo sed -i \"s?-Djavax.net.ssl.keyStoreType=[^ ]*\s?-Djavax.net.ssl.keyStoreType=${destination_keyStoreType} ?g\" /bigmac/conf/node1.properties;
sudo -i /bigmac/bin/cpqctl restart;
"
echo ""
printf "Restored java security node1.properties' values...\n"
echo ""
}

after_refresh () {
echo "";
printf "applying jdbc fix ${destination_short_name}...\n"
if [[ ! -f "fix_jdbcScan.sh" ]]; then
	echo ""; printf "fix_jdbcScan.sh is missing\n"
	return 1
fi
bash fix_jdbcScan.sh $destination_site
}

move_destination_backup () {
printf "Moving destination backup ${destination_image_location} to ${destination_site} backup folder...\n"
ssh -t -t ${destination_site} "
	sudo mkdir -p /backup;
	sudo mv -f ${destination_image_location} /backup;
"
move_destination_backup_status=$?
if [ $move_destination_backup_status -ne 0 ]; then
		printf "Please verify backup location ${destination_image_location} and move it manually...\n";
		echo "";
	else 
		printf "Move completed\n";
		echo "";
fi
}

remove_source_backup () {
if [[ ! -d ${source_image_location} ]]; then "backup ${source_image_location} does not exist\n" && return 1; fi
while true; do
	echo ""
	printf "(Mandatory) Please confirm if you would like to remove source backup now - ${source_image_location}? (y / n)";
	read yn
	case $yn in
		[Yy]* ) rm -rf ${source_image_location}; break;
		;;
		[Nn]* ) echo "aborting..." && return 1
		;;
		* ) echo "Please answer y (yes) or n (no)"
		;;
	esac
done
source_image_location_status=$?
if [ $source_image_location_status -ne 0 ]; then
		printf "Please verify backup location ${source_image_location} and move it manually...\n";
		echo "";
	else 
		printf "Source backup removed\n";
		echo "";
fi
}

end_message () {
echo ""
printf "Refresh of ${destination_short_name} is completed\n"
}


main() {
set_arguments "${@}"
logging
get_source_variables
set_source_variables
if [[ ${using_param_file} == 'no' ]]; then get_destination_variables; fi;
set_destination_variables
check_diskspace_on_source_and_destination
destination_schema_check
destination_propman_setup
get_destination_java_security
get_sflCertificate
clean_backup_destination_site
show_destination_variables
if [[ ${skip_prompt} == 'yes' ]]; then timeout_skip_prompt; fi
if [[ ${skip_prompt} == 'no' ]]; then upgrade_prompt; fi
if [[ ${skip_prompt} == 'yes' ]]; then destination_start_rngd; fi
oem_blackout
complete_backups
if [[ ${remove_destination_frontend} == 'yes' ]]; then destination_remove_frontend; fi
if [[ ${remove_destination_schema} == 'yes' ]]; then destination_remove_schema; fi
destination_deploy_message
destination_deploy
if [[ ${restore_sflCertificate} == 'yes' ]]; then restore_sflCertificate_cert; fi
if [[ ${restore_source_java_properties} == 'yes' ]]; then restore_java_properties_folder; fi
after_refresh
move_destination_backup
remove_source_backup
end_message
}

main "${@}";

exit 0;
