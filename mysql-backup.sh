#!/bin/bash
################################################################################
## DATE: 2012-05-09
## AUTHOR: Flo Schuessel
## WEBSITE: https://github.com/staticsirupflo/mysql-tools
## EMAIL: fs@iltisworld.de
## DATE: 2009-08-02
## AUTHOR: Matt Reid
## WEBSITE: http://kontrollsoft.com
## EMAIL: themattreid@gmail.com
## LICENSE: BSD http://www.opensource.org/licenses/bsd-license.php
################################################################################
## Copyright 2008 Matt Reid
## All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
##################################################################################
## WHAT THIS SCRIPT DOES #########################################################
# Runs a backup for MySQL databases with given options
##################################################################################
# Suggested CRONTAB entry:
# 02 03 * * * * /usr/local/bin/mysql-backup.sh /home/me/mysql-backup.cfg  > /dev/null 2>&1
##################################################################################
if [ "$1" == "" ]; then
    echo "No config filename passed."
    exit 1
fi
if [ ! -f "$1" ]; then
    echo "Config file could not be loaded."
    exit 1
fi
source $1
##################################################################################
# Do not edit below here #                                                                                                      
##################################################################################
CHOST="$HOSTNAME"
ASQLFILE="/tmp/mysql-backup-tmp"
MTIME="+3"
MONTHDAY=`date +'%d'` #looking for 01 for 1st day of month
WEEKDAY=`date +'%u'` #looking for 7 for Sunday

BINARY=`which mysqldump`
TAR_BINARY=`which tar`
test -d $DUMP_ARCHIVE || mkdir $DUMP_ARCHIVE
DT=`date +%G%m%d%H%M%S`
MAIL_DT=`date +"%d/%m/%G %H:%M:%S"`
#sql file testing                                                                                                         
test -d ${ASQLFILE} || mkdir -p ${ASQLFILE}
/bin/rm -f ${ASQLFILE}/*
SQLFILE="${ASQLFILE}/${SEC}.sql"
test -e ${SQLFILE} || touch ${SQLFILE}

function mailer {
    STATUS=$1
    SIZE=$2
	DB=$3
	FILE=$4
    echo -e "$STATUS for $CLIENTNAME - $CHOST\nSize: $SIZE\nDatabase: $DB\nDate: $MAIL_DT\nFile: $FILE" | mail -s "MySQL Backup: $STATUS $MAIL_DT" $EMAIL
    log "Emailed backup report to $EMAIL"
}

function backup {
    log ""
    log "Beginning daily backup procedure at `date`"
    if [ "$MONTHDAY" = "01" ]; then
    	DUMP_ARCHIVE="${DUMP_ARCHIVE}/monthly"
    	test -d ${DUMP_ARCHIVE} || mkdir -p ${DUMP_ARCHIVE}
    	MTIME="+90"
    fi
    if [ "$WEEKDAY" = "7" ]; then
        DUMP_ARCHIVE="${DUMP_ARCHIVE}/weekly"
	    test -d ${DUMP_ARCHIVE} || mkdir -p ${DUMP_ARCHIVE}
        MTIME="+30"
    fi

    find $DUMP_ARCHIVE/*dump*sql -mtime $MTIME -exec rm {} \; > /dev/null 2>&1
    if [ "$COMPRESS" = "1" ]; then
	    find $DUMP_ARCHIVE/*dump*gz -mtime $MTIME -exec rm {} \; > /dev/null 2>&1
    fi
    for each in $DATABASES; do
    	if [ "$each" = "--all-databases" ]; then
    	    each="all-databases"
    	fi
    	log "Beginning backup of $each..."
    	START_SEC=`date +%s`
    	nice $BINARY --host=$HOST -u $USER --password="$PASS" $OPTIONS $DATABASES > $DUMP_ARCHIVE/$each-dump.${DT}.sql
    	DUMP_SEC=`date +%s`
    	if (( $COMPRESS == 1 )); then
    	    SQLFILE="$DUMP_ARCHIVE/$each-dump.${DT}.sql"
    	    STATE=`tail -n 1 ${SQLFILE} | awk -F "--" {'print $2'} | awk {'print $1 $2'}`
    	    if [ "${STATE}" = "Dumpcompleted" ]; then
    		    nice $TAR_BINARY -czf $DUMP_ARCHIVE/$each-dump.${DT}.tar.gz $DUMP_ARCHIVE/$each-dump.${DT}.sql  > /dev/null 2>&1 && rm -f $DUMP_ARCHIVE/$each-dump.${DT}.sql
        		COMPRESS_SEC=`date +%s`
        		FILE="$DUMP_ARCHIVE/$each-dump.${DT}.tar.gz"
        		SIZE=`du -h ${FILE} | cut -f 1 -d "/"`
        		SIZE_byte=`du ${FILE} | cut -f 1 -d "/"`
        		if test -e ${FILE}; then
                    SIZE_KB=`du -k ${FILE} | cut -f 1 -d "/"`
                    if (( "$EMAILENABLE" == 1 )); then
                        mailer "SUCCESS" "${SIZE_KB} KB GZIP" "$each" "${FILE}"
                    fi
        		    STATUSID="1"
        		    #compute timing
        		    DUMP_DELTA=`expr $DUMP_SEC - $START_SEC`
        		    COMPRESS_DELTA=`expr $COMPRESS_SEC - $DUMP_SEC`
        		    log "Data File size: $SIZE_byte"
        		    log "Data dump of $each database took $DUMP_DELTA seconds to complete."
        		    log "Dump compression of $each database took $COMPRESS_DELTA seconds to complete."
        		    log "Backup procedure complete at `date`"
        		else
                    if (( "$EMAILENABLE" != 0 )); then
        		        mailer "FAILED - File NULL" "${SIZE}" "$each" "n/a"
    		        fi
        		    STATUSID="3"
        		fi
    	    else 
                if (( "$EMAILENABLE" != 0 )); then
                    mailer "FAILED - NOT COMPLETE" "NULL" "$each" "n/a"
                fi
    		    STATUSID="2"
    	    fi
    	else
            FILE="$DUMP_ARCHIVE/$each-dump.${DT}.sql"
    	    STATE=`tail -n 1 ${FILE} | awk -F "--" {'print $2'} | awk {'print $1 $2'}`
    	    echo "##### $STATE #####"
                if [ "${STATE}" = "Dumpcompleted" ]; then
    		SIZE=`du -h ${FILE} | cut -f 1 -d "/"`
    		SIZE_byte=`du ${FILE} | cut -f 1 -d "/"`
    		if test -e ${FILE}; then
                        SIZE_KB=`du -k ${FILE} | cut -f 1 -d "/"`
                        mailer "SUCCESS" "${SIZE_KB} KB" "$each" "${FILE}"
    		    STATUSID="1"
    		    #compute timing
    		    DUMP_DELTA=`expr $DUMP_SEC - $START_SEC`
    		    log "Data File size: $SIZE_byte"
    		    log "Data dump of $each database took $DUMP_DELTA seconds to complete."
    		    log "Backup procedure complete at `date`"
    		else
                if (( "$EMAILENABLE" != 0 )); then
		            mailer "FAILED - File NULL" "${SIZE}" "$each" "n/a"
	            fi
    		    STATUSID="3"
    		fi
    	    else
                if (( "$EMAILENABLE" != 0 )); then
    		        mailer "FAILED - NOT COMPLETE" "NULL" "$each" "n/a"
		        fi
    		    STATUSID="2"
    	    fi
    	fi
    done
}

function log {
    MESSAGE=$1
    if (( $LOG == 1 )); then
        echo $MESSAGE >> $BACKUP_LOG
    fi
    if (( $SILENT == 0 )); then
        echo $MESSAGE
    fi
}    

function check_server {
    if [ "$HOST" = "localhost" ] || [ "$HOST" = "127.0.0.1" ]; then
	    pgrep mysql > /dev/null 2>&1
	    if test $? -eq 0 ; then
	        backup  #run backup function
	    else
            #database not running...probably on other node
	        log ""
	        log "Database not running on this node and localhost/127.0.0.1 was specified as HOST. Backup aborted."
	        log ""
	    fi
    else 
	    backup
    fi
    if (( $STATUSID == 1 )); then
        exit 0
    else 
        exit 1
    fi
}

check_server
