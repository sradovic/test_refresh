#!/bin/bash
#
# chromeFixRestart.sh -
#
#	Script to go on sites and fix the web.xml and httpd.conf files to deal with SameSite attributes.
#	This version also restarts the cpqServer app and OHS processes
#
# Version 1 - Les LaPhilliph 01/15/2020
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
sshOpts='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
if [ $# -lt 1 ]; then
  echo "Site name required"
  exit
else
  hostName=$(ssh ${sshOpts} $1 hostname)
  if [ "$hostName" == '' ]; then
    echo "Site name supplied is invalid"
    exit
  fi
fi

ts=$(date +%Y%m%d%H%M%S)

echo "Performing chrome fix on $hostName ...."
activeIp=$(ssh ${sshOpts} -t -t $hostName "stty -onlcr; sudo /bigmac/container-setup/history.sh -i ACTIVE " 2>/dev/null )
#echo "activeIp: >$activeIp<"
#exit
ssh ${sshOpts} -t -t $hostName " stty -onlcr; sudo ssh $activeIp 'cat /bigmac/cpq/bigmachines/WEB-INF/web.xml'"  2>/dev/null > $DIR/tracking/chrome-$hostName-web.xml-$ts

if [ $( grep -c "SameSite=" $DIR/tracking/chrome-$hostName-web.xml-$ts ) -eq 0 ]; then
  sudo rm -f $DIR/tracking/chrome-$hostName-web.xml.new
  cat $DIR/tracking/chrome-$hostName-web.xml-$ts | awk '
BEGIN	{
		f = 0;
	}
	{
		if (f == 0) {
			if (index($0,"crossDomainSessionSecurity") > 0){
				f = 1;
			}
			print $0;
		} else {
			if (index($0,"/init-param") > 0){
				f = 0;
				print $0;
				printf "        <init-param>\n";
				printf "          <param-name>cookieAttributes</param-name>\n";
				printf "          <param-value>SameSite=None; Secure</param-value>\n";
				printf "        </init-param>\n";
			} else {
				print $0;
			}
		}
	}
' > $DIR/tracking/chrome-$hostName-web.xml.new
  scp $DIR/tracking/chrome-$hostName-web.xml.new $hostName:/var/tmp/chrome-$hostName-web.xml.new
  ssh ${sshOpts} -t -t $hostName " sudo scp /var/tmp/chrome-$hostName-web.xml.new $activeIp:/bigmac/cpq/bigmachines/WEB-INF/web.xml.new " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " sudo ssh $activeIp 'mv /bigmac/cpq/bigmachines/WEB-INF/web.xml /bigmac/cpq/bigmachines/WEB-INF/web.xml-$ts; mv /bigmac/cpq/bigmachines/WEB-INF/web.xml.new /bigmac/cpq/bigmachines/WEB-INF/web.xml; chown bm:ecom /bigmac/cpq/bigmachines/WEB-INF/web.xml' " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " sudo /bigmac/bin/cpqctl restart server " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " rm -f /var/tmp/chrome-$hostName-web.xml.new " 2>/dev/null 
  sudo chmod 777 $DIR/tracking/chrome-$hostName-web.xml.new $DIR/tracking/chrome-$hostName-web.xml-$ts 2>/dev/null
else
  echo "web.xml fix already in place"
  rm -f $DIR/tracking/chrome-$hostName-web.xml-$ts
fi

ssh ${sshOpts} -t -t $hostName " stty -onlcr; sudo ssh $activeIp 'cat /bigmac/apache_conf/httpd.conf' "  > $DIR/tracking/chrome-$hostName-httpd.conf-$ts 2>/dev/null 
if [ $( grep -c "SameSite=None" $DIR/tracking/chrome-$hostName-httpd.conf-$ts ) -eq 0 ]; then
  sudo rm -f $DIR/tracking/chrome-$hostName-httpd.conf.new
  cp $DIR/tracking/chrome-$hostName-httpd.conf-$ts $DIR/tracking/chrome-$hostName-httpd.conf.new
  printf "\n # Added fix for Chrome\n Header edit Set-Cookie \"(.*)\" \"\$1; SameSite=None\"\n\n" >> $DIR/tracking/chrome-$hostName-httpd.conf.new
  scp  $DIR/tracking/chrome-$hostName-httpd.conf.new $hostName:/var/tmp/chrome-httpd-fix.conf 
  ssh ${sshOpts} -t -t $hostName " sudo ssh $activeIp 'mv /bigmac/apache_conf/httpd.conf /bigmac/apache_conf/httpd.conf-$ts; cp /bigmac/apache_conf/httpd.conf-$ts /bigmac/apache_conf/httpd.conf;' " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " sudo scp /var/tmp/chrome-httpd-fix.conf $activeIp:/bigmac/apache_conf/httpd.conf " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " sudo ssh $activeIp 'chown bm:ecom /bigmac/apache_conf/httpd.conf' " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " sudo /bigmac/bin/cpqctl restart ohs " 2>/dev/null 
  ssh ${sshOpts} -t -t $hostName " rm -f /var/tmp/chrome-$hostName-httpd.conf.new " 2>/dev/null 
  sudo chmod 777 $DIR/tracking/chrome-$hostName-httpd.conf.new $DIR/tracking/chrome-$hostName-httpd.conf-$ts 2>/dev/null
else
  echo "httpd.conf fix already in place"
  rm -f $DIR/tracking/chrome-$hostName-httpd.conf-$ts
fi
