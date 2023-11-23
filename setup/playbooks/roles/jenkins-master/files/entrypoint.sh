#!/bin/bash

chown -R jenkins:jenkins /var/jenkins_home
gosu jenkins /usr/bin/tini -- /usr/local/bin/jenkins.sh
