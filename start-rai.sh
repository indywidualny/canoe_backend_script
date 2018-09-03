#!/bin/sh
/bin/systemctl start rai_node

JSON='{"action":"version"}'

# Then wait until it responds on RPC
while true
do
    curl --fail --connect-timeout 2 --max-time 5 -s -g -d $JSON '[::1]:7076'
    if [ $? -ne 0 ]
    then
        # curl didn't return 0 - failure
        echo $i
        printf '.'
        sleep 5
    else
        break # terminate loop
    fi
done
printf 'node running'
