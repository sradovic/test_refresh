#!/bin/bash
getArgs() {
        while [[ ${#} > 0 ]]; do
                local l_arg="${1}";
                case ${l_arg} in
				
			-t)
                                echo " Pre ${#} "
                                if [[  ${#} -eq 1 ]]; then printf "Missing required arg for option -t. Aborting"; exit 1; fi
			   	SITE=${2};
				shift 2;
				;;
                        -b)
                                b='-b';
                                shift 1;
                                ;;
								
			-i)
                                if [[  ${#} -eq 1 ]]; then printf "Missing required arg for option -i. Aborting"; exit 1; fi
				image=${2};
				firstchar=`echo $image | cut -c1-1`
                                echo "Prvi character je $firstchar"
                                if [[ $firstchar = "-" ]]; then  echo "Missing required arg for option -i. Aboorting"; exit 1; fi
				path="no";
				shift 2;
				;;
                        *)
                                echo "!!!! Unknown argument: ${2}";
                                usage;
                                return 1;
                                ;;
                esac;
        done;
}

main () {
getArgs "${@}"
echo "$b"
echo "image $image"
echo "Site is $SITE"
}
time main "${@}" || exit ${?};
