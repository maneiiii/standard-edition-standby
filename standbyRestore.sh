#!/bin/bash
#############################################################
# Author : Mariano Urroz                                   ##
# Description : This script is developed for manual        ##
#               Standby database configuration for         ##
#               standard edition databases. It will        ##
#               restore a  database.                       ##
#############################################################

##
## Current user executing the script
##
RESTORE_USER=`whoami`

##
## Env for locating full path of the script being executed
##
CURSCRIPT=`readlink -f $0`
SCRIPTDIR=$(readlink -e $(dirname $0))

##
## Load init vars
##
source $SCRIPTDIR/standbyRestore.ini

##
## For Warning and Text manupulation
##
bold=$(tput bold)
reset=$(tput sgr0)
bell=$(tput bel)
underline=$(tput smul)

#############################################################
# Functions to handle exceptions and erros                  #
#############################################################

###
### Handling error while running script
###
### $1 : Error Code
### $2 : Error message in detail
###

ReportError(){
        if [ "${3}" != "" ]
                then
                        echo "" >> ${RESTORE_LOG_FILE}
                        echo "########################################################" >> ${RESTORE_LOG_FILE}
                        echo -e "Error during Running Script :\n$CURSCRIPT" >> ${RESTORE_LOG_FILE}
                        echo -e "$1: $2" >> ${RESTORE_LOG_FILE}
                        echo "########################################################" >> ${RESTORE_LOG_FILE}
                        echo "" >> ${RESTORE_LOG_FILE}
                        exit 1;
        else
                        echo "########################################################"
                        echo "Error during Running Script : $CURSCRIPT"
                        echo -e "$1: $2"
                        echo "########################################################"
                        exit 1;
        fi
}

###
### Dispalying information based on input of user 
### OR
### Status of script while running.
###

ReportInfo(){
        if [ "${2}" != "" ]
                then
                        echo "" >> ${RESTORE_LOG_FILE}
                        echo "########################################################" >> ${RESTORE_LOG_FILE}
                        echo -e "Information by the script :\n$CURSCRIPT\n" >> ${RESTORE_LOG_FILE}
                        echo -e "INFO : $1 " >> ${RESTORE_LOG_FILE}
                        echo "########################################################" >> ${RESTORE_LOG_FILE}
                        echo "" >> ${RESTORE_LOG_FILE}
        else
                        echo "########################################################"
                        echo "Information by the script : $CURSCRIPT"
                        echo -e "INFO : $1 "
                        echo "########################################################"
        fi
}

###
### FUNCTION TO CHECK FUNDAMENTAL VARIABLES
###

CheckVars(){
        if [ "${1}" = "" ]
        then
                ReportError "RERR-001" "${bell}${bold}${underline}ORACLE_HOME${reset} Env variable not Set. Aborting...." "Y"

        elif [ ! -d ${1} ]
        then
                ReportError "RERR-002" "Directory \"${bell}${bold}${underline}${1}${reset}\" not found or ORACLE_HOME Env invalid. Aborting...." "Y"

        elif [ ! -x ${1}/bin/sqlplus ]
        then
                ReportError  "RERR-003" "Executable \"${bell}${bold}${underline}${1}/bin/sqlplus${reset}\" not found; Aborting..." "Y"

        elif [ "${2}" = "" ]
        then
                ReportError  "RERR-004" "${bell}${bold}${underline}ORACLE_SID${reset} Env variable not Set. Aborting..." "Y"

        elif [ "${3}" != "oracle" ]
        then
                ReportError  "RERR-004" "User "${bell}${bold}${underline}${2}${reset}" not valid for running script; Aborting..." "Y"

#        elif [ "${4}" = "" ]
#        then
#                ReportError "RERR-001" "${bell}${bold}${underline}RECOVERY_ARCH_DIR${reset} Env variable not Set. Aborting...." "Y"

#        elif [ ! -d ${4} ]
#        then
#                ReportError "RERR-002" "Directory \"${bell}${bold}${underline}${4}${reset}\" not found or RECOVERY_ARCH_DIR Env invalid. Aborting...." "Y"

        else
                return 0;
        fi
}

checkSidValid(){
        param1=("${!1}")
        check=${2}
        statusSID=0
        for i in ${param1[@]}
                do
                        if [ ${i} == $2 ];
                                then
                                statusSID=1
                                break
                        esle
                echo $i;
                        fi
        done
    return $statusSID;
}

###
### Get Oracle SID env 
###
FunGetOracleSID(){
myarr=($(ps -ef | grep ora_smon| grep -v grep | awk -F' ' '{print $NF}' | cut -c 10-))
checkSidValid myarr[@] ${ORACLE_SID}
if [ $? -eq 0 ]
        then
                ReportError  "\nRERR-005" "ORACLE_SID : ${bell}${bold}${underline}${ORACLE_SID}${reset} Env is invalid, no instance is running. Aborting..." "Y"
fi

ReportInfo "\nChecking for validness for ORACLE_SID: ${bell}${bold}${underline}${ORACLE_SID}${reset} passed....." "Y"
}

###
### Get the Database open mode...
###
FunGetDBmode(){
DBMODE=$($1/bin/sqlplus -s /nolog <<END
set pagesize 0 feedback off verify off echo off;
connect / as sysdba
select open_mode from v\$database;
END
)
}

###
### Shutdown the instance
###
FunShutdownDB(){
case ${2} in
    I|i )
        ReportInfo "${3}" "Y"
        $1/bin/sqlplus -s /nolog <<EOF >> ${RESTORE_LOG_FILE}
        set pagesize 0 feedback off verify off echo off;
        connect / as sysdba
        shutdown immediate;
EOF
        ;;

        A|a )
        ReportInfo "${3}" "Y"
        $1/bin/sqlplus -s /nolog <<EOF
        set pagesize 0 feedback off verify off echo off;
        connect / as sysdba
        shutdown abort;
EOF
        ;;

    * )
        ReportInfo "${3}" "Y"
    ;;
esac

}

###
### Start the database
###
FunStartDB(){
case ${2} in
    n|N )
        ReportInfo "${3}" "Y"
        $1/bin/sqlplus -s /nolog <<EOF >> ${RESTORE_LOG_FILE} 
        set pagesize 0 feedback off verify off echo off;
        connect / as sysdba
        startup nomount pfile=${RESTORE_PFILE};
EOF
        ;;

        m|M )
        ReportInfo "${3}" "Y"
        $1/bin/sqlplus -s /nolog <<EOF >> ${RESTORE_LOG_FILE}
        set pagesize 0 feedback off verify off echo off;
        connect / as sysdba
        startup mount pfile=${RESTORE_PFILE};
EOF
        ;;


        r|R )
        ReportInfo "${3}" "Y"
        $1/bin/sqlplus /nolog <<EOF >> ${RESTORE_LOG_FILE}
        set pagesize 0 verify off echo off;
        connect / as sysdba
        startup mount restrict pfile=${RESTORE_PFILE};
EOF
        ;;


    * )
        ReportInfo "Startup of instance skipped......." "Y"
    ;;
esac

}

###
### Function to very the schedule
###
FunVerifySchedule(){
count=`crontab -l | grep "${1}" | grep -v grep | wc -l`
   if [ ${count} = '1' ]
        then
        return 0;
   else
        return 1;
   fi
}

###
### Function to enable disable scheduling
###
FunHandleSchedule(){
    if [ ${1} = 'D' ]
        then
                        ReportInfo "Disabling Schedule job for recovery ........." "Y"
                        # Backing up crontab entries before any changes take palce
                        crontab -l | grep "startrecovery ${ORACLE_SID}" | grep -v grep > ${RECOVERY_LOG_DIR}/temp/crontab${ORACLE_SID}.tmp
                        # delete the corntab entries for specific ORACLE_SID
                        crontab -l | grep -v "startrecovery ${ORACLE_SID}" | grep -v grep | crontab

        elif [ ${1} = 'E' ]
                then
                        ReportInfo "Enabling Schedule job for recovery ........." "Y"
                        crontab -l >> ${RECOVERY_LOG_DIR}/temp/crontab${ORACLE_SID}.tmp
                        cat ${RECOVERY_LOG_DIR}/temp/crontab${ORACLE_SID}.tmp | crontab
                        #crontab -l | awk '{print} END {system("cat ${RECOVERY_LOG_DIR/temp/crontab.tmp | grep \"startrecovery ${ORACLE_SID}\"") }' | crontab
                        #crontab -l | awk '{print} END {print "*/15 * * * * /archive/standbyscripts/recover.sh"}' | crontab

        else
                        ReportError "NEP-001" ${bell}${bold}${underline}"Scheduling status cannot be determined."${reset}" Aborting...." "Y"
        fi
}

###
### Function to apply archived logs - Added by murroz (maneiiii)
###
FunRestoreDatabase(){
ReportInfo "${2}" "Y"
${1}/bin/rman target / >> /dev/null <<EOF >> ${RESTORE_LOG_FILE}
run {
allocate channel c1 device type disk;
restore standby controlfile from '${RESTORE_RMAN_DIR}/${RESTORE_RMAN_CTL_FILE}';
alter database mount;
catalog start with '${RESTORE_RMAN_DIR}' noprompt;
set newname for database to '+DATA/${ORACLE_SID}/DATAFILE/%b';
restore database;
SWITCH DATAFILE ALL;
SWITCH TEMPFILE ALL;
}
exit;
EOF
}

###
### Function to check archive applied status
###
FunDropDB(){
ReportInfo "${2}" "Y"
${1}/bin/sqlplus -s / as sysdba <<EOF >> ${RESTORE_LOG_FILE}
drop database;
exit;
EOF
}

###
### Renaming redo logs.
###
FunClearLogfiles(){
ReportInfo "${2}" "Y"

SQLOUT=$($1/bin/sqlplus -s /nolog <<END
set pagesize 0 feedback off verify off echo off;
connect / as sysdba
select 'alter database clear logfile group '||group#||';' from v\$logfile group by group# order by 1;
END
)

ReportInfo "${SQLOUT}" "Y"

$1/bin/sqlplus -s /nolog <<END
set pagesize 0 feedback off verify off echo off;
connect / as sysdba
${SQLOUT}
END

#echo ${SQLOUT}
}

###
### Function to create spfile in ASM
###
FunCreateSpfile(){
ReportInfo "${2}" "Y"
${1}/bin/sqlplus -s / as sysdba <<EOF >> ${RESTORE_LOG_FILE}
create spfile='+DATA/${ORACLE_SID}/spfile${ORACLE_SID}.ora' from pfile='${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora.dup';
exit;
EOF
}

###
### Starting DB with srvctl
###
FunStartDBsrvctl(){
ReportInfo "${2}" "Y" 
${1}/bin/srvctl enable database -d ${ORACLE_SID}
${1}/bin/srvctl start database -d ${ORACLE_SID}
}


###
### Stop DB with srvctl
###
FunStopDBsrvctl(){
ReportInfo "${2}" "Y"
${1}/bin/srvctl stop database -d ${ORACLE_SID}
${1}/bin/srvctl disable database -d ${ORACLE_SID}
}

###
### Question start
###
function ConfirmStart() {
    local DB_NAME=$1
    read -p "ATENCION: Este script alterara la base `echo -e "\e[1m${DB_NAME}\e[0m"`. Continua? y/n: " answer
    if [ "$answer" != "${answer#[Yy]}" ]
    then
        echo
    else
        echo "Exiting..."
        exit 0
    fi
}


###
### MAIN BODY
###

ConfirmStart ${ORACLE_SID}

CheckVars ${ORACLE_HOME} ${ORACLE_SID} ${RESTORE_USER}
ReportInfo "\nChecking fundamental variables passed....." "Y"
#FunGetOracleSID

FunStopDBsrvctl ${ORACLE_HOME} "n" "Stopping database instance ${ORACLE_SID}"
FunShutdownDB ${ORACLE_HOME} "a" "Shutting down abort Database instance ${ORACLE_SID} ....."
FunStartDB ${ORACLE_HOME} "r" "Starting database instance ${ORACLE_SID} in restricted mode ....."
FunDropDB ${ORACLE_HOME} "Dropping Database instance ${ORACLE_SID} ....."
FunShutdownDB ${ORACLE_HOME} "a" "Shutting down abort Database instance ${ORACLE_SID} ....."
FunStartDB ${ORACLE_HOME} "n" "Starting database instance ${ORACLE_SID} in nomount mode ....."
FunRestoreDatabase ${ORACLE_HOME} "Restoring Database instance ${ORACLE_SID} ....."
FunClearLogfiles ${ORACLE_HOME} "Clearing redo log files...."
FunCreateSpfile ${ORACLE_HOME} "Create spfile on ASM and starting db with srvctl"
FunShutdownDB ${ORACLE_HOME} "i" "Shutting down immediate Database instance ${ORACLE_SID} ....."
FunStartDBsrvctl ${ORACLE_HOME} "n" "Starting database instance ${ORACLE_SID} in mount mode ....."

ReportInfo "\nEND....." "Y"
