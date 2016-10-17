L_PG_HOME ?= /usr/local/pgsql/bin
PG_PORT ?= 5432
PG_DATAS ?= PG10_DATAS
PG_AUTH ?= md5
PG_LOGFILE ?= logfile
PG_USER ?= $(USER) 
CONF ?= .conf
CERTS_DIR ?= certs
CERTS_DAYS ?= 365
OPENSSL ?= openssl
SYS_TYPE ?= $(shell uname)
SED_I ?= ".bkg"

test:
	@echo $(SYS_TYPE)
	@echo $(SED_I)

_certs:
	mkdir -p $(CERTS_DIR)
	$(OPENSSL) genrsa -out $(CERTS_DIR)/localhost.key 2048
	$(OPENSSL) req -new -config $(CONF)/localhost_csr.conf -key  $(CERTS_DIR)/localhost.key -out  $(CERTS_DIR)/localhost.csr
	$(OPENSSL) x509 -req -days $(CERTS_DAYS) -in $(CERTS_DIR)/localhost.csr -signkey $(CERTS_DIR)/localhost.key -out $(CERTS_DIR)/localhost.crt
	$(OPENSSL) genrsa -out $(CERTS_DIR)/1_localhost.key 2048
	$(OPENSSL) req -new -config $(CONF)/localhost_csr.conf -key  $(CERTS_DIR)/1_localhost.key -out  $(CERTS_DIR)/1_localhost.csr
	$(OPENSSL) x509 -req -days $(CERTS_DAYS) -in $(CERTS_DIR)/1_localhost.csr -signkey $(CERTS_DIR)/1_localhost.key -out $(CERTS_DIR)/1_localhost.crt
	$(OPENSSL) genrsa -out $(CERTS_DIR)/2_localhost.key 2048
	$(OPENSSL) req -new -config $(CONF)/localhost_csr.conf -key  $(CERTS_DIR)/2_localhost.key -out  $(CERTS_DIR)/2_localhost.csr
	$(OPENSSL) x509 -req -days $(CERTS_DAYS) -in $(CERTS_DIR)/2_localhost.csr -signkey $(CERTS_DIR)/2_localhost.key -out $(CERTS_DIR)/2_localhost.crt

_init_db: _certs
	$(L_PG_HOME)/initdb -D $(PG_DATAS) -U $(PG_USER) --pwfile $(CONF)/pwd.conf --auth=$(PG_AUTH)

init_db: _init_db
	sed -i $(SED_I) "s/#port = 5432/port = 5432/g" $(PG_DATAS)/postgresql.conf
	sed -i $(SED_I) "s/#wal_level = minimal/wal_level = hot_standby/g" $(PG_DATAS)/postgresql.conf
	sed -i $(SED_I) "s/#unix_socket_directories/unix_socket_directories/g" $(PG_DATAS)/postgresql.conf
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS) -l $(PG_LOGFILE) start
	sleep 5
	@echo ""
	@echo "password is:"
	@cat $(CONF)/pwd.conf
	@echo ""
	psql -U $(PG_USER) -p 5432 postgres < $(CONF)/create_master_user.sql
	psql -U $(PG_USER) -p 5432 postgres < $(CONF)/pg_bkg.sql
	echo "host	replication	repuser	127.0.0.1/32	md5" >> $(PG_DATAS)/pg_hba.conf
	echo "local	replication	repuser		md5" >> $(PG_DATAS)/pg_hba.conf
	sed -i $(SED_I) "s/#max_wal_senders = 0/max_wal_senders = 4/g" $(PG_DATAS)/postgresql.conf
	sed -i $(SED_I) "s/#synchronous_standby_names = ''/synchronous_standby_names = 'standby01,standby02'/g" $(PG_DATAS)/postgresql.conf
	sed -i $(SED_I) "s/#hot_standby = off/hot_standby = on/g" $(PG_DATAS)/postgresql.conf
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS) -l $(PG_LOGFILE) stop
	sleep 3
	sed -i $(SED_I) "s/#ssl = off/ssl = on/g" $(PG_DATAS)/postgresql.conf
	cp -r $(PG_DATAS) $(PG_DATAS)_1
	cp -r $(PG_DATAS) $(PG_DATAS)_2
	cp $(CERTS_DIR)/localhost.crt $(PG_DATAS)/server.crt
	cp $(CERTS_DIR)/1_localhost.crt $(PG_DATAS)_1/server.crt
	cp $(CERTS_DIR)/2_localhost.crt $(PG_DATAS)_2/server.crt
	cp $(CERTS_DIR)/localhost.key $(PG_DATAS)/server.key
	cp $(CERTS_DIR)/1_localhost.key $(PG_DATAS)_1/server.key
	cp $(CERTS_DIR)/2_localhost.key $(PG_DATAS)_2/server.key
	cp $(CONF)/recovery.conf.01 $(PG_DATAS)_1/recovery.conf
	cp $(CONF)/recovery.conf.02 $(PG_DATAS)_2/recovery.conf
	sed -i $(SED_I) "s/port = 5432/port = 5433/g" $(PG_DATAS)_1/postgresql.conf
	sed -i $(SED_I) "s/port = 5432/port = 5434/g" $(PG_DATAS)_2/postgresql.conf
	chmod 0000 */server.key
	chmod 0600 */server.key

restart:
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS) -l $(PG_LOGFILE) restart
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS)_1 -l $(PG_LOGFILE)_1 restart
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS)_2 -l $(PG_LOGFILE)_2 restart

start:
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS) -l $(PG_LOGFILE) start
	sleep 5
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS)_1 -l $(PG_LOGFILE)_1 start
	$(L_PG_HOME)/pg_ctl -D $(PG_DATAS)_2 -l $(PG_LOGFILE)_2 start

clean:
	rm -rf $(PG_DATAS)
	rm -rf $(PG_DATAS)_1
	rm -rf $(PG_DATAS)_2
	rm -f $(PG_LOGFILE)
	rm -f $(PG_LOGFILE)_1
	rm -f $(PG_LOGFILE)_2
	rm -rf $(CERTS_DIR)
stop:
	$(L_PG_HOME)/pg_ctl stop -D $(PG_DATAS)
	$(L_PG_HOME)/pg_ctl stop -D $(PG_DATAS)_1
	$(L_PG_HOME)/pg_ctl stop -D $(PG_DATAS)_2

all: start_db

