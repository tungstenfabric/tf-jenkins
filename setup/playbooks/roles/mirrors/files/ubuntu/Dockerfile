FROM ubuntu:20.04
RUN apt-get update && apt-get install -y apt-mirror
ADD mirror.list /etc/apt/mirror.list
ADD sources.list /sources.list
ADD syncrepos.sh /syncrepos.sh
ADD apt-mirror-20 /apt-mirror-20
RUN chmod a+x /apt-mirror-20
CMD /syncrepos.sh
