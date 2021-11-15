FROM centos:8
RUN yum install -y epel-release createrepo yum-utils
ADD repos/* /etc/yum.repos.d/
ADD syncrepos.sh /syncrepos.sh
CMD /syncrepos.sh
