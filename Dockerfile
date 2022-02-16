FROM ubuntu:20.04


# avoid debconf and initrd 
# 
ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ARG MARIADB_MAJOR=10.2
ENV MARIADB_MAJOR $MARIADB_MAJOR
ARG MARIADB_VERSION=1:10.2.41+maria~bionic
ENV MARIADB_VERSION $MARIADB_VERSION
ENV MYSQL_USER=admin \
    MYSQL_PASS=**Random** \
    ON_CREATE_DB=**False** \
    REPLICATION_MASTER=**False** \
    REPLICATION_SLAVE=**False** \
    REPLICATION_USER=replica \
    REPLICATION_PASS=replica
ENV MONGODB_VERSION=5.0

RUN apt-get update
RUN apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    wget
RUN wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -  && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/$MONGODB_VERSION multiverse" | tee /etc/apt/sources.list.d/mongodb-org-$MONGODB_VERSION.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        mongodb-org \
        && rm -rf /var/lib/apt/lists/*
RUN apt-get update
RUN apt-get install --no-install-recommends -y openssh-server software-properties-common postgresql-12 postgresql-client-12 postgresql-contrib mariadb-server supervisor lsof  telnet net-tools locales vim python python3-pip git\
&& rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y exim4-daemon-light telnet && \
    rm -rf /var/lib/apt/lists/*

# make /var/run/sshd
RUN mkdir /var/run/sshd

# apt config
ADD source.list /etc/apt/sources.list
ADD 25norecommends /etc/apt/apt.conf.d/25norecommends

# clean packages
RUN apt-get clean
RUN rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

# set root password
RUN echo "root:root" | chpasswd

# clean packages
RUN apt-get clean
RUN rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
RUN mkdir /docker-entrypoint-initdb.d

# setup mysql
ADD setupmysql.sh /setupmysql.sh
RUN chmod +x /setupmysql.sh
COPY my.cnf /etc/mysql/my.cnf
#RUN /etc/init.d/mysql start &&\
#    sleep 10 &&\
#    echo "CREATE USER 'root'@'%' IDENTIFIED BY 'root';GRANT ALL ON *.* TO root@'%'; FLUSH PRIVILEGES" | mysql &&\
#    echo "CREATE USER 'newuser'@'%' IDENTIFIED BY 'root_password';GRANT ALL ON *.* TO newuser@'%'; FLUSH PRIVILEGES" | mysql
COPY mysql/mysqlinitdb.sql /tmp/mysqlinitdb.sql
COPY populatemysql.sh /populatemysql.sh
RUN chmod +x /populatemysql.sh
COPY mysql/startmysql.sh /startmysql.sh
RUN chmod a+x /startmysql.sh

# setup postgresql
USER postgres

# Create a PostgreSQL role named ``docker`` with ``docker`` as the password and
# then create a database `docker` owned by the ``docker`` role.
# Note: here we use ``&&\`` to run commands one after the other - the ``\``
#       allows the RUN command to span multiple lines.
#RUN    /etc/init.d/postgresql start &&\
#    psql --command "CREATE USER docker WITH SUPERUSER PASSWORD 'docker';" &&\
#    createdb -O docker fakeapi
COPY postgres/setuppostgresql.sh /setuppostgresql.sh


# Adjust PostgreSQL configuration so that remote connections to the
# database are possible.
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/12/main/pg_hba.conf

RUN echo "listen_addresses='*'" >> /etc/postgresql/12/main/postgresql.conf
COPY postgres/pgdump.sql /tmp/pgdump.sql
COPY populatepostgres.sh /populatepostgres.sh

#RUN /populatepostgres.sh

USER root
#configure mongodb
RUN sed -i 's/^\( *bindIp *: *\).*/\10.0.0.0/' /etc/mongod.conf
RUN /usr/bin/mongod --config /etc/mongod.conf --dbpath /var/lib/mongodb/ --logpath /var/log/mongodb/mongod.log &
#RUN sleep 10
RUN mkdir -p /sample_airbnb/sample_airbnb
COPY mongo/* /sample_airbnb/sample_airbnb/


#setup python packages
RUN mkdir /restserver
ADD restserver/restserver.py /restserver/restserver.py
ADD restserver/requirements.txt /restserver/requirements.txt
RUN pip install -r /restserver/requirements.txt
COPY restserver/startrestserver.sh /startrestserver.sh


#Setup smtp server
COPY exim/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf

#Setup Git server
RUN ssh-keygen -A
WORKDIR /git-server/
RUN mkdir /git-server/keys 
RUN adduser  --shell /usr/bin/git-shell git 
RUN echo git:12345 | chpasswd
RUN mkdir /home/git/.ssh
COPY git-server/git-shell-commands /home/git/git-shell-commands
COPY git-server/sshd_config /etc/ssh/sshd_config
COPY git-server/start.sh start.sh

# Expose the port
EXPOSE 3306 5432 3307 27017 5001 25 22

COPY startupscript.sh /startupscript.sh
RUN chmod +x /startupscript.sh

# Add VOLUMEs to allow backup of config, logs and databases
VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql","/var/lib/mysql" ,"/data/db","/data/configdb","/data/logs","/data/backup/mongodb"]

# copy supervisor conf
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# start supervisor
CMD ["/usr/bin/supervisord"]
