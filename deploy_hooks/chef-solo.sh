#!/bin/bash

cd /var/www/test-app
rm -rf site-cookbooks/test-app
mkdir -p site-cookbooks/test-app
cp -rf recipes site-cookbooks/test-app/
cp metadata.rb site-cookbooks/test-app/
berks vendor site-cookbooks

/usr/bin/env chef-solo -c chef/solo.rb -j chef/node.json
