#!/bin/bash

# First, make sure the tomcat cookbook is installed
cd /etc/chef/codedeploy/
/usr/bin/env librarian-chef install

/usr/bin/env chef-solo -c /etc/chef/codedeploy/solo.rb
