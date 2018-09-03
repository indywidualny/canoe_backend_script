#!/bin/sh
curl --connect-timeout 2 --max-time 5 -s -g -d '{"action":"version" }' '[::1]:7076'
