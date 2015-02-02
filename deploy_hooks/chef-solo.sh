#!/bin/bash

cd /var/www/test-app
if [ -e metadata.rb ]; then
  mkdir -p site-cookbooks/test-app
  mv recipes site-cookbooks/test-app/
  mv metadata.rb site-cookbooks/test-app/
fi
berks vendor site-cookbooks

/usr/bin/env chef-solo -c chef/solo.rb -j chef/node.json
