FROM registry.access.redhat.com/rhel7
#RUN yum install -y createrepo  yum-utils
ADD repos/* /etc/yum.repos.d/
ADD syncrepos.sh /syncrepos.sh
CMD /syncrepos.sh
