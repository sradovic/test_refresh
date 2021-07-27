#!/bin/bash

DEST_BCK="yes";
SOURCE_BCK="yes";
BIG_USER="";
NO_PARALL="8";
PPARTIAL="";
DPARTIAL="";
Xms="9g";
XX="3g"
Start="";
Stop="";
username="$(whoami)";
BCK_LOC="/fsnhome/${username}/refresh_backup";
DEF_TEMPLATE="propman_default"
USING_PARAM_FILE="no";
using_image='no'
BATCH='no';
declare -r g_dir="$(pwd)";
g_components="${g_dir}/components";
g_encrypt_dir="${g_components}/encrypt/1.0.0";
g_rcu="${g_components}/rcu";
g_rcu_wls="${g_rcu}/18.3.0/v3";
RCU_HOME="${g_rcu_wls}/oracle_common";
g_target_user_oracle='oracle';
oracle_scripts="/home/oracle/oracle_scripts"
g_db_orabin="/usr/local/orabin"
upgrademaps="components/maps"

error(){
  MSG="$1"
  [ -n "$MSG" ] &&  echo "$MSG"
  [ -z "$MSG" ] &&  MSG='Generic failure'
  exit 1
}

[ -z "$STY" ] && error "ERROR: Must run using screen"

logging (){
DATE1=`date '+%m%d%y.%H%M%S'`
mkdir -m 777 logs 2>/dev/null
exec 2>logs/refresh/refresh_${DEST_SITE}$DATE1.log
set -x
}

function usage()
{
  echo "Command Syntax: "
  echo
  echo "    $0 -S <source fqdn> -D <dest fqdn> -I <path_to_image-skip source backup> -B <path_to_bck_location> -N <skip destination backup> -P <location of PARAM. FILE>"
  echo
  echo "      where: "
  echo "             -S <source fqdn> "
  echo "             -D <dest fqdn> "
  echo "             -I <image>         path_to_image-skip source backup"
  echo "             -B <location>      path_to_bck_location"
  echo "             -N               skip destination backup"
  echo "             -P location      location of PARAM. FILE"
  echo "             -b               source is big user and needs to be imported as big user to destination"
  echo "             -l <no.>         no of parrallel for pullsite"
  echo "             -x <step to start deployimage> "
  echo "             -y <step to stop deployimage> "
  echo "             -o        pull front-end end deploy front-end (-o fs )" 
  echo "             -T <propman templete name>  "
  echo
  echo "      example: "
  echo '             refresh.sh  -S cpq-s41-001.web.dem.ch3.bmi  -D cpq-m12-002.web.dem.ch3.bmi'
  echo
  exit
}

function get_deploy_parametars ()
     {
      sub_id=$(grep ^sub_id ${PARAM_FILE} | cut -f2 -d=);
      dec_db_passwd=$(grep ^db_passwd ${PARAM_FILE} | cut -f2 -d=);
      passwordenc=$(java -jar encrypt.jar AES encrypt ${dec_db_passwd});
      dst_db_user=$(grep ^cpqdbuser ${PARAM_FILE} | cut -f2 -d=);
      cpqdbuser=$(grep ^cpqdbuser ${PARAM_FILE} | cut -f2 -d=);
      mapkey=$(grep ^mapkey ${PARAM_FILE} | cut -f2 -d=);
      dbhost_mapped=$(grep ^cpqdbnode ${PARAM_FILE} | cut -f2 -d=);
      cpqdbnode=$(grep ^cpqdbnode ${PARAM_FILE} | cut -f2 -d=);
      target=$(grep ^target ${PARAM_FILE} | cut -f2 -d=);
      companyname=$(grep ^companyname ${PARAM_FILE} | cut -f2 -d=);
      image=$(grep ^image ${PARAM_FILE} | cut -f2 -d=);
      dbsid_mapped=$(grep -v ^# ${upgrademaps}/site.map | grep -i "^\<${mapkey}\>" | head -1 | awk '{print $5}') || return 1;
}


dest_site_parameters () {
DEST_SSITENAME=$(ssh -t -t ${DEST_SITE} "hostname -s" | tr -d '\r' );
dst_db_user=`ssh $SSHOPTS ${DEST_SITE} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
}

Start_Rngd () {
ssh $SSHOPTS -t -t ${DEST_SITE} "
                        sudo -i su - --session-command '
                        systemctl start rngd;
                        ';
                ";
}

# Drop CPQ schema
Drop_CPQ_schemas () {
ssh $SSHOPTS -t -t ${dbhost_mapped} "
                        echo '';
                        [[ -f ~/.profile ]] && source ~/.profile;
                        [[ -f /usr/local/bin/oraenv ]] && source /usr/local/bin/oraenv -s <<<\"${dbsid_mapped}\";
                        sudo -u ${g_target_user_oracle} ${g_db_orabin}/dropUserSchema.sh ${dst_db_user};
                        exit 0;
                        " || echo "Failed to drop  CPQ DB user" "ERROR-CPQ-DEPLOY-8";
}

source_site_parameters () {
SOURCE_SSITENAME=$(ssh -t -t ${SOURCE_SITE} "hostname -s" | tr -d '\r' );
souce_db_user=`ssh $SSHOPTS ${SOURCE_SITE} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
}


dest_backup (){
bash pullsite --oci legacy -i ${DEST_IMAGE} -k  ${dst_db_user}  -t ${DEST_SITE} -D /bmsrv99${DEST_DC}${DEST_TY}/oracle/backup/datapump_ondemand -l ${NO_PARALL} -v -M prod ${PPARTIAL} 2>&1 &
EXPPID="$!"
echo " PID: $EXPPID"
export $EXPPID
}

source_backup (){
bash pullsite --oci legacy -i ${SOURCE_IMAGE} -k  ${souce_db_user}  -t ${SOURCE_SITE} -D /bmsrv99${SOURCE_DC}${SOURCE_TY}/oracle/backup/datapump_ondemand -l ${NO_PARALL} -v -M prod ${PPARTIAL}
}

show_Arguments_18D  (){

SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"

dst_db_user=`ssh $SSHOPTS ${DEST_SITE} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
dst_db_passwd=`ssh $SSHOPTS ${DEST_SITE} "grep ^db_pass /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
mdssid=`ssh $SSHOPTS ${SITE} "grep ^mds_db_id /bmfs/cpqShared/conf/mdsdatabase.properties | cut -f2 -d="`
deployimage_param="./logs/deploy_param_file/${DEST_SSITENAME}_deployimage_${DATE}_param.txt";
dbmap_key=${dst_db_user}
dbhost_mapped=$(grep -v ^# ${upgrademaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $2}') || return 1;
dbsid_mapped=$(grep -v ^# ${upgrademaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $5}') || return 1;
TASID=`ssh $SSHOPTS ${DEST_SITE} "grep ^tas /bmfs/cpqShared/conf/tas.properties | cut -f2 -d="`
IPETH1=$(ssh ${DEST_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
g_db_cpquserpass=$(java -jar ${g_encrypt_dir}/encrypt.jar AES decrypt ${dst_db_passwd})

cat <<-_DEPLOY_IMAGE_PARAM_18D > "${deployimage_param}"
				sub_id=${TASID}
				db_passwd=${g_db_cpquserpass}
				image=${BCK_LOC}/${SHORT_SITENAME}-${DATE}
				cpqdbnode=${dbhost_mapped}
				cpqdbuser=${dst_db_user}
				mapkey=${dst_db_user}
				target=${IPETH1}
				mdsdbid=${mdssid}
				companyname=${SHORT_SITENAME}
_DEPLOY_IMAGE_PARAM_18D
}

Deploy_to_Target_18_D (){

bash deployimage --oci legacy --tassubid "${TASID}" --companyname "${SHORT_SITENAME}"  --cpqdbnode "${dbhost_mapped}" --passwordenc "${dst_db_passwd}" --image "${SOURCE_IMAGE}" --mapkey "${dst_db_user}" --target "${IPETH1}" --cpqdbuser "${dst_db_user}"  --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname "${REGISTRY_NAME}" ${BIG_USER} ${DPARTIAL} ${Start} ${Stop}
}


Deploy_to_Target_18_D_using_par_file (){

bash deployimage --oci legacy --tassubid "${sub_id}" --companyname "${companyname}"  --cpqdbnode "${cpqdbnode}" --passwordenc "${passwordenc}" --image "${image}" --mapkey "${mapkey}" --target "${target}" --cpqdbuser "${cpqdbuser}"  --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname "${REGISTRY_NAME}" ${BIG_USER} ${DPARTIAL} ${Start} ${Stop}
}

#======================================================end of functions==========================================================



DATE=`date '+%m%d%y'`

if [ $# -eq 0 ];
 then
  usage;
  exit 0;
fi

while getopts ":S:D:I:B:P:l:x:y:T:Nbo" x ; do
  case "${x}" in
    D)
      DEST_SITE=${OPTARG};
      ;;
    S)
      SOURCE_SITE=${OPTARG};
      source_site_exist='yes'
      ;;
    I)
      SOURCE_IMAGE=${OPTARG};
      SOURCE_BCK="no";
      echo "sorce image ${SOURCE_IMAGE}"
      using_image='yes'
      ;;
    l)
      NO_PARALL=${OPTARG};
      ;;
    x)
      Start=" -s ${OPTARG}";
      ;;
    y)
      Stop=" --stopbefore ${OPTARG}";
      ;;
    B)
      BCK_LOC=${OPTARG};
      ;;
    T)
      DEF_TEMPLATE=${OPTARG};
      ;;
    o)
      PPARTIAL="-o fs";
      DPARTIAL="--deploytype fs -s 5";
      ;;
    b)
      BIG_USER="-b";
      ;;
    N)
      DEST_BCK="no"
      ;;
    P)
      PARAM_FILE=${OPTARG};
      USING_PARAM_FILE="yes"
      DEST_BCK="no";
      SOURCE_BCK="no";
      ;;
    *)
      usage;
      ;;
    ?)
      usage;
     ;;
  esac
done
shift $((OPTIND -1))

logging

SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
   DIPETH1=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${DEST_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
   DIPETH0=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${DEST_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth0 | cut -f2 -d=");
       ssh-keygen -R ${DEST_SITE};
       ssh-keygen -R ${DIPETH0};
       ssh-keygen -R ${DIPETH1};
       ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${DEST_SITE} "exit";
       ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${DIPETH1} "exit" ;

   SIPETH1=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SOURCE_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
   SIPETH0=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SOURCE_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth0 | cut -f2 -d=");
       ssh-keygen -R ${SOURCE_SITE};
       ssh-keygen -R ${SIPETH0};
       ssh-keygen -R ${SIPETH1};
       ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SOURCE_SITE} "exit";
       ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SIPETH1} "exit" ;
sleep 2;

DATA_CENTER=`echo ${DEST_SITE} | cut -d. -f4`;
SSITENAME="$(echo ${DEST_SITE}| cut -d '.' -f1)";
DEST_SITE_IP=$(ssh ${DEST_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
SHORT_SITENAME=$(ssh -t -t ${DEST_SITE_IP} "hostname -s" | tr -d '\r' );
FULL_SITENAME=$(ssh -t -t ${DEST_SITE_IP} "hostname"  | tr -d '\r');
if [ "${SHORT_SITENAME}" != "${SSITENAME}" ]; then
      echo "Something is wrong!!! short DNS hostname does not match actual short hostname";
      exit 1;
fi
if [ "${DEST_SITE}" != "${FULL_SITENAME}" ]; then
      echo "Something is wrong!!! FQDN  hostname does not match actual hostname";
      exit 1;
fi

if [[ ${DATA_CENTER} == 'dc3' ]]; then
                REGISTRY_NAME='provadmin-dc3.app.mgt.dc3.bmi';
                DEST_DC="7"
elif [[ ${DATA_CENTER} == 'ch3' ]]; then
                REGISTRY_NAME='provadmin.app.mgt.ch3.bmi';
                DEST_DC="8"
elif  [[ ${DATA_CENTER} == 'com' ]]; then
                REGISTRY_NAME='provadmin-am3.nldc1.oraclecloud.com:5043';
                DEST_DC="9"
else
     echo "Wrong data center ID!!!!"
     exit 1;
fi

dst_db_user=`ssh $SSHOPTS ${DEST_SITE} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
dbmap_key=${dst_db_user}
dbsid_mapped=$(grep -v ^# ${upgrademaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $5}') || return 1;
DEST_TYPE=$(echo ${dbsid_mapped:2:3})

SOURCE_DATA_CENTER=`echo ${SOURCE_SITE} | cut -d. -f4`;
SOURCE_SSITENAME="$(echo ${SOURCE_SITE}| cut -d '.' -f1)";
SOURCE_SITE_IP=$(ssh ${SOURCE_SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
SOURCE_SHORT_SITENAME=$(ssh -t -t ${SOURCE_SITE_IP} "hostname -s" | tr -d '\r' );
SOURCE_FULL_SITENAME=$(ssh -t -t ${SOURCE_SITE_IP} "hostname"  | tr -d '\r');
if [ "${SOURCE_SHORT_SITENAME}" != "${SOURCE_SSITENAME}" ]; then
      echo "Something is wrong!!! short DNS hostname does not match actual short hostname";
      exit 1;
fi
if [ "${SOURCE_SITE}" != "${SOURCE_FULL_SITENAME}" ]; then
      echo "Something is wrong!!! FQDN  hostname does not match actual hostname";
      exit 1;
fi

if [[ ${SOURCE_DATA_CENTER} == 'dc3' ]]; then
                REGISTRY_NAME='provadmin-dc3.app.mgt.dc3.bmi';
                SOURCE_DC="7"
elif [[ ${SOURCE_DATA_CENTER} == 'ch3' ]]; then
                REGISTRY_NAME='provadmin.app.mgt.ch3.bmi';
                SOURCE_DC="8"
elif  [[ ${SOURCE_DATA_CENTER} == 'com' ]]; then
                REGISTRY_NAME='provadmin-am3.nldc1.oraclecloud.com:5043';
                SOURCE_DC="9"
else
     echo "Wrong data center ID!!!!"
     exit 1;
fi

source_db_user=`ssh $SSHOPTS ${SOURCE_SITE} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
source_dbmap_key=${source_db_user}
source_dbsid_mapped=$(grep -v ^# ${upgrademaps}/site.map | grep -i "^\<${source_dbmap_key}\>" | head -1 | awk '{print $5}') || return 1;
SOURCE_TYPE=$(echo ${source_dbsid_mapped:2:3})

case "${DEST_TYPE}" in
        PRD) DEST_TY="6"
		     echo "Destination is prod!!!"
           ;;
        TST) DEST_TY="7"
		     echo "Destination is test!!!"
           ;;
        DEM) DEST_TY="8"
		     echo "Destination is demo!!!"
                     Xms="5g";
                     XX="1g"
            ;;
        *) echo "  : Not processed"
           ;;
esac

case "${SOURCE_TYPE}" in
        PRD) SOURCE_TY="6"
		     echo "Source is prod!!!"
           ;;
        TST) SOURCE_TY="7"
		     echo "Source is test!!!"
           ;;
        DEM) SOURCE_TY="8"
		     echo "Source is demo!!!"
            ;;
        *) echo "  : Not processed"
           ;;
esac 

#============================destination site==================================================================
ssh $SSHOPTS -t -t ${DEST_SITE} "

                        if [ -d "/bigmac" ]
                        then
                                echo "Directory /bigmac exists.";
                                exit 100;
                        else
                                echo "Directory /bigmac does not exists.";
                                exit 101;
                        fi;
                "
site_is_clean=$?

case ${site_is_clean} in
    101 )
         echo "site is clean";
          if [[ ${USING_PARAM_FILE} == 'no' ]] 
            then
              echo "You have to provide parameter -P </path/to/parameter/file> to deploy on clean vm"
              exit 1 ;
          fi;
;;
    100 )
         echo "site has /bigmac dir";
;;
esac;

main (){

if [[ ${USING_PARAM_FILE} == yes ]]
        then
                printf "we are using parametar file \n";
                get_deploy_parametars;
                TYPEOFDEPLOYMENT=1
        else
                printf "we are not using parametar file \n";
                dest_site_parameters
                show_Arguments_18D;
                TYPEOFDEPLOYMENT=2
fi;
#=============================destination backup=======================================================

if [[ ${site_is_clean} -eq '100' ]]
 then
        #dest_site_parameters
        sleep 2
        if [[ ${DEST_BCK} == yes ]]
        then
             DEST_IMAGE="${BCK_LOC}/${DEST_SSITENAME}-${DATE}"
                if [ -d "${DEST_IMAGE}" ]
                  then
                    echo "Warninig: Directory ${DEST_IMAGE}  exists! (remove or rename).";
                    exit 1;
                fi;

             mkdir -p ${DEST_IMAGE}
             chmod 777 ${DEST_IMAGE}
             printf "front end pullsite buckup of desination site \n";
             dest_backup ;
        else
             printf "skipinng backup of desination site \n";
        fi;
fi


#==============================source backup=========================================================
if [[ ${using_image} == 'no' ]] 
then
	source_site_parameters;
        if [[ ${SOURCE_BCK} == yes ]]
        then
                echo ${DATE}
                SOURCE_IMAGE="${BCK_LOC}/${SOURCE_SSITENAME}-${DATE}"
                if [ -d "${SOURCE_IMAGE}" ]
                  then
                    echo "Warninig: Directory ${SOURCE_IMAGE}  exists! (remove or rename).";
                    exit 1;
                fi;

                mkdir -p ${SOURCE_IMAGE}
                chmod 777 ${SOURCE_IMAGE}
                printf "pullsite backup of source site \n";
                source_backup;
                echo " Done."
        else
                printf "skipinng backup of source site \n";
        fi;
else
        echo " Using existing pullsite image  - no source pullsite nessessery"
fi
wait $EXPPID

#===============================================================================================
ssh $SSHOPTS -t -t ${DEST_SITE} "
                        
                        if [ -d "/var/tmp/propman" ] 
			then
    				echo "Warninig: Directory /var/tmp/propman exists.";
                                exit 254;    
			else
    				echo "Directory /var/tmp/propman does not exists.";
                                exit 255;
			fi;
                "
proman_dir="$?"

if [ ${proman_dir} -eq "255" ]
                        then
                                echo "Directory /var/tmp/propman DOES NOT exists and will be created";
                                rsync -avzh ./propman_templates/${DEF_TEMPLATE}/ ${DEST_SITE}:/var/tmp/propman/ 
                                echo "Propman template used is :./propman_templates/${DEF_TEMPLATE}"
                                bash propman replace ${DEST_SITE}
                        else
                                printf "Do yo want to remove existing /var/tmp/propman and create new? : (y/n) \n";
                                        read x ;
                        		if [[ ${x} == 'y' ]]
                                		then
                                        		echo "Removing existing /var/tmp/propman";
                                        		bash propman delete ${DEST_SITE}; 
                                                        sleep 2
                                                        rsync -avzh ./propman_templates/${DEF_TEMPLATE}/ ${DEST_SITE}:/var/tmp/propman/;
                                                        echo "Propman template used is :./propman_templates/${DEF_TEMPLATE}"
                                                        bash propman replace ${DEST_SITE};
                        		fi;

fi;
 

#==============================Cleaning destination front end============================================================
printf "Do yo want to Stop_and_Clean_front_end on $DEST_SITE: (y/n) \n";
                        read x ;
                        if [[ ${x} == 'y' ]]
                                then
                                        ./cleansite_new -t $DEST_SITE
                        fi
                        if [[ ${PPARTIAL} == '' ]]; then      
                          printf "Do yo want to Drop CPQ schema ${dst_db_user}: (y/n) \n";
                                        read x ;
                          if [[ ${x} == 'y' ]]
                                then
                                        Drop_CPQ_schemas
                          fi
                        fi 

#==============================================================================================================================

case ${TYPEOFDEPLOYMENT} in
    1 )
       echo " "; 
       echo " Deployment using parametar file";
                        if [[ $BATCH == no ]]
                          echo ""
                          echo "bash deployimage --oci legacy --tassubid "${sub_id}" --companyname "${companyname}"  --cpqdbnode "${cpqdbnode}" --passwordenc "${passwordenc}" --image "${image}" --mapkey "${mapkey}" --target "${target}" --cpqdbuser "${cpqdbuser}"  --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname "${REGISTRY_NAME}" ${BIG_USER} ${DPARTIAL} ${Start} ${Stop}" 
                          echo "" 
                                then
                                     printf "Do yo want to deploy image: (y/n) \n";
                                read x ;
                        fi;
                        if [[ ${x} == 'y' ]]
                                then
                                      Start_Rngd
                                      Deploy_to_Target_18_D_using_par_file
                        fi;
;;

    2 )
       echo " ";
       echo " Deployment using info form existing site";
                        if [[ $BATCH == no ]]
                                then
                                 echo ""
                                 echo "bash deployimage --oci legacy --tassubid "${TASID}" --companyname "${SHORT_SITENAME}"  --cpqdbnode "${dbhost_mapped}" --passwordenc "${dst_db_passwd}" --image "${SOURCE_IMAGE}" --mapkey "${dst_db_user}" --target "${IPETH1}" --cpqdbuser "${dst_db_user}"  --jvmmempool ${Xms} --gcnewsize ${XX}  --mode prod --propman restore --cpqnode node1 --registryname "${REGISTRY_NAME}" ${BIG_USER} ${DPARTIAL} ${Start} ${Stop}"
                                 echo ""
                                     printf "Do yo want to deploy image: (y/n) \n";
                                read x ;
                        fi;
                        if [[ ${x} == 'y' ]]
                                then
                                        Start_Rngd
                                        Deploy_to_Target_18_D
                        fi;
;;
esac;
}

main "${@}";
exit 0;

