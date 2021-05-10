FROM ubuntu:20.04
RUN apt-get update && apt-get install -y apt-mirror
ADD mirror.list /etc/apt/mirror.list
ADD sources.list /sources.list
ADD syncrepos.sh /syncrepos.sh
CMD /syncrepos.sh
