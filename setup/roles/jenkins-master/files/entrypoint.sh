#!/bin/bash

chown -R jenkins:jenkins /var/jenkins_home
gosu jenkins /sbin/tini -- /usr/local/bin/jenkins.sh
