#!/bin/bash

# On debian-like system, use apt-get to install
for pkg in ruby2.0-dev ruby2.0 make autoconf g++ git; do
  aptitude show $pkg | grep -q 'State: installed'
  if [ $? != 0 ]; then
    apt-get -y install $pkg
  fi
done

# Don't install documentation for gems:
echo 'gem: --no-rdoc --no-ri' >> /etc/gemrc

# Now, we can install the required gems
for gem in chef ohai librarian-chef io-console berkshelf; do
  gem2.0 list | grep -q $gem
  if [ $? != 0 ]; then
    gem2.0 install $gem

    if [ $? != 0 ]; then
      echo "Failed to install required gems. Cannot continue with deployment"
      exit 1
    fi
  fi
done
