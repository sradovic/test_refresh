#!/bin/bash
#
testCase=$1
currentJdbcIp=`ssh -t -t $testCase "
        stty -onlcr ; grep url /bmfs/cpqShared/conf/database.properties | sed -e 's/.*(HOST\=//' | sed -e 's/).*//' ;
"`
currentJdbcHost=$( host ${currentJdbcIp} | cut -f 5 -d ' ' | sed -e 's/\.$//' );
if [ $( echo ${currentJdbcHost} | grep -c scan ) == 0 ]; then
        newJdbcIp=$( ssh -t -t ${currentJdbcIp} "stty -onlcr; ( sudo -iu oracle /usr/local/orabin/findScanAddr.sh 2>/dev/null) " | tail -1 );
        echo "Current JDBC string points to ${currentJdbcHost} and thus needs to be adjusted";
        echo "New JDBC IP: ${newJdbcIp}";
        ssh -t -t $testCase "
                tS=\$(date +%Y%m%d%H%M%S)
                cp -f /bmfs/cpqShared/conf/database.properties /var/tmp/database.properties_bad-\${tS};
                sudo sed -i -e \"s/$currentJdbcIp/$newJdbcIp/\" /bmfs/cpqShared/conf/database.properties;
                g_version=\$( sed -n 's/^bigmac.version=//p' /bigmac/conf/build.properties );
                echo \"g_version: \${g_version}\";
                if [[ \${g_version} =~ \"18.3.\" || \${g_version} < \"18.3.\" ]]; then
                        /root/bigmac stop;
                        sudo cat /bigmac/Oracle/Middleware/latest/user_projects/domains/*/config/jdbc/cpqDataSource-3561-jdbc.xml > /var/tmp/cpqDataSource-3561-jdbc.xml_bad-\${tS};
                        sudo -i sed -i -e \"s/$currentJdbcIp/$newJdbcIp/\" /bigmac/Oracle/Middleware/latest/user_projects/domains/*/config/jdbc/cpqDataSource-3561-jdbc.xml;
                        /root/bigmac start;
                else
                        sudo /bigmac/bin/cpqctl stop;
                        containerIp=\$(sudo /bigmac/container-setup/history.sh -i ACTIVE);
                        sudo -i ssh \${containerIp} \"cat /bigmac/Oracle/Middleware/latest/user_projects/domains/*/config/jdbc/cpqDataSource-3561-jdbc.xml \"  > /var/tmp/cpqDataSource-3561-jdbc.xml_bad;
                        sudo -i ssh \${containerIp} \"sed -i -e \\\"s/$currentJdbcIp/$newJdbcIp/\\\" /bigmac/Oracle/Middleware/latest/user_projects/domains/*/config/jdbc/cpqDataSource-3561-jdbc.xml \";
                        sudo /bigmac/bin/cpqctl start;
                fi
        "
else
        echo "Site is already using a scan address of ${currentJdbcIp}. No fix needed.";
fi

