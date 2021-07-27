#!/bin/bash
DATE=`date '+%m%d%y'`
l=8
options=''
F=''
b=''
o=''
path="yes"
dpath="yes"
sitemaps="./components/maps/"
g_encrypt_dir="./components/encrypt/1.0.0/"
username="$(whoami)";
SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
error(){
  MSG="$1"
  [ -n "$MSG" ] &&  echo "$MSG"
  [ -z "$MSG" ] &&  MSG='Generic failure'
  exit 1
}

[ -z "$STY" ] && error "ERROR: Must run using screen"

function usage()
{
  echo "Command Syntax: "
  echo
  echo "    $0  -t <dest > -i <path_to_image backup> -d -F <truncation file> -l <no of parallel> -b -d"
  echo
  echo "      where: "
  echo "             -t <dest fqdn> "
  echo "             -i <image>         path_to_image backup "
  echo "             -d               leave dpdmp files in thr datapump dir on db server"
  echo "             -F <truncation file>      location of truncation. FILE"
  echo "             -b               bring dpdmp to -i directory"
  echo "             -l <no.>         no of parrallel for pullsite"
  echo "             -o <opt.>       pull front-end/db (-o fs/db )"
  echo
  echo "      example: "
  echo '             refresh.sh  -S cpq-s41-001.web.dem.ch3.bmi  -D cpq-m12-002.web.dem.ch3.bmi'
  echo
  exit
}

pullsite_param  (){
SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
deployimage_param="./logs/pullsite_param_file/${SITE}${DATE}_param.txt";

Image=${i};
ddst_db_user=`ssh $SSHOPTS ${SITE} "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
dst_db_passwd=`ssh $SSHOPTS ${SITE} "grep ^db_pass /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
#mdssid=`ssh $SSHOPTS ${SITE} "grep ^mds_db_id /bmfs/cpqShared/conf/mdsdatabase.properties | cut -f2 -d="`
dbmap_key=${dst_db_user}
dbhost_mapped=$(grep -v ^# ${sitemaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $2}') || return 1;
dbsid_mapped=$(grep -v ^# ${sitemaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $5}') || return 1;
BIGMAC_HOME="/bigmac/"
BIGMAC_CONF="${BIGMAC_HOME}conf/"
TASID=`ssh $SSHOPTS ${SITE} "grep ^tas /bmfs/cpqShared/conf/tas.properties | cut -f2 -d="`
IPETH1=$(ssh ${SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
g_db_cpquserpass=$(java -jar ${g_encrypt_dir}/encrypt.jar AES decrypt ${dst_db_passwd})
DATE=`date '+%m%d%y'`

cat <<-_PULLSITE_IMAGE_PARAM > "${deployimage_param}"
	sub_id=${TASID}
	db_passwd=${g_db_cpquserpass}
	image=${Image}
	cpqdbnode=${dbhost_mapped}
	cpqdbuser=${ddst_db_user}
	mapkey=${ddst_db_user}
	target=${IPETH1}
	companyname=${SSITENAME}
_PULLSITE_IMAGE_PARAM
}


if [ $# -eq 0 ];
 then
  usage;
  exit 0;
fi

while getopts ":t:l:F:o:i:bd" x ; do
  case "${x}" in
    l)
      l=${OPTARG};
      ;;
    d)
      dpath="no";
      ;;
    F)
      F="-F ${OPTARG}";
      ;;
    i)
      image=${OPTARG};
      path="no";
      ;;
    b)
      b="-b"
      ;;
    o)
      o="-o ${OPTARG} "
      ;;
    t)
      SITE=${OPTARG};      
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

SSHOPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
   DIPETH1=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth1 | cut -f2 -d=");
   DIPETH0=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SITE} "grep ^IP /etc/sysconfig/network-scripts/ifcfg-eth0 | cut -f2 -d=");
       ssh-keygen -R ${SITE};
       ssh-keygen -R ${DIPETH0};
       ssh-keygen -R ${DIPETH1};
       ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${SITE} "exit";
       ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no ${DIPETH1} "exit" ;

SSITENAME=$(ssh -t -t  $SSHOPTS $SITE "hostname -s" | tr -d '\r' );
dst_db_user=`ssh $SSHOPTS $SITE "grep ^db_user /bmfs/cpqShared/conf/database.properties | cut -f2 -d="`
FULL_SITENAME=$(ssh -t -t $SSHOPTS $SITE "hostname"  | tr -d '\r');
DATA_CENTER=`echo ${FULL_SITENAME} | cut -d. -f4`;
dbmap_key=${dst_db_user}
dbhost_mapped=$(grep -v ^# ${sitemaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $2}') || return 1;
dbsid_mapped=$(grep -v ^# ${sitemaps}/site.map | grep -i "^\<${dbmap_key}\>" | head -1 | awk '{print $5}') || return 1;
D_TYPE=$(echo ${dbsid_mapped:2:3})

if [[ ${DATA_CENTER} == 'dc3' ]]; then
                DEST_DC="7"
elif [[ ${DATA_CENTER} == 'ch3' ]]; then
                DEST_DC="8"
elif  [[ ${DATA_CENTER} == 'com' ]]; then
                DEST_DC="9"
else
     echo "Wrong data center ID!!!!"
     exit 1;
fi


case "${D_TYPE}" in
        PRD) TYPE="6"
                     echo "Source is prod!!!"
           ;;
        TST) TYPE="7"
                     echo "Source is test!!!"
           ;;
        DEM) TYPE="8"
                     echo "Source is demo!!!"
            ;;
esac


if [[ $path == "yes" ]] ;then
  i="/fsnhome/${username}/pullsite/${SSITENAME}-${DATE}"
else
  i=$(echo "$image/${SSITENAME}-${DATE}")
fi

if [[ $dpath == "yes" ]] ;then
 D="/public/${SSITENAME}-${DATE}"
else
 D="/bmsrv99${DEST_DC}${TYPE}/oracle/backup/datapump_ondemand"
fi

if [ -d "${i}" ]
                  then
                    echo "Warninig: Directory ${i}  exists! (remove or rename).";
                    exit 1;
                fi;

ssh $SSHOPTS -t -t ${SITE} "

                        if [ -d "/backup" ]
                        then
                                echo "Warninig: Directory /backup exists.";
                                exit 254;
                        else
                                echo "Directory /backup does not exists.";
                                exit 255;
                        fi;
                "
backup_dir="$?"

if [ ${backup_dir} -eq "254" ]
  then
    ssh $SSHOPTS -t -t ${SITE} "
      cd /backup ; sudo ln -s $i ${SSITENAME}_backup_${DATE} ;
   "
  else
   ssh $SSHOPTS -t -t ${SITE} "
      sudo mkdir /backup ; cd /backup  ; sudo ln -s $i ${SSITENAME}_backup_${DATE} ;
  "
fi
pullsite_param
#==================================PULLSITE=================================================================
echo "pullsite --oci legacy -i $i -k  ${dst_db_user} -t ${SITE} -D $D -l $l -v -M prod $b $F $o"
bash pullsite --oci legacy -i $i -k ${dst_db_user} -t ${SITE} -D $D -l $l -v -M prod $b $F $o

#=============================================================================================================
