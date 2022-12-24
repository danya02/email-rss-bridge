#Dockerfile for a Postfix email relay service

# Used from https://github.com/juanluisbaptiste/docker-postfix under GPLv3

FROM alpine:3.15

RUN apk update && \
    apk add bash gawk cyrus-sasl cyrus-sasl-login cyrus-sasl-crammd5 mailx \
    postfix && \
    rm -rf /var/cache/apk/* && \
    mkdir -p /var/log/supervisor/ /var/run/supervisor/ && \
    sed -i -e 's/inet_interfaces = localhost/inet_interfaces = all/g' /etc/postfix/main.cf

COPY redirect /etc/postfix/redirect

RUN adduser mailrcv -D

COPY run.sh /
RUN chmod +x /run.sh
COPY recv.sh /
RUN chmod +x /recv.sh
RUN newaliases


EXPOSE 25
#ENTRYPOINT ["/run.sh"]
CMD ["/run.sh"]